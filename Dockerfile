FROM php:8.5.12-fpm-alpine3.24 AS php-build

# Compile all extensions against the same PHP source and ABI.
RUN set -eux; \
    apk add --no-cache $PHPIZE_DEPS linux-headers icu-dev libzip-dev libpng-dev \
        libjpeg-turbo-dev freetype-dev libwebp-dev postgresql-dev \
        imagemagick-dev; \
    cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j "$(nproc)" exif gd intl pcntl \
        pdo_mysql pdo_pgsql sockets zip; \
    pecl install igbinary-3.2.17RC1 msgpack-3.0.1; \
    docker-php-ext-enable igbinary msgpack; \
    printf 'yes\nno\nno\nyes\nno\nno\n' | pecl install redis-6.3.0; \
    pecl install imagick-3.8.1 xdebug-3.5.3; \
    docker-php-ext-enable redis imagick; \
    php -r 'foreach (["exif", "gd", "igbinary", "imagick", "intl", "msgpack", "pcntl", "pdo_mysql", "pdo_pgsql", "redis", "sockets", "zip"] as $extension) { if (!extension_loaded($extension)) { exit(1); } }'

FROM nginx:1.31.7-alpine3.24

LABEL org.opencontainers.image.title="Docker Laravel by Prowect"
LABEL org.opencontainers.image.description="Docker image for Laravel applications"
LABEL org.opencontainers.image.authors="office@prowect.com"
LABEL org.opencontainers.image.source="https://github.com/Prowect/Docker-Laravel"

ENV ALPINE_VERSION=v3.24
ENV PHP_INI_DIR=/usr/local/etc/php

COPY --from=php-build /usr/local /usr/local

RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache curl exiftool imagemagick nghttp2 runit vim \
        nodejs npm; \
    apk add --no-cache --virtual .scan-deps scanelf; \
    runDeps="$(scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
        | tr ',' '\n' | sort -u \
        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }')"; \
    apk add --no-cache $runDeps; \
    apk del --no-network .scan-deps; \
    ln -sf /usr/local/bin/php /usr/bin/php; \
    php -r 'if (PHP_VERSION_ID < 80512) { exit(1); }'; \
    php-fpm -v

# install a verified Composer release
ADD --checksum=sha256:7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6 \
    https://getcomposer.org/download/2.10.3/composer.phar /usr/local/bin/composer
RUN chmod +x /usr/local/bin/composer

# add custom config (feel free to override these files yourself)
COPY config/nginx/health.conf /etc/nginx/conf.d/00-health.conf
COPY config/nginx/security.conf /etc/nginx/conf.d/00-security.conf
COPY config/nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY config/vim/vimrc /etc/vim/vimrc
COPY config/php/xdebug/xdebug.ini ${PHP_INI_DIR}/templates/xdebug.ini

RUN sed -i \
    -e "s|^user = www-data$|user = nginx|" \
    -e "s|^group = www-data$|group = nginx|" \
    /usr/local/etc/php-fpm.d/www.conf \
    && sed -i \
    -e "s|upload_max_filesize\\s*=.*|upload_max_filesize = 128M|" \
    -e "s|max_file_uploads\\s*=.*|max_file_uploads = 50|" \
    -e "s|post_max_size\\s*=.*|post_max_size = 128M|" \
    -e "s|expose_php\\s*=.*|expose_php = Off|" \
    -e "s|;cgi.fix_pathinfo\\s*=.*|cgi.fix_pathinfo = 0|" \
    "${PHP_INI_DIR}/php.ini" \
    && php-fpm -t

# add runsvdir services
COPY service/crontab.service /etc/service/crontab/run
COPY service/nginx.service /etc/service/nginx/run
COPY service/php-fpm.service /etc/service/php-fpm/run
COPY service/queue-worker.service /etc/service/queue-worker/run
COPY service/vite.service /etc/service/vite/run
COPY service/inertia-ssr.service /etc/service/inertia-ssr/run
RUN chmod +x /etc/service/*/run

# add entrypoint (startup script)
COPY entrypoint.sh /main-entrypoint.sh
RUN chmod +x /main-entrypoint.sh

# inject laravel cronjobs
RUN echo "* * * * * /usr/bin/php /data/www/artisan schedule:run" >> /etc/crontabs/nginx

WORKDIR /data/www

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl --fail --silent --show-error http://127.0.0.1:8081/healthz > /dev/null || exit 1

ENTRYPOINT [ "/main-entrypoint.sh" ]
