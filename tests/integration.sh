#!/bin/sh
set -eu

IMAGE=${1:-}
APP_DIRECTORY=${2:-}
RUN_ID=${3:-1}

if [ -z "$IMAGE" ] || [ -z "$APP_DIRECTORY" ]; then
    echo "Usage: tests/integration.sh <base-image> <laravel-app> [run-id]" >&2
    exit 2
fi

APP_DIRECTORY=$(cd "$APP_DIRECTORY" && pwd)
if [ ! -f "$APP_DIRECTORY/artisan" ] || [ ! -f "$APP_DIRECTORY/composer.json" ]; then
    echo "Not a Laravel application: $APP_DIRECTORY" >&2
    exit 2
fi

if [ -f "$APP_DIRECTORY/package.json" ] \
    && [ ! -f "$APP_DIRECTORY/package-lock.json" ] \
    && [ ! -f "$APP_DIRECTORY/npm-shrinkwrap.json" ]; then
    echo "package.json exists, but npm ci requires package-lock.json or npm-shrinkwrap.json." >&2
    exit 2
fi

TEST_DIRECTORY=$(mktemp -d)
CONTEXT_DIRECTORY="$TEST_DIRECTORY/context"
APP_CONTEXT_DIRECTORY="$CONTEXT_DIRECTORY/app"
DERIVED_IMAGE="docker-laravel:integration-${RUN_ID}-$$"
CONTAINER_ID=""

cleanup() {
    if [ -n "$CONTAINER_ID" ]; then
        docker rm -f "$CONTAINER_ID" > /dev/null 2>&1 || true
    fi
    docker image rm --force "$DERIVED_IMAGE" > /dev/null 2>&1 || true
    rm -rf "$TEST_DIRECTORY"
}
trap cleanup EXIT

mkdir -p "$APP_CONTEXT_DIRECTORY"
tar \
    --exclude='./.git' \
    --exclude='./.env' \
    --exclude='./.env.*' \
    --exclude='./.npmrc' \
    --exclude='./auth.json' \
    --exclude='./node_modules' \
    --exclude='./public/build' \
    --exclude='./public/hot' \
    --exclude='./storage/logs/*' \
    --exclude='./vendor' \
    -C "$APP_DIRECTORY" \
    -cf "$TEST_DIRECTORY/app.tar" .
tar -C "$APP_CONTEXT_DIRECTORY" -xf "$TEST_DIRECTORY/app.tar"

if [ -f "$APP_DIRECTORY/.env.example" ]; then
    cp "$APP_DIRECTORY/.env.example" "$APP_CONTEXT_DIRECTORY/.env"
fi

cat > "$CONTEXT_DIRECTORY/Dockerfile" <<'EOF'
ARG BASE_IMAGE=docker-laravel:test
FROM ${BASE_IMAGE}

COPY app /data/www

RUN MODE=build \
    APP_ENV=production \
    /main-entrypoint.sh true
EOF

BUILD_LOG="$TEST_DIRECTORY/build.log"
echo "[$RUN_ID] Building derived Laravel image ..."
if ! docker build \
    --build-arg "BASE_IMAGE=$IMAGE" \
    --no-cache \
    --tag "$DERIVED_IMAGE" \
    "$CONTEXT_DIRECTORY" > "$BUILD_LOG" 2>&1; then
    echo "[$RUN_ID] Derived-image build failed:" >&2
    cat "$BUILD_LOG" >&2
    exit 1
fi

docker run --rm --entrypoint /bin/sh "$DERIVED_IMAGE" -c '
    test -f /data/www/vendor/autoload.php
    if [ -f /data/www/package.json ]; then
        test -f /data/www/public/build/manifest.json
        test ! -d /data/www/node_modules
    fi
    php /data/www/artisan --version
' > /dev/null

CONTAINER_ID=$(docker run --detach --rm \
    -e APP_ENV=production \
    -e CACHE_STORE=array \
    -e SESSION_DRIVER=array \
    -e QUEUE_CONNECTION=sync \
    -e DB_CONNECTION=sqlite \
    "$DERIVED_IMAGE")

HEALTHY=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if docker exec "$CONTAINER_ID" curl --fail --silent http://127.0.0.1:8081/healthz > /dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    sleep 1
done

if [ "$HEALTHY" != true ]; then
    echo "[$RUN_ID] Derived container did not become healthy." >&2
    docker logs "$CONTAINER_ID" >&2
    exit 1
fi

echo "[$RUN_ID] Derived-image integration test passed."
