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
  php85-pecl-redis php85-mysqli php85-mysqlnd php85-pecl-xdebug \
  php85-curl curl libcurl php85-ctype php85-zip \
  php85-pdo_sqlite mysql-client gnu-libiconv \
  && ln -s /usr/bin/php85 /usr/local/bin/php \
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
COPY php.ini          /etc/php85/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/http.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
