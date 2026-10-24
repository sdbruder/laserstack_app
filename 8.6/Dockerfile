# php86 is packaged in edge only, no released Alpine branch carries it yet
FROM alpine:edge
#PHP php86

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

# opcache and json are built into the php86 package, no separate packages
RUN \
  apk update \
  && apk upgrade \
  && apk add \
  php86-mbstring php86-iconv php86-intl php86-gd php86-session \
  php86-simplexml php86-xml php86-xmlreader php86-xmlwriter php86-pdo_mysql \
  php86 php86-fpm php86-phar php86-fileinfo php86-tokenizer php86-dom \
  php86-pcntl php86-xsl php86-sodium php86-pdo_pgsql \
  bash sudo vim less curl git supervisor yarn curl nginx npm nodejs \
  php86-pecl-redis php86-mysqli php86-mysqlnd php86-pecl-xdebug \
  php86-curl curl libcurl php86-ctype php86-zip \
  php86-pdo_sqlite mysql-client postgresql-client gnu-libiconv \
  && ln -s /usr/bin/php86 /usr/local/bin/php \
  && rm -f /etc/nginx/http.d/*

RUN \
  curl -sS --location --output /tmp/composer-setup.php "https://getcomposer.org/installer" \
  && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet \
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
COPY php.ini          /etc/php86/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/http.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
