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

Not a problem: one app per container is exactly the shape of this image. The
image holds no application code, so you layer or mount the app at
`/var/www/<name>/public`.

## Minimum changes for one production app

1. Pin the digest: `FROM laserstack/app:8.5.12@sha256:<digest>`.
2. Replace the vhost with a fixed root and a fixed `server_name`.
3. Write `xdebug.mode=off` into a `conf.d` file.
4. Run as a non-root user, or keep the root container but keep the app code on a
   read-only mount owned by `nobody`.
5. Raise `pm.max_children` to the size of the host, and send the nginx logs to
   `/dev/stdout`.
6. Add a health check that requests a known path, and pass `--init`.
7. Remove the development toolchain when you can, to shrink the CVE feed.
8. Scan and sign the result in CI, and keep the pinned base digest under review.

## Evidence commands

```
docker run --rm --entrypoint /bin/bash laserstack/app:8.5 -lc 'id; php -m | grep -i xdebug'
docker image inspect laserstack/app:8.5 --format 'User=[{{.Config.User}}] Health=[{{.Config.Healthcheck}}]'
curl -si -H 'Host: app.example.com' http://<container>:80/     # 404
curl -si -H 'Host: myapp.test'      http://<container>:80/     # the app
```
