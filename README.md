# Laser Stack

This is the app container image for [Laserstack](https://github.com/sdbruder/laserstack).

## Images

Each directory builds one image. An image carries the newest PHP patch of its
series and runs on the newest Alpine release that still packages that series;
a series that no released branch carries yet runs on `edge`, and takes its
package from the repository that has it.

| Directory | Alpine | PHP    | Series status                     |
| --------- | ------ | ------ | --------------------------------- |
| `7.4`     | 3.15   | 7.4.33 | end of life, final release        |
| `8.0`     | 3.16   | 8.0.30 | end of life, final release        |
| `8.1`     | 3.19   | 8.1.34 | end of life, final release        |
| `8.2`     | 3.22   | 8.2.35 | security fixes only               |
| `8.3`     | 3.24   | 8.3.36 | bug and security fixes            |
| `8.4`     | 3.24   | 8.4.27 | bug and security fixes            |
| `8.5`     | 3.24   | 8.5.12 | current stable                    |
| `8.6`     | edge   | 8.6.0RC5 | release candidate, not `latest` |

The `8.6` directory builds: Alpine carries `php86` in the `edge/testing`
repository, and the Dockerfile installs the series from there. PHP 8.6 has no
stable release yet (GA is planned for 19 November 2026), so the image is a
release candidate, and `latest` stays on `8.5` because
`.github/workflows/nightly-publish.yml` sets `APP_LATEST=8.5`. When Alpine moves
`php86` to `edge/community`, delete the `ARG PHP_REPO` line from
`8.6/Dockerfile`; nothing else changes.

A directory whose series lives outside `main` and `community` names its
repository in an `ARG PHP_REPO` line. `buildx.sh` reads that value, so the
version resolution installs the series the same way the Dockerfile does.

`.buildx-skip` holds one version directory per line. Blank lines and lines that
are not `major.minor` are ignored. It is empty at the moment.

Each image runs nginx (vhosts from `nginx-site.conf` on port 80) and php-fpm
under supervisord. Xdebug is loaded with `xdebug.mode=profile`, and `phpunit`
is the version `composer global require` resolved for that PHP series. Every
image from `7.4` to `8.5` carries the `memcached` extension, so a client can use
the memcached profile of the stack as a cache store. `8.6` does not: Alpine has
no package for it and pecl's `memcached` 3.4.0 does not compile against 8.6. The
mysql client and the postgres client (`psql`, `pg_dump`) are installed, for
`laser mysql` and `laser psql` of
[laserstack](https://github.com/sdbruder/laserstack).

`buildx-orbstack.sh` tags each image `laserstack/app:<php-version>` and
`laserstack/app:<major.minor>`, and gives the `APP_LATEST` directory the
`latest` tag.

## Publishing

`buildx.sh` builds every directory for `linux/amd64` and `linux/arm64`, pushes
`laserstack/app:<major.minor>` and `laserstack/app:<php-version>`, and gives
`latest` to the newest directory (or to `APP_LATEST`, when set; the workflow
sets it to `8.5`, so a release candidate cannot take `latest`). It reads
`HUB_USER` and `HUB_PASSWORD` from the environment or from `.env`.

`BUILDX_CACHE=gha` turns on the GitHub Actions build cache. A failed cache
does not block the build; the script retries without it.

`.github/workflows/nightly-publish.yml` runs the same script every night at
01:00 UTC, and on demand from the Actions tab. It needs two repository
secrets:

| Secret         | Value                                            |
| -------------- | ------------------------------------------------ |
| `HUB_USER`     | Docker Hub user name                             |
| `HUB_PASSWORD` | Docker Hub access token with read and write access |


## License

 Laser Stack (and this container image) is open-sourced software licensed under [BSD license](LICENSE.md).
