FROM nginx:1.31.8-alpine3.24

LABEL org.opencontainers.image.title="Docker Laravel by Prowect"
LABEL org.opencontainers.image.description="Docker image for Laravel applications"
LABEL org.opencontainers.image.authors="office@prowect.com"
LABEL org.opencontainers.image.source="https://github.com/Prowect/Docker-Laravel"

ENV ALPINE_VERSION=v3.24
ENV PHP_VERSION=php85
ENV PHP_FPM_VERSION=php-fpm85
ENV PHP_INI_DIR=/etc/php85

RUN set -eux; \
    apk upgrade --no-cache; \
    apk add --no-cache 'brotli-libs>=1.2.1-r0' 'curl>=8.23.0-r0' \
        'libcurl>=8.23.0-r0' exiftool imagemagick nghttp2 runit vim \
        'nodejs>=24.22.1-r0' npm; \
    apk add --no-cache \
        ${PHP_VERSION}-ctype \
        ${PHP_VERSION}-curl \
        ${PHP_VERSION}-dom \
        ${PHP_VERSION}-exif \
        ${PHP_VERSION}-fileinfo \
        ${PHP_VERSION}-fpm \
        ${PHP_VERSION}-gd \
        ${PHP_VERSION}-iconv \
        ${PHP_VERSION}-intl \
        ${PHP_VERSION}-mbstring \
        ${PHP_VERSION}-openssl \
        ${PHP_VERSION}-pcntl \
        ${PHP_VERSION}-pdo \
        ${PHP_VERSION}-pdo_mysql \
        ${PHP_VERSION}-pdo_pgsql \
        ${PHP_VERSION}-pdo_sqlite \
        ${PHP_VERSION}-pecl-igbinary \
        ${PHP_VERSION}-pecl-imagick \
        ${PHP_VERSION}-pecl-msgpack \
        ${PHP_VERSION}-pecl-redis \
        ${PHP_VERSION}-pecl-xdebug \
        ${PHP_VERSION}-phar \
        ${PHP_VERSION}-posix \
        ${PHP_VERSION}-session \
        ${PHP_VERSION}-simplexml \
        ${PHP_VERSION}-sockets \
        ${PHP_VERSION}-sodium \
        ${PHP_VERSION}-tokenizer \
        ${PHP_VERSION}-xml \
        ${PHP_VERSION}-xmlreader \
        ${PHP_VERSION}-xmlwriter \
        ${PHP_VERSION}-zip \
        ${PHP_VERSION}; \
    ln -sf /usr/bin/${PHP_VERSION} /usr/bin/php; \
    ln -sf /usr/sbin/${PHP_FPM_VERSION} /usr/sbin/php-fpm; \
    ln -sf /var/log/${PHP_VERSION}/error.log /dev/stderr; \
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
    -e "s|user = nobody|user = nginx|" \
    -e "s|;php_admin_value\[error_log\]\\s=.*|php_admin_value[error_log] = /var/log/${PHP_VERSION}/error.log|" \
    -e "s|;php_admin_flag\[log_errors\]\\s=.*|php_admin_flag[log_errors] = on|" \
    -e "s/;clear_env = no/clear_env = no/g" \
    "${PHP_INI_DIR}/php-fpm.d/www.conf" \
    && sed -i \
    -e "s|;daemonize\\s*=.*|daemonize = no|" \
    -e "s|listen\\s*=.*|listen = 9000|" \
    -e "s|;error_log = log/${PHP_VERSION}/error.log|error_log = log/nginx/error.log|" \
    "${PHP_INI_DIR}/php-fpm.conf" \
    && sed -i \
    -e "s|upload_max_filesize\\s*=.*|upload_max_filesize = 128M|" \
    -e "s|max_file_uploads\\s*=.*|max_file_uploads = 50|" \
    -e "s|post_max_size\\s*=.*|post_max_size = 128M|" \
    -e "s|expose_php\\s*=.*|expose_php = Off|" \
    -e "s|;cgi.fix_pathinfo\\s*=.*|cgi.fix_pathinfo = 0|" \
    "${PHP_INI_DIR}/php.ini" \
    && php-fpm -t -y "${PHP_INI_DIR}/php-fpm.conf" -c "${PHP_INI_DIR}"

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
