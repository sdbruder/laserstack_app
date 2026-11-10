FROM alpine:3.24
#PHP php85

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

# opcache and json are built into the php85 package, no separate packages
RUN \
  apk update \
  && apk upgrade \
  && apk add \
  php85-mbstring php85-iconv php85-intl php85-gd php85-session \
  php85-simplexml php85-xml php85-xmlreader php85-xmlwriter php85-pdo_mysql \
  php85 php85-fpm php85-phar php85-fileinfo php85-tokenizer php85-dom \
  php85-pcntl php85-xsl php85-sodium php85-pdo_pgsql \
  bash sudo vim less curl git supervisor yarn curl nginx npm nodejs \
  php85-pecl-redis php85-pecl-memcached php85-mysqli php85-mysqlnd php85-pecl-xdebug \
  php85-curl curl libcurl php85-ctype php85-zip \
  php85-pdo_sqlite mysql-client postgresql-client gnu-libiconv \
  && ln -s /usr/bin/php85 /usr/local/bin/php \
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
COPY php.ini          /etc/php85/conf.d/laser.ini
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
