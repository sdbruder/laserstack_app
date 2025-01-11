FROM alpine:3.19
#PHP php81

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

RUN \
  apk update \
  && apk upgrade \
  && apk add \
  php81-mbstring php81-opcache php81-iconv php81-intl php81-gd php81-session \
  php81-simplexml php81-xml php81-xmlreader php81-xmlwriter php81-pdo_mysql \
  php81 php81-fpm php81-phar php81-fileinfo php81-tokenizer php81-dom \
  php81-pecl-amqp php81-pcntl php81-xsl php81-sodium php81-pdo_pgsql \
  bash sudo vim less curl git supervisor yarn curl nginx npm nodejs \
  php81-pecl-redis php81-mysqli php81-mysqlnd php81-pecl-xdebug \
  php81-curl curl libcurl php81-ctype php81-zip php81-json \
  php81-pdo_sqlite mysql-client gnu-libiconv \
  && ln -s /usr/bin/php81 /usr/local/bin/php \
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
COPY php.ini          /etc/php81/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
