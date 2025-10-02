FROM nginx:1.29.1-alpine

LABEL org.opencontainers.image.title="Docker Laravel by Prowect"
LABEL org.opencontainers.image.description="Docker image for Laravel applications"
LABEL org.opencontainers.image.authors="office@prowect.com"
LABEL org.opencontainers.image.source="https://github.com/Prowect/Docker-Laravel"

ENV ALPINE_VERSION=v3.22
ENV PHP_VERSION=php83
ENV PHP_FPM_VERSION=php-fpm83

# install 
RUN \
    echo "https://dl-cdn.alpinelinux.org/alpine/$ALPINE_VERSION/main" >> /etc/apk/repositories && \
    echo "@community https://dl-cdn.alpinelinux.org/alpine/$ALPINE_VERSION/community" >> /etc/apk/repositories && \
    apk --update add --no-cache \
        curl \
        exiftool \
        imagemagick \
        nghttp2 \
        runit@community \
        vim \
    && \
    # install PHP (incl. required extensions for laravel)
    apk --update add --no-cache \
        ${PHP_VERSION}-ctype@community \
        ${PHP_VERSION}-curl@community \
        ${PHP_VERSION}-dom@community \
        ${PHP_VERSION}-exif@community \
        ${PHP_VERSION}-fileinfo@community \
        ${PHP_VERSION}-fpm@community \
        ${PHP_VERSION}-gd@community \
        ${PHP_VERSION}-iconv@community \
        ${PHP_VERSION}-intl@community \
        ${PHP_VERSION}-json@community \
        ${PHP_VERSION}-mbstring@community \
        ${PHP_VERSION}-opcache@community \
        ${PHP_VERSION}-openssl@community \
        ${PHP_VERSION}-pcntl@community \
        ${PHP_VERSION}-pdo@community \
        ${PHP_VERSION}-pdo_mysql@community \
        ${PHP_VERSION}-pdo_pgsql@community \
        ${PHP_VERSION}-pdo_sqlite@community \
        ${PHP_VERSION}-pecl-imagick@community \
        ${PHP_VERSION}-phar@community \
        ${PHP_VERSION}-posix@community \
        ${PHP_VERSION}-redis@community \
        ${PHP_VERSION}-session@community \
        ${PHP_VERSION}-simplexml@community \
        ${PHP_VERSION}-sodium@community \
        ${PHP_VERSION}-tokenizer@community \
        ${PHP_VERSION}-xdebug@community \
        ${PHP_VERSION}-xml@community \
        ${PHP_VERSION}-xmlreader@community \
        ${PHP_VERSION}-xmlwriter@community \
        ${PHP_VERSION}-zip@community \
        ${PHP_VERSION}@community

# install composer
ADD https://getcomposer.org/composer.phar /usr/local/bin/composer
RUN chmod +x /usr/local/bin/composer && \
    composer self-update --no-interaction --2 && \
    # install other packages (required for Laravel)
    apk --update add --no-cache \
        nodejs-current@community \
        npm@community \
    && \
    # cleanup apk
    rm -rf /var/cache/apk/* \
    && \
    # forward logs to stdout and stderr
    ln -sf /var/log/${PHP_VERSION}/error.log /dev/stderr

# add custom config (feel free to override this files by yourself)
COPY config/nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY config/vim/vimrc /etc/vim/vimrc
COPY config/php/xdebug/xdebug.ini /etc/${PHP_VERSION}/templates/xdebug.ini

RUN sed -i \
    -e "s|user = nobody|user = nginx|" \
    -e "s|;php_admin_value\[error_log\]\s=.*|php_admin_value\[error_log\] = /var/log/${PHP_VERSION}/error.log|" \
    -e "s|;php_admin_flag\[log_errors\]\s=.*|php_admin_flag[log_errors] = on|" \
    -e "s/;clear_env = no/clear_env = no/g" \
    /etc/${PHP_VERSION}/php-fpm.d/www.conf \
    && \
    sed -i -e "s|;daemonize\s*=.*|daemonize = no|" \
    -e "s|listen\s*=.*|listen = 9000|" \
    -e "s|;error_log = log/${PHP_VERSION}/error.log|error_log = log/nginx/error.log|" \
    /etc/${PHP_VERSION}/php-fpm.conf \
    && \
    sed -i -e "s|upload_max_filesize\s*=.*|upload_max_filesize = 128M|" \
    -e "s|max_file_uploads\s*=.*|max_file_uploads = 50|" \
    -e "s|post_max_size\s*=.*|post_max_size = 128M|" \
    -e "s|;cgi.fix_pathinfo\s*=.*|cgi.fix_pathinfo = 1|" \
    /etc/${PHP_VERSION}/php.ini

# add runsvdir services
COPY service/crontab.service /etc/service/crontab/run
COPY service/nginx.service /etc/service/nginx/run
COPY service/php-fpm.service /etc/service/php-fpm/run
COPY service/queue-worker.service /etc/service/queue-worker/run
COPY service/vite.service /etc/service/vite/run
RUN chmod +x /etc/service/*/run

# add entrypoint (startup script)
COPY entrypoint.sh /main-entrypoint.sh
RUN chmod +x /main-entrypoint.sh

# inject laravel cronjobs
RUN echo "* * * * * /usr/bin/php /data/www/artisan schedule:run" >> /etc/crontabs/nginx

WORKDIR /data/www

EXPOSE 80

ENTRYPOINT [ "/main-entrypoint.sh" ]