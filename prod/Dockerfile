# syntax=docker/dockerfile:1
#
# Production overlay for one app on top of laserstack/app.
#
# Build it from the repository root, so that examples/ and prod/ are in the
# context. prod/build.sh does this, and it pins the base digest for you:
#
#   ./prod/build.sh --update
#   APP_DOMAIN=app.example.com ./prod/build.sh
#
# BASE_IMAGE must carry a digest, from prod/digests.lock. It has no default, so
# an unset value fails the build instead of pulling a moving tag. BuildKit warns
# about that on every build: the warning is the point.

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG BASE_DIGEST
ARG PHP_SERIES=8.5
ARG APP_DOMAIN
ARG TRUST_FORWARDED_PROTO=0
ARG TRUSTED_PROXY=10.0.0.0/8
ARG PHP_MAX_CHILDREN=16
ARG HEALTH_PATH=/

LABEL \
  org.opencontainers.image.title="laserstack app, production overlay" \
  org.opencontainers.image.base.name="laserstack/app:${PHP_SERIES}" \
  org.opencontainers.image.base.digest="${BASE_DIGEST}"

ENV HEALTH_PATH=${HEALTH_PATH}

# The shared nginx config and the snippets. Port 80 of the base image stays in
# the metadata; the app listens on 8080.
COPY examples/nginx/nginx.conf /etc/nginx/nginx.conf
COPY examples/nginx/snippets/ /etc/nginx/snippets/

# A RUN step cannot read the build context, so the files that it has to adjust
# arrive here first, and are removed again at the end of the vhost step.
COPY prod/php/zz-prod.ini prod/php/zz-prod-fpm.conf /tmp/overlay/
COPY examples/nginx/http.d/00-single-app.conf examples/nginx/http.d/10-behind-proxy.conf /tmp/overlay/
COPY prod/supervisord.conf /etc/supervisord.conf

EXPOSE 8080
WORKDIR /var/www/app

# An unprivileged user owns nginx, php-fpm and the application. The lock on
# `laser`, the user of the base image, removes the empty password.
RUN \
  addgroup -g 10001 app \
  && adduser -D -H -u 10001 -G app -s /sbin/nologin app \
  && passwd -l laser

# Drop the development toolchain: version control, editor, sudo, the JavaScript
# toolchain and the PHP test tooling. bash, curl and the database clients stay:
# applications shell out to them.
RUN \
  apk del --no-cache git vim less sudo nodejs npm yarn \
  && rm -rf /root/.composer /usr/local/bin/composer /usr/local/bin/phpunit

# No Xdebug in production: remove the extension and the loader line that
# laser.ini of the base image points at. Then the production PHP settings and
# the php-fpm pool.
RUN \
  PHP_ABI="$(printf '%s' "${PHP_SERIES}" | tr -d .)" \
  && { test -d "/etc/php${PHP_ABI}" || { echo "prod: no /etc/php${PHP_ABI}, check PHP_SERIES=${PHP_SERIES}" >&2; exit 1; }; } \
  && { test "${PHP_MAX_CHILDREN}" -ge 8 || { echo "prod: PHP_MAX_CHILDREN must be at least 8" >&2; exit 1; }; } \
  && sed -i -e 's|^zend_extension=xdebug.so|;zend_extension=xdebug.so|' -e 's|^xdebug\.|;xdebug.|' "/etc/php${PHP_ABI}/conf.d/laser.ini" \
  && apk del --no-cache "php${PHP_ABI}-pecl-xdebug" \
  && sed -e "s|__MAX_CHILDREN__|${PHP_MAX_CHILDREN}|" /tmp/overlay/zz-prod-fpm.conf > "/etc/php${PHP_ABI}/php-fpm.d/zz-prod.conf" \
  && install -m 0644 /tmp/overlay/zz-prod.ini "/etc/php${PHP_ABI}/conf.d/zz-prod.ini" \
  && PHP_FPM="$(command -v "php-fpm${PHP_ABI}")" \
  && { test -n "${PHP_FPM}" || { echo "prod: no php-fpm${PHP_ABI} in PATH" >&2; exit 1; }; } \
  && ln -sf "${PHP_FPM}" /usr/local/bin/php-fpm

# The vhost: the single app example with this domain, or the shape for a
# balancer that terminates TLS, with the address range of that balancer.
RUN \
  { test -n "${APP_DOMAIN}" || { echo "prod: the build argument APP_DOMAIN is required" >&2; exit 1; }; } \
  && case "${TRUST_FORWARDED_PROTO}" in \
       0) VHOST=/tmp/overlay/00-single-app.conf ;; \
       1) VHOST=/tmp/overlay/10-behind-proxy.conf ;; \
       *) echo "prod: TRUST_FORWARDED_PROTO must be 0 or 1" >&2; exit 1 ;; \
     esac \
  && rm -f /etc/nginx/http.d/* \
  && sed -e "s|server_name  app.example.com;|server_name  ${APP_DOMAIN};|" \
         -e "s|server_name  app-lb.example.com;|server_name  ${APP_DOMAIN};|" \
         -e "s|set_real_ip_from   10.0.0.0/8;|set_real_ip_from   ${TRUSTED_PROXY};|" \
         "$VHOST" > /etc/nginx/http.d/00-app.conf \
  && rm -rf /tmp/overlay

# The application mount point, and its writable directory.
RUN \
  mkdir -p /var/www/app/public /var/www/app/storage \
  && chown -R app:app /var/www/app

USER app

# The health check reaches nginx and, through /, php-fpm as well.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS -o /dev/null "http://127.0.0.1:8080${HEALTH_PATH}"

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
