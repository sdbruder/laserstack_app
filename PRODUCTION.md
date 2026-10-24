# Can these images run a single app in production?

Checked image: `laserstack/app:8.5` (PHP 8.5.12, Alpine 3.24), built locally, plus the
published Docker Hub tags.

## Answer

No, not as they are. Use them as a base, not as a finished production image.

The image is a developer-workstation image. It serves every project of the host
through one wildcard vhost, it loads the Xdebug profiler, it runs as root, and it
carries the full development toolchain. The shape is right for one app per
container. The defaults are not.

## Blockers

| #  | Blocker | Evidence | Production effect |
| -- | ------- | -------- | ----------------- |
| 1  | The vhost only matches `*.test` host names | `nginx-site.conf`: `server_name "~^([^.]*\.){0,}(?P<project>[^.]+)\.test$"; root /var/www/$project/public;`. Smoke test: `Host: myapp.test` returns the app, `Host: app.example.com` returns `404 File not found.` | The real domain does not route. You must replace `/etc/nginx/http.d/nginx-site.conf`. |
| 2  | The document root comes from the request | Same directive: `root /var/www/$project/public` | A wrong or forged `Host` selects a different directory tree. Set a fixed root. |
| 3  | Xdebug runs in profile mode | `/etc/php85/conf.d/laser.ini`: `xdebug.mode=profile`, `xdebug.start_with_request=trigger`; `php -m` lists xdebug | Any client that sends the trigger (`?XDEBUG_TRIGGER`, session cookie) makes the app write cachegrind files and slow down. The overlay removes the extension and comments its loader lines. |
| 4  | The container runs as root | `Config.User` is empty; `id` in the container is `uid=0(root)`. User `laser` has an empty password (`/etc/shadow`: `laser::20750:...`) and a login shell; `sudo` is installed | An application compromise is a root compromise. Run the image with a non-root user. |
| 5  | No health check | `Config.Healthcheck` is `<nil>` | The orchestrator cannot tell when the app is ready. Add your own probe. |
| 6  | Tags move | `buildx.sh` pushes `laserstack/app:<major.minor>` and `latest`; `nightly-publish.yml` rebuilds at 01:00 UTC daily. Hub shows `7.4` pushed `2026-10-24T20:02` | A deploy of `8.5` today and tomorrow is not the same image. Pin `laserstack/app:8.5.12@sha256:<digest>`. Never use `latest`. |
| 7  | The base floats | `FROM alpine:3.24` plus `apk upgrade` in the Dockerfile; `8.6` uses `alpine:edge` | The content changes at every build, without a version change. |
| 8  | The runtime image carries the development toolchain | `sudo`, `git`, `vim`, `node`, `npm`, `yarn`, `composer`, `phpunit`, `psql`, `mysql`, `nc` are all present; the image is 314 MB in 9 layers | A large attack surface and a large CVE feed for a production container. |
| 9  | Access logs go to a file | `nginx -T`: `access_log /var/log/nginx/access.log main` (confirmed present in the container) and no `logrotate` is installed | `docker logs` does not show the access log, and the file grows until the disk is full. The php and nginx process logs do go to stdout, through supervisord. |
| 10 | PID 1 is supervisord | `ps` in the container: PID 1 `supervisord`, children `nginx`, `php-fpm85` | [INFERENCE] supervisord reaps only its own children. Use `docker run --init`, or a k8s pod, for processes the app spawns. |
| 11 | php-fpm fits a laptop, not a server | `www.conf`: `pm.max_children = 5`, `pm = dynamic`, `user = nobody`, `listen = 127.0.0.1:9000` | A concurrency ceiling of 5 requests. Every writable path (cache, sessions, storage, logs) must belong to `nobody`. |
| 12 | No supply-chain controls | No digest pinning in the Dockerfile, no signing, no SBOM, no vulnerability scan in the workflow | You cannot state what you deploy, or prove it. |
| 13 | Port 80, no TLS | `EXPOSE 80` | Terminate TLS at a proxy or load balancer, as usual. |
| 14 | Old series have no security support | `7.4`, `8.0`, `8.1` are end of life per the README table | Use `8.5`, or `8.3`/`8.4` when the app needs them. |
| 15 | The vhost serves dotfiles | With the shipped `8.5/nginx-site.conf`: `GET /.env` returns `200` and 24 bytes, `GET /.git/config` returns `200` | An exposed `.env` is an exposed application key. `examples/nginx/http.d/00-single-app.conf` answers `403`. |
| 16 | The body limit contradicts php.ini | Alpine `nginx.conf` sets `client_max_body_size 1m`; `php.ini` sets `upload_max_filesize = 100M`. The same 2 MiB upload: dev vhost `413`, `examples/nginx` `200` with `{"bytes":2097364}` | Uploads over 1 MiB fail at nginx, before PHP sees them. |
| 17 | No scheme handling behind a balancer | With `10-behind-proxy.conf`: `X-Forwarded-Proto: https` gives `{"https":"on"}`, without the header `{"https":""}`. The shipped config always reports plain HTTP | The app builds `http://` links and sets cookies without `Secure`. |
| 18 | PHP reports its version | Every response carries `X-Powered-By: PHP/8.5.12` | Write `expose_php = Off` into a `conf.d` file. |
| 19 | Any `*.php` path reaches php-fpm | `GET /missing.php` gives `404` from php-fpm, not from nginx | php-fpm closes the hole by itself. Add `try_files $uri =404;` for defence in depth, as the examples do. |

Not a problem: one app per container is exactly the shape of this image. The
image holds no application code, so you layer or mount the app at
`/var/www/<name>/public`.

## Minimum changes for one production app

1. Pin the digest: `FROM laserstack/app:8.5@sha256:<digest>`, and take the digest
   from a lock file. `prod/build.sh --update` writes it, `--check` reports a
   moved base tag.
2. Replace the vhost with a fixed root and a fixed `server_name`: take the set in
   `examples/nginx`, see the section below.
3. Remove Xdebug, and write `expose_php=Off` into a `conf.d` file.
4. Run as a non-root user, or keep the root container but keep the app code on a
   read-only mount owned by `nobody`.
5. Raise `pm.max_children` to the size of the host. The nginx logs already go to
   the container streams with `examples/nginx/nginx.conf`.
6. Add a health check that requests a known path, and pass `--init`.
7. Remove the development toolchain when you can, to shrink the CVE feed.
8. Scan and sign the result in CI, and keep the pinned base digest under review.

## prod overlay

`prod/` builds one production image for one app on top of a pinned base, and
applies the eight items of the list above.

| File | What it does |
| ---- | ------------ |
| `Dockerfile` | the overlay: pinned base, unprivileged user, no toolchain, no Xdebug, production nginx, php, php-fpm and supervisord configurations |
| `build.sh` | resolves the base digest, writes `digests.lock`, builds from the pin; optional `--push`, `--scan` and `--sign` |
| `digests.lock` | the pinned base digest: the file that makes a rebuild reproducible |
| `php/zz-prod.ini` | `expose_php = Off` |
| `php/zz-prod-fpm.conf` | `pm.max_children`, the pool user `app`, and the pid file and error log of a non-root process |
| `supervisord.conf` | supervisord without root: socket, pid file and logs under `/tmp` and on the container streams |

Usage:

```
./prod/build.sh --update                      # resolve laserstack/app:8.5, write the lock
APP_DOMAIN=app.example.com ./prod/build.sh    # build laserstack/app-prod:8.5
./prod/build.sh --check                       # exit 1 when the base tag moved
```

Behind a balancer that terminates TLS:

```
TRUST_FORWARDED_PROTO=1 TRUSTED_PROXY=10.0.0.0/8 \
APP_DOMAIN=app.example.com ./prod/build.sh
```

`--push` builds `linux/amd64` and `linux/arm64` and pushes. `--scan` runs trivy,
or grype, and fails on HIGH and CRITICAL. `--sign` runs cosign, and needs
`--push`. Both fail when the tool is not in `PATH`.

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `PHP_SERIES` | `8.5` | base series, must match the lock |
| `APP_DOMAIN` | required | the `server_name` of the app |
| `IMAGE` / `TAG` | `laserstack/app-prod` / `$PHP_SERIES` | the image to build |
| `TRUST_FORWARDED_PROTO` | `0` | `1` takes the scheme from `X-Forwarded-Proto` |
| `TRUSTED_PROXY` | `10.0.0.0/8` | the balancer range, used with `TRUST_FORWARDED_PROTO=1` |
| `PHP_MAX_CHILDREN` | `16` | php-fpm `pm.max_children`, at least 8 |
| `HEALTH_PATH` | `/` | the path of the health check, also settable at run time |

Run it:

```
docker run --init -p 8080:8080 \
  -v /srv/app:/var/www/app:ro \
  -v app-storage:/var/www/app/storage \
  laserstack/app-prod:8.5
```

- The container user is `app`, uid 10001. supervisord, nginx and php-fpm all run
  as that user, and the app listens on 8080.
- `--init`: supervisord is PID 1, and it reaps only its own children.
- The app is read-only at `/var/www/app` and must be readable by uid 10001. The
  directories the app writes to (cache, sessions, storage) need uid 10001
  ownership: a named volume that you chown once, as in the example above.
- The health check requests `http://127.0.0.1:8080$HEALTH_PATH`, through nginx
  and php-fpm. Set `HEALTH_PATH` at run time for a different path.

### Verified

Built both shapes from `laserstack/app:8.5@sha256:726f0d3d…` and ran them with a
read-only application mount.

| Check | Result |
| ----- | ------ |
| `docker exec … id` | `uid=10001(app)`, and supervisord, nginx and php-fpm all run as `app` |
| health status | `healthy`, exit code 0 |
| `nginx -t` in the image | successful, no alert: `-e /dev/stderr` covers the compiled-in default log |
| `GET /` | `200`, the application, with `Server: nginx` and no `X-Powered-By` |
| `GET /.env` | `403`, and `/.well-known/security.txt` `200` |
| static asset | `Cache-Control: max-age=2592000`, with the server headers inherited |
| 2 MiB upload | `200`, `{"bytes":2097364}` |
| `php -m` | no xdebug; `expose_php => Off` |
| php-fpm | workers in the `www` pool, `pm.max_children = 16`, `error_log = /dev/stderr`, `pid = /tmp/php-fpm.pid` |
| toolchain | no `git`, `sudo`, `vim`, `node`, `npm`, `yarn`, `composer`, `phpunit`; `psql`, `mysql`, `curl`, `bash` stay |
| supervisord log | one line per event on the container stream, no duplicated output |
| image metadata | `User=app`, `Expose 8080` (80 stays from the base image), base name and digest labels set |
| `/tmp` after start | only the runtime files: nginx temp directories and pid, php-fpm pid, supervisord pid and socket |
| balancer shape | `X-Forwarded-Proto: https` gives `{"https":"on"}`, and `{"https":""}` without it; `X-Forwarded-For: 203.0.113.9, 10.1.2.3` from a trusted peer gives `{"remote":"10.1.2.3"}` |
| wrong digest | `docker buildx build --build-arg BASE_IMAGE=laserstack/app:8.5@sha256:0000…` fails with `not found`; without `BASE_IMAGE` it fails with `base name should not be blank` |
| `--check` | reports the base tag as still pinned, exit 0 |

Two notes from the run:

- `php-fpm` logs `NOTICE: [pool www] 'user' directive is ignored when FPM is not
  running as root`. The workers run as `app` either way, and the directive
  matters when someone starts the image as root.
- BuildKit warns `InvalidDefaultArgInFrom` for `BASE_IMAGE`. It has no default on
  purpose, so a build without a pin fails instead of pulling a moving tag.

## nginx examples

`examples/nginx/` holds a production set for one app. Every file was loaded into
`laserstack/app:8.5` and exercised; the results are in "Verified" below. The
vhosts listen on 8080, and on 8443 for TLS: a non-root user cannot bind a port
below 1024.

| File | Purpose |
| ---- | ------- |
| `nginx.conf` | Main config. Logs to the container streams, `client_max_body_size 100M` to match php.ini, gzip, 4096 connections, TLS 1.2 and 1.3 only, and pid and temp files under `/tmp` for a non-root run. |
| `http.d/00-single-app.conf` | One fixed domain, then the shared body. Start here. |
| `http.d/10-behind-proxy.conf` | The load balancer terminates TLS. Client address from `X-Forwarded-For` within a trusted range, scheme from `X-Forwarded-Proto`. |
| `http.d/20-direct-tls.conf.disabled` | nginx terminates TLS on 8443, HSTS, ACME challenge, and a redirect from 8080. Mount the certificates, then rename the file to `20-direct-tls.conf`: the include pattern is `http.d/*.conf`. |
| `snippets/server-body.conf` | The body of an application server block: fixed root, dotfile deny, static cache, PHP handler. Every vhost includes it. |
| `snippets/security-headers.conf` | `nosniff`, `SAMEORIGIN`, referrer and permissions policy, on error responses too. |
| `snippets/static-assets.conf` | 30-day cache for the static extensions. Holds no `add_header` on purpose. |
| `snippets/php-fpm.conf` | The `~ \.php$` handler for `127.0.0.1:9000`, with `try_files $uri =404` and the `HTTPS` parameter from `$app_https`. |

Install into your own image:

```
COPY examples/nginx/nginx.conf  /etc/nginx/nginx.conf
COPY examples/nginx/http.d/     /etc/nginx/http.d/
COPY examples/nginx/snippets/   /etc/nginx/snippets/
```

Mount them for a test run. The `http.d` mount replaces the shipped
`nginx-site.conf`:

```
docker run -p 8080:8080 \
  -v "$PWD/examples/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$PWD/examples/nginx/http.d:/etc/nginx/http.d:ro" \
  -v "$PWD/examples/nginx/snippets:/etc/nginx/snippets:ro" \
  -v "$PWD/app:/var/www/app:ro" \
  laserstack/app:8.5
```

### Verified

| Check | Result |
| ----- | ------ |
| `nginx -t` with all three vhosts | syntax is ok |
| `Host: app.example.com` | `200`, the app answers |
| `GET /.env` | `403` |
| `GET /.well-known/security.txt` | `200` |
| `GET /assets/app.css` | `Cache-Control: max-age=2592000`, and the security headers of the server block are inherited |
| `X-Forwarded-Proto: https` behind the balancer | `{"https":"on"}` |
| no forwarded headers | `{"https":""}` |
| `X-Forwarded-For` from a trusted range | `{"remote":"10.0.0.7"}` for the header `203.0.113.9, 10.0.0.7` |
| the same header from outside the range | the real peer address, the header is ignored |
| 2 MiB upload | `200`, `{"bytes":2097364}` |
| `https://app-tls.example.com/` | HTTP/2 `200` with `strict-transport-security` |
| `http://app-tls.example.com/a/b?c=d` | `301 https://app-tls.example.com/a/b?c=d` |
| `/.well-known/acme-challenge/…` over plain HTTP | `200`: the dotfile rule does not block the challenge |
| access log | lines appear in `docker logs` |

### Notes

- Every vhost must define `$app_https` (`set $app_https $https;` or
  `set $app_https $forwarded_https;`). A vhost that forgets it fails `nginx -t`,
  which is the point.
- nginx has no line continuation. A value stays on one line.
- An `add_header` inside a `location` cancels every `add_header` the server block
  inherited. The static location therefore sets no header of its own.
- `set_real_ip_from` must list the balancer addresses only. A wide range lets a
  client forge its own address. With `real_ip_recursive on` nginx walks the
  header from the right and skips trusted addresses.
- `Strict-Transport-Security` belongs on the TLS side. A browser ignores it over
  plain HTTP, so `10-behind-proxy.conf` leaves it to the balancer.

## Evidence commands

```
docker run --rm --entrypoint /bin/bash laserstack/app:8.5 -lc 'id; php -m | grep -i xdebug'
docker image inspect laserstack/app:8.5 --format 'User=[{{.Config.User}}] Health=[{{.Config.Healthcheck}}]'
curl -si -H 'Host: app.example.com' http://<container>:80/     # 404
curl -si -H 'Host: myapp.test'      http://<container>:80/     # the app
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: myapp.test' http://<container>/.env   # 200, dev vhost
curl -s -o /dev/null -w '%{http_code}\n' -F file=@2mib.bin -H 'Host: myapp.test' http://<container>/upload.php  # 413, dev vhost
```

The same checks against `examples/nginx` answer `403` for `/.env` and `200` for
the 2 MiB upload.
