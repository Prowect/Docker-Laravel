#!/bin/sh
set -eu

IMAGE=${1:-docker-laravel:test}
TEST_DIRECTORY=$(mktemp -d)
APP_DIRECTORY="$TEST_DIRECTORY/app"
CUSTOM_ENTRYPOINT="$TEST_DIRECTORY/entrypoint.sh"
CUSTOM_NGINX_CONFIG="$TEST_DIRECTORY/default.conf"
CONTAINER_ID=""

cleanup() {
    if [ -n "$CONTAINER_ID" ]; then
        docker rm -f "$CONTAINER_ID" > /dev/null 2>&1 || true
    fi
    docker run --rm --entrypoint chown \
        -v "$TEST_DIRECTORY:/test" "$IMAGE" \
        -R "$(id -u):$(id -g)" /test > /dev/null 2>&1 || true
    rm -rf "$TEST_DIRECTORY"
}
trap cleanup EXIT

mkdir -p \
    "$APP_DIRECTORY/bootstrap" \
    "$APP_DIRECTORY/node_modules" \
    "$APP_DIRECTORY/public" \
    "$APP_DIRECTORY/vendor"

touch \
    "$APP_DIRECTORY/bootstrap/app.php" \
    "$APP_DIRECTORY/vendor/autoload.php"

cat > "$APP_DIRECTORY/artisan" <<'PHP'
<?php

if (($argv[1] ?? '') === 'cache:clear' && getenv('FAIL_CACHE_CLEAR') === 'true') {
    exit(42);
}

if (($argv[1] ?? '') === 'db:seed' && getenv('FAIL_SEED') === 'true') {
    exit(43);
}
PHP

cat > "$APP_DIRECTORY/public/index.php" <<'PHP'
<?php

echo (ini_get('expose_php') ? 'on' : 'off')
    .'|'.ini_get('cgi.fix_pathinfo')
    .'|'.ini_get('upload_max_filesize')
    .'|'.getenv('TEST_FPM_ENV');
PHP

cat > "$CUSTOM_ENTRYPOINT" <<'SH'
#!/bin/sh
printf 'custom-argument=%s\n' "$@"
SH
chmod +x "$CUSTOM_ENTRYPOINT"

cat > "$CUSTOM_NGINX_CONFIG" <<'NGINX'
server {
    listen 80;
    server_name localhost;

    root /data/www/public;
    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        try_files $uri /index.php =404;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
}
NGINX

OUTPUT=$(docker run --rm \
    -e APP_ENV=local \
    -v "$APP_DIRECTORY:/data/www" \
    -v "$CUSTOM_ENTRYPOINT:/entrypoint.sh" \
    "$IMAGE" first "second argument")

printf '%s\n' "$OUTPUT" | grep -Fqx 'custom-argument=first'
printf '%s\n' "$OUTPUT" | grep -Fqx 'custom-argument=second argument'

XDEBUG_OUTPUT=$(docker run --rm \
    -e APP_ENV=local \
    -e XDEBUG_ENABLED=true \
    -v "$APP_DIRECTORY:/data/www" \
    "$IMAGE" php -m)
printf '%s\n' "$XDEBUG_OUTPUT" | grep -Fqx 'xdebug'

if docker run --rm \
    -e APP_ENV=local \
    -e FAIL_CACHE_CLEAR=true \
    -v "$APP_DIRECTORY:/data/www" \
    "$IMAGE" true; then
    echo "Entrypoint continued after a failed command." >&2
    exit 1
else
    EXIT_CODE=$?
fi

if [ "$EXIT_CODE" -ne 42 ]; then
    echo "Expected exit code 42, got $EXIT_CODE." >&2
    exit 1
fi

if docker run --rm \
    -e APP_ENV=local \
    -e DB_CONNECTION=sqlite \
    -e ONSTART_SEEDER=true \
    -e FAIL_SEED=true \
    -v "$APP_DIRECTORY:/data/www" \
    "$IMAGE" true; then
    echo "Entrypoint continued after a failed seeder." >&2
    exit 1
else
    EXIT_CODE=$?
fi

if [ "$EXIT_CODE" -ne 43 ]; then
    echo "Expected seeder exit code 43, got $EXIT_CODE." >&2
    exit 1
fi

docker run --rm \
    -e APP_ENV=local \
    -e DB_CONNECTION=sqlite \
    -e ONSTART_SEEDER=false \
    -e FAIL_SEED=true \
    -v "$APP_DIRECTORY:/data/www" \
    "$IMAGE" true > /dev/null

docker run --rm --entrypoint php "$IMAGE" -r '
    if (PHP_VERSION_ID < 80512) {
        fwrite(STDERR, "PHP 8.5.12 or newer is required.\n");
        exit(1);
    }
    foreach (["ctype", "curl", "dom", "exif", "fileinfo", "gd", "iconv", "igbinary", "imagick", "intl", "mbstring", "msgpack", "openssl", "pcntl", "pdo_mysql", "pdo_pgsql", "pdo_sqlite", "Phar", "posix", "redis", "session", "SimpleXML", "sodium", "sockets", "tokenizer", "xml", "xmlreader", "xmlwriter", "zip"] as $extension) {
        if (!extension_loaded($extension)) {
            fwrite(STDERR, "Missing PHP extension: $extension\n");
            exit(1);
        }
    }
    if (!defined("Redis::SERIALIZER_IGBINARY") || !defined("Redis::SERIALIZER_MSGPACK")) {
        fwrite(STDERR, "Missing Redis serializers.\n");
        exit(1);
    }
'

FPM_INFO=$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
    'php-fpm -c "$PHP_INI_DIR" -i 2>/dev/null')
printf '%s\n' "$FPM_INFO" | grep -Fq 'Loaded Configuration File => /usr/local/etc/php/php.ini'
printf '%s\n' "$FPM_INFO" | grep -Fq 'cgi.fix_pathinfo => Off => Off'
printf '%s\n' "$FPM_INFO" | grep -Fq 'expose_php => Off => Off'
printf '%s\n' "$FPM_INFO" | grep -Fq 'upload_max_filesize => 128M => 128M'

RUNTIME_VERSIONS=$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c '
    nginx -v 2>&1
    php-fpm -v
    node --version
    npm --version
    composer --version --no-ansi
    cat /etc/alpine-release
    cat /etc/apk/repositories
')
printf '%s\n' "$RUNTIME_VERSIONS" | grep -Fqx 'nginx version: nginx/1.31.7'
printf '%s\n' "$RUNTIME_VERSIONS" | grep -Eq '^PHP 8\.5\.(1[2-9]|[2-9][0-9]) .*fpm-fcgi'
printf '%s\n' "$RUNTIME_VERSIONS" | grep -Eq '^v24\.'
printf '%s\n' "$RUNTIME_VERSIONS" | grep -Eq '^11\.'
printf '%s\n' "$RUNTIME_VERSIONS" | grep -Eq '^Composer version 2\.10\.3 '
printf '%s\n' "$RUNTIME_VERSIONS" | grep -Eq '^3\.24\.'
if printf '%s\n' "$RUNTIME_VERSIONS" | grep -E '/v3\.[0-9]+/' | grep -Fqv '/v3.24/'; then
    echo "Image contains a package repository from another Alpine release." >&2
    exit 1
fi

QUEUE_OUTPUT=$(docker run --rm --entrypoint /bin/sh "$IMAGE" -c \
    'unset QUEUE_CONNECTION HORIZON_ENABLED; /etc/service/queue-worker/run 2>&1 || true')
printf '%s\n' "$QUEUE_OUTPUT" | grep -Fq 'Queue Worker - skipped'
if printf '%s\n' "$QUEUE_OUTPUT" | grep -Fq 'Starting laravel queue worker'; then
    echo "Queue worker started without a configured connection." >&2
    exit 1
fi

CONTAINER_ID=$(docker run --detach --rm \
    -e APP_ENV=production \
    -e TEST_FPM_ENV=available \
    -v "$APP_DIRECTORY:/data/www" \
    -v "$CUSTOM_NGINX_CONFIG:/etc/nginx/conf.d/default.conf:ro" \
    "$IMAGE")

HEALTHY=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if docker exec "$CONTAINER_ID" curl --fail --silent http://127.0.0.1:8081/healthz > /dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    sleep 1
done

if [ "$HEALTHY" != true ]; then
    echo "Container health endpoint did not become available." >&2
    docker logs "$CONTAINER_ID" >&2
    exit 1
fi

RUNTIME_PHP_INFO=$(docker exec "$CONTAINER_ID" curl --fail --silent http://127.0.0.1/index.php)
if [ "$RUNTIME_PHP_INFO" != 'off|0|128M|available' ]; then
    echo "Unexpected PHP-FPM settings: $RUNTIME_PHP_INFO" >&2
    exit 1
fi

RUNTIME_HEADERS=$(docker exec "$CONTAINER_ID" curl --silent --dump-header - --output /dev/null http://127.0.0.1/index.php)
if printf '%s\n' "$RUNTIME_HEADERS" | grep -Eiq '^(X-Powered-By:|Server: nginx/)'; then
    echo "Runtime headers expose server version information." >&2
    exit 1
fi

echo "Entrypoint tests passed."
