FROM alpine:3.15
#PHP php7

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

RUN \
  apk update \
  && apk --no-cache upgrade \
  && apk --no-cache add \
  bash sudo vim less curl git supervisor yarn \
  nginx npm nodejs mysql-client gnu-libiconv \
  php7 php7-fpm php7-phar php7-fileinfo php7-tokenizer php7-dom \
  php7-simplexml php7-xml php7-xmlreader php7-xmlwriter php7-pdo_mysql \
  php7-mbstring php7-opcache php7-iconv php7-intl php7-gd php7-session \
  php7-pecl-redis php7-mysqli php7-mysqlnd php7-pecl-xdebug \
  php7-curl curl libcurl php7-ctype php7-zip php7-pdo_sqlite \
  && ln -s /usr/bin/php7 /usr/local/bin/php \
  && rm -f /etc/nginx/conf.d/*

RUN \
  curl -sS --location --output /usr/local/bin/phpunit "https://phar.phpunit.de/phpunit.phar" \
  && chmod +x /usr/local/bin/phpunit \
  && curl -sS --location --output /tmp/composer-setup.php "https://getcomposer.org/installer" \
  && php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet \
  && rm /tmp/composer-setup.php \
  && /usr/local/bin/composer global require phpunit/phpunit

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
COPY nginx-site.conf  /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
