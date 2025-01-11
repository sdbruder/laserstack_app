FROM alpine:3.19
#PHP php83

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

RUN \
  echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
  && cat /etc/apk/repositories \
  && apk update \
  && apk upgrade \
  && apk add \
  php83-mbstring php83-opcache php83-iconv php83-intl php83-gd php83-session \
  php83-simplexml php83-xml php83-xmlreader php83-xmlwriter php83-pdo_mysql \
  php83 php83-fpm php83-phar php83-fileinfo php83-tokenizer php83-dom \
  php83-pcntl php83-xsl php83-sodium php83-pdo_pgsql \
  bash sudo vim less curl git supervisor yarn curl nginx npm nodejs \
  php83-pecl-redis php83-mysqli php83-mysqlnd php83-pecl-xdebug \
  php83-curl curl libcurl php83-ctype php83-zip php83-json \
  php83-pdo_sqlite mysql-client gnu-libiconv \
  && ln -s /usr/bin/php83 /usr/local/bin/php \
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
COPY php.ini          /etc/php83/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
