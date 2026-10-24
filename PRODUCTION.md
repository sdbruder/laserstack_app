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
| 3  | Xdebug runs in profile mode | `/etc/php85/conf.d/laser.ini`: `xdebug.mode=profile`, `xdebug.start_with_request=trigger`; `php -m` lists xdebug | Any client that sends the trigger (`?XDEBUG_TRIGGER`, session cookie) makes the app write cachegrind files and slow down. Set `xdebug.mode=off`. |
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

1. Pin the digest: `FROM laserstack/app:8.5.12@sha256:<digest>`.
2. Replace the vhost with a fixed root and a fixed `server_name`: take the set in
   `examples/nginx`, see the section below.
3. Write `xdebug.mode=off` and `expose_php=Off` into a `conf.d` file.
4. Run as a non-root user, or keep the root container but keep the app code on a
   read-only mount owned by `nobody`.
5. Raise `pm.max_children` to the size of the host. The nginx logs already go to
   the container streams with `examples/nginx/nginx.conf`.
6. Add a health check that requests a known path, and pass `--init`.
7. Remove the development toolchain when you can, to shrink the CVE feed.
8. Scan and sign the result in CI, and keep the pinned base digest under review.

## nginx examples

`examples/nginx/` holds a production set for one app. Every file was loaded into
`laserstack/app:8.5` and exercised; the results are in "Verified" below.

| File | Purpose |
| ---- | ------- |
| `nginx.conf` | Main config. Logs to the container streams, `client_max_body_size 100M` to match php.ini, gzip, 4096 connections, TLS 1.2 and 1.3 only. |
| `http.d/00-single-app.conf` | One fixed domain, one fixed document root, dotfile deny, static caching, PHP handler. Start here. |
| `http.d/10-behind-proxy.conf` | The load balancer terminates TLS. Client address from `X-Forwarded-For` within a trusted range, scheme from `X-Forwarded-Proto`. |
| `http.d/20-direct-tls.conf.disabled` | nginx terminates TLS on 443, HSTS, ACME challenge, port 80 redirect. Mount the certificates, then rename the file to `20-direct-tls.conf`: the include pattern is `http.d/*.conf`. |
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
docker run -p 8080:80 \
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
