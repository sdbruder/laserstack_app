FROM alpine:3.19
#PHP php82

LABEL maintainer="Sergio Bruder"

WORKDIR /var/www/html

RUN \
	echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
	&& cat /etc/apk/repositories \
	&& apk update \
	&& apk upgrade \
	&& apk add \
		php82-mbstring php82-opcache php82-iconv php82-intl php82-gd php82-session \
		php82-simplexml php82-xml php82-xmlreader php82-xmlwriter php82-pdo_mysql \
		php82 php82-fpm php82-phar php82-fileinfo php82-tokenizer php82-dom \
		php82-pcntl php82-xsl php82-sodium php82-pdo_pgsql \
		bash sudo vim less curl git supervisor yarn curl nginx npm nodejs \
		php82-pecl-redis php82-mysqli php82-mysqlnd php82-pecl-xdebug \
		php82-curl curl libcurl php82-ctype php82-zip php82-json \
		php82-pdo_sqlite mysql-client gnu-libiconv \
	&& ln -s /usr/bin/php82 /usr/local/bin/php \
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
COPY php.ini          /etc/php82/conf.d/laser.ini
COPY nginx-site.conf  /etc/nginx/conf.d/
COPY supervisord.conf /etc/supervisord.conf

ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so

EXPOSE 80

CMD ["supervisord", "--nodaemon", "--configuration", "/etc/supervisord.conf"]
