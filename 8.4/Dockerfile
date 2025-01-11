FROM alpine:3.21
#PHP php84

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

RUN \
  echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
  && cat /etc/apk/repositories \
  && apk update \
  && apk upgrade \
  && apk add \
  php84-mbstring php84-opcache php84-iconv php84-intl php84-gd php84-session \
  php84-simplexml php84-xml php84-xmlreader php84-xmlwriter php84-pdo_mysql \
  php84 php84-fpm php84-phar php84-fileinfo php84-tokenizer php84-dom \
  php84-pcntl php84-xsl php84-sodium php84-pdo_pgsql \
  bash sudo vim less curl git supervisor yarn curl nginx npm nodejs \
  php84-pecl-redis php84-mysqli php84-mysqlnd php84-pecl-xdebug \
  php84-curl curl libcurl php84-ctype php84-zip php84-json \
  php84-pdo_sqlite mysql-client gnu-libiconv \
  && ln -s /usr/bin/php84 /usr/local/bin/php \
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
COPY php.ini          /etc/php84/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD=/usr/lib/preloadable_libiconv.so

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
