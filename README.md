# Laser Stack

This is the app container image for [Laserstack](https://github.com/sdbruder/laserstack).

## Images

Each directory builds one image. An image carries the newest PHP patch of its
series and runs on the newest Alpine release that still packages that series.

| Directory | Alpine | PHP    | Series status                     |
| --------- | ------ | ------ | --------------------------------- |
| `7.4`     | 3.15   | 7.4.33 | end of life, final release        |
| `8.0`     | 3.16   | 8.0.30 | end of life, final release        |
| `8.1`     | 3.19   | 8.1.34 | end of life, final release        |
| `8.2`     | 3.22   | 8.2.35 | security fixes only               |
| `8.3`     | 3.24   | 8.3.36 | bug and security fixes            |
| `8.4`     | 3.24   | 8.4.27 | bug and security fixes            |
| `8.5`     | 3.24   | 8.5.12 | current stable                    |

Each image runs nginx (vhosts from `nginx-site.conf` on port 80) and php-fpm
under supervisord. Xdebug is loaded with `xdebug.mode=profile`, and `phpunit`
is the version `composer global require` resolved for that PHP series.

`buildx-orbstack.sh` tags each image `laserstack/app:<php-version>` and
`laserstack/app:<major.minor>`, and gives the `APP_LATEST` directory the
`latest` tag.

## License

 Laser Stack (and this container image) is open-sourced software licensed under [BSD license](LICENSE.md).
