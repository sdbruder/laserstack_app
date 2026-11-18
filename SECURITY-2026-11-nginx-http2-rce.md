# nginx: ten advisories of 2026-11-18, and these images

2026-11-18

## The vulnerabilities

Ten advisories, published today, all against nginx itself. Three are rated major
by nginx, which a scanner reports as critical.

| CVE | What | Severity | Fixed in |
| --- | ---- | -------- | -------- |
| CVE-2026-123007 | memory corruption in HTTP/2 flow control, remote code execution | major | 1.31.9+, 1.30.7+ |
| CVE-2026-118899 | infinite loop while reading a client request body over TLS 1.3 | major | 1.31.9+, 1.30.7+ |
| CVE-2026-113425 | use-after-free in the mail proxy module | major | 1.31.9+, 1.30.7+ |
| CVE-2026-123634 | use-after-free during response processing in resolver | medium | 1.31.9+, 1.30.7+ |
| CVE-2026-123633 | use-after-free in HTTP/2 | medium | 1.31.9+, 1.30.7+ |
| CVE-2026-121810 | use-after-free in HTTP/3 | medium | 1.31.9+, 1.30.7+ |
| CVE-2026-120967 | SNI bypass when validating client certificates in stream | medium | 1.31.9+, 1.30.7+ |
| CVE-2026-125283 | buffer overflow when using alias with try_files | minor | 1.31.9+, 1.30.7+ |
| CVE-2026-123640 | insufficient validation in the stream ssl_preread module | minor | 1.31.9+, 1.30.7+ |
| CVE-2026-120993 | NULL pointer dereference when using PROXY protocol v2 | minor | 1.31.9+ only |

nginx.org lists one of them with a doubled prefix, `CVE-CVE-2026-121810`, which is
why a scanner can report nine identifiers instead of ten.

Every affected range ends at 1.31.8, so **no nginx that these images can install
today is fixed.** nginx-1.30.7 (stable) and nginx-1.31.9 (mainline), both released
today, are the first versions that carry the fixes. The 1.28 line is legacy as of
now, next to 1.26 and 1.24, so it receives no upstream fix at all: for the `8.2`
image the fix can only come from an Alpine backport.

## What these images carry

| Image | Alpine | nginx | Package built | Fixed for these |
| ----- | ------ | ----- | ------------- | --------------- |
| `7.4` | 3.15 | 1.20.2-r2 | 2023-10-19 | no, and 3.15 is end of life |
| `8.0` | 3.16 | 1.22.1-r1 | 2023-10-15 | no, and 3.16 is end of life |
| `8.1` | 3.19 | 1.24.0-r16 | 2024-04-26 | no, a backport is expected |
| `8.2` | 3.22 | 1.28.3-r7 | 2026-07-23 | no, a backport is expected |
| `8.3`, `8.4`, `8.5` | 3.24 | 1.30.6-r0 | 2026-10-22 | no, 1.30.7 or a backport is expected |
| `8.6` | edge | 1.30.6-r1 | 2026-11-08 | no, 1.31.9 is expected |

Each image already carries the newest nginx its Alpine branch offers. The build
log of the 15 November nightly installs exactly the revision each branch index
carries today:

```
for b in v3.15 v3.16 v3.19 v3.22 v3.24 edge; do
  printf '%-6s ' "$b"
  curl -s "https://dl-cdn.alpinelinux.org/alpine/$b/main/aarch64/APKINDEX.tar.gz" \
    | tar xzO APKINDEX | grep -A2 '^P:nginx$' | grep '^V:'
done
```

There is nothing newer to update to yet. `1.30.6-r1` on edge is not a security
revision either: an Alpine APKBUILD records `secfixes` per revision, and there
`1.30.6-r0` is the newest entry — six CVEs of October — while `-r1` has none.

Note also what the name `nginx` resolves to. `apk info nginx` lists openresty too,
because openresty provides the same name. The installed package is Alpine's own:

```
$ docker run --rm --entrypoint nginx laserstack/app:8.5 -v
nginx version: nginx/1.30.6
$ docker run --rm --entrypoint sh laserstack/app:8.5 -c 'apk info -W /usr/sbin/nginx'
/usr/sbin/nginx is owned by nginx-1.30.6-r0
```

## These images are not exposed as shipped

The vhost listens on port 80 and nothing that these advisories touch is
configured:

- the only listener is `listen 80 default_server;` in `nginx-site.conf`, with no
  certificate and no `ssl` listener
- no `http2` or `http3` parameter on any listener
- no `stream { }` block, no `mail { }` block, no `proxy_protocol`, and the single
  `resolver` line in nginx.conf is commented out
- the vhost uses `try_files` without `alias`, which is what the one overflow needs
- Alpine's default `ssl_session_tickets off` is left as it comes

The binary has all of it compiled in — `--with-http_ssl_module`,
`--with-http_v2_module`, `--with-http_v3_module`, `--with-mail=dynamic`,
`--with-stream=dynamic` — so what is reachable depends on configuration, not on
the package:

| Advisory | Needs | As shipped |
| -------- | ----- | ---------- |
| CVE-2026-123007 | HTTP/2 | not reachable |
| CVE-2026-118899 | TLS | not reachable |
| CVE-2026-123633 | HTTP/2 | not reachable |
| CVE-2026-121810 | HTTP/3 | not reachable |
| CVE-2026-113425 | the mail module | not reachable |
| CVE-2026-123634 | a `resolver` directive | not reachable |
| CVE-2026-120967, CVE-2026-123640 | a `stream { }` block | not reachable |
| CVE-2026-120993 | `proxy_protocol` on a listener | not reachable |
| CVE-2026-125283 | `alias` with `try_files` | not reachable |

So an image used as it comes serves plain HTTP/1.1 on port 80 and cannot be hit
through any of the ten. The two that appear the moment you extend it are the
HTTP/2 memory corruption (`CVE-2026-123007`, the critical one) and the TLS 1.3
loop (`CVE-2026-118899`): add a TLS listener with HTTP/2, the usual production
shape, and both become reachable from the network.

## If you terminate TLS in this container

- keep HTTP/2 off, or patch nginx to 1.30.7+, until the image carries the fix
- or front the container with a proxy that terminates TLS and let it serve plain
  HTTP. That is already the topology this repository recommends: TLS and HTTP/2
  belong to the balancer in front, and the example vhost expects `$forwarded_https`
  from it instead of terminating anything itself (see PRODUCTION.md)
- after any update of nginx, restart the daemon: a running nginx keeps the old
  code in memory, the same rule the OpenSSH note gives

## When Alpine publishes it

Watch the branch that matters:

```
curl -sL https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64/APKINDEX.tar.gz \
  | tar xzO APKINDEX | grep -A2 '^P:nginx$'
```

Expect the same upstream version with a new `-rN` for 3.19, 3.22 and 3.24 — Alpine
backports rather than bumping the version, which is what `1.24.0-r16`,
`1.28.3-r7` and `1.30.6-r0` are, each carrying a batch of older CVEs — and
`1.31.9` for edge, which follows upstream. The 3.15 of `7.4` and the 3.16 of `8.0`
receive no updates at all: both branches are end of life, and no newer Alpine
branch carries PHP 7.4 or PHP 8.0 either, so those two images cannot be fixed by
an Alpine update — only by an nginx from outside Alpine, or by retiring them.

**A nightly rebuild alone does not pick it up.** The package layer is served from
the GitHub Actions build cache, which the nightly sets with `BUILDX_CACHE: gha`. In
the 15 November log the amd64 layer of the biggest image reports `#10 CACHED`,
while its arm64 layers ran, so the amd64 image published that night carried
whatever the cache held rather than what `apk upgrade` would have installed — and
the two architectures can therefore differ in package content. Until that is
addressed, a rebuild after the fix has to bypass the cache for that layer, and the
package version has to be checked on both architectures:

```
docker run --rm --entrypoint apk laserstack/app:8.5 list --installed | grep '^nginx-'
docker run --rm --platform linux/amd64 --entrypoint apk laserstack/app:8.5 list --installed | grep '^nginx-'
```

## Sources

- <https://nginx.org/en/security_advisories.html> — the advisories, with the affected and fixed versions
- <https://nginx.org/en/download.html> — 1.30.7 stable and 1.31.9 mainline, released 2026-11-18
- <https://my.f5.com/manage/s/article/K000163926> — the F5 advisory of the HTTP/2 memory corruption; K000163930 and K000163931 for the other two majors
- Alpine's `main/nginx/APKBUILD` — the `secfixes` list behind the table above
- <https://api.osv.dev/v1/query> — Alpine's vulndb, queried per branch and version
