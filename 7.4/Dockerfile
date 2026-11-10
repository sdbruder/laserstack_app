FROM alpine:3.15
#PHP php7

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

RUN \
  apk update \
  && apk --no-cache upgrade \
  && apk --no-cache add \
  bash sudo vim less curl git supervisor yarn \
  nginx npm nodejs mysql-client postgresql-client gnu-libiconv \
  php7 php7-fpm php7-phar php7-fileinfo php7-tokenizer php7-dom \
  php7-simplexml php7-xml php7-xmlreader php7-xmlwriter php7-pdo_mysql \
  php7-mbstring php7-opcache php7-iconv php7-intl php7-gd php7-session \
  php7-pecl-redis php7-pecl-memcached php7-mysqli php7-mysqlnd php7-pecl-xdebug \
  php7-curl curl libcurl php7-ctype php7-zip php7-pdo_sqlite php7-pdo_pgsql \
  && ln -s /usr/bin/php7 /usr/local/bin/php \
  && rm -f /etc/nginx/http.d/*

# composer, pinned: a rebuild of this directory gives the same composer, and
# renovate.json5 keeps the pin current. One version serves every series:
# composer 2.x needs PHP 7.2.5 or newer.
# renovate: datasource=packagist depName=composer/composer
ARG COMPOSER_VERSION=2.11.2

RUN \
  curl -sS --location --output /tmp/composer-setup.php "https://getcomposer.org/installer" \
  && php /tmp/composer-setup.php --version="${COMPOSER_VERSION}" --install-dir=/usr/local/bin --filename=composer --quiet \
  && rm /tmp/composer-setup.php \
  && /usr/local/bin/composer global require phpunit/phpunit \
  && ln -s /root/.composer/vendor/bin/phpunit /usr/local/bin/phpunit

RUN \
  echo "source /etc/profile" > ~/.bashrc \
  && chmod a+x ~/.bashrc \
  && mv /etc/profile.d/color_prompt.sh.disabled /etc/profile.d/color_prompt.sh \
  && echo laser > /etc/hostname \
  && addgroup laser \
  && adduser -D -s /bin/bash -h /var/www -G laser laser \
  && passwd -d laser laser

COPY bashrc           /root/.bashrc
COPY php.ini          /etc/php7/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/http.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

# The image describes itself. A reader asks the image which tools it carries and
# never the README: versions.txt lists the tool versions, packages.txt the apk
# inventory. The nightly publish repeats versions.txt in its log and its run
# summary.
RUN mkdir -p /etc/laserstack \
  && { \
       printf 'php %s\n'          "$(php -r 'echo PHP_VERSION;' 2>/dev/null)"; \
       command -v composer      >/dev/null && printf 'composer %s\n'   "$(composer --version 2>/dev/null | sed -n 's/^Composer version \([^ ]*\).*/\1/p')"; \
       command -v phpunit       >/dev/null && printf 'phpunit %s\n'    "$(phpunit --version 2>/dev/null | awk '{print $2}')"; \
       command -v node          >/dev/null && printf 'node %s\n'       "$(node --version 2>/dev/null)"; \
       command -v npm           >/dev/null && printf 'npm %s\n'        "$(npm --version 2>/dev/null)"; \
       command -v yarn          >/dev/null && printf 'yarn %s\n'       "$(yarn --version 2>/dev/null)"; \
       command -v nginx         >/dev/null && printf 'nginx %s\n'      "$(nginx -v 2>&1 | sed -n 's|.*nginx/||p')"; \
       command -v git           >/dev/null && printf 'git %s\n'        "$(git --version 2>/dev/null | awk '{print $3}')"; \
       command -v supervisord   >/dev/null && printf 'supervisor %s\n' "$(supervisord --version 2>/dev/null)"; \
       true; \
     } > /etc/laserstack/versions.txt \
  && apk info -v | sort > /etc/laserstack/packages.txt

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
