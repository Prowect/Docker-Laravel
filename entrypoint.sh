#!/bin/sh
set -eu

export BASH_COLOR_PRIMARY='\033[1;36m'
export BASH_COLOR_DARK='\033[1;30m'
export BASH_COLOR_RESET='\033[0m'
export BASH_COLOR_ERROR='\033[0;31m'
export BASH_COLOR_SUCCESS='\033[0;32m'
export BASH_COLOR_WARNING='\033[0;33m'

echo -e "

$BASH_COLOR_PRIMARY          ##########         
$BASH_COLOR_PRIMARY       #################       
$BASH_COLOR_PRIMARY    #####           #####     $BASH_COLOR_DARK  _____                            _   
$BASH_COLOR_PRIMARY  #####   #########   #####   $BASH_COLOR_DARK |  __ \                          | |  
$BASH_COLOR_PRIMARY  ####  #############  ####   $BASH_COLOR_DARK | |__) | __ _____      _____  ___| |_ 
$BASH_COLOR_PRIMARY  ###   #############   ###   $BASH_COLOR_DARK |  ___/ '__/ _ \ \ /\ / / _ \/ __| __|
$BASH_COLOR_PRIMARY  ###   #############  ####   $BASH_COLOR_DARK | |   | | | (_) \ V  V /  __/ (__| |_ 
$BASH_COLOR_PRIMARY  ###     #########   #####   $BASH_COLOR_DARK |_|   |_|  \___/ \_/\_/ \___|\___|\__|
$BASH_COLOR_PRIMARY   ##   ##         #####
$BASH_COLOR_PRIMARY        #############
$BASH_COLOR_PRIMARY          ##########

$BASH_COLOR_RESET"

export MODE=${MODE:-"run"}
export APP_ENV=${APP_ENV:-"production"}
export PASSPORT_ENABLED=${PASSPORT_ENABLED:-"false"}
export XDEBUG_ENABLED=${XDEBUG_ENABLED:-"false"}
export INERTIA_SSR_ENABLED=${INERTIA_SSR_ENABLED:-"false"}
export ONSTART_MIGRATE=${ONSTART_MIGRATE:-"false"}
export ONSTART_SEEDER=${ONSTART_SEEDER:-"false"}
export ONSTART_SEEDER_WAIT=${ONSTART_SEEDER_WAIT:-"true"}
DB_CONNECTION=${DB_CONNECTION:-""}
export IS_BUILD_MODE=$([ "$MODE" = "build" ] && echo true || echo false)
export IS_DEV_MODE=$([ "$MODE" = "dev" ] || [ "$APP_ENV" = "local" ] && echo true || echo false)
export IS_RUN_MODE=$([ "$MODE" = "run" ] || [ "$APP_ENV" = "production" ] && echo true || echo false)

if [ "$IS_BUILD_MODE" = true ]; then
    export CACHE_STORE=${CACHE_STORE:-"array"}
    export SESSION_DRIVER=${SESSION_DRIVER:-"array"}
    export QUEUE_CONNECTION=${QUEUE_CONNECTION:-"sync"}
    export DB_CONNECTION=${DB_CONNECTION:-"sqlite"}
fi

echo -e "${BASH_COLOR_DARK}Current mode: ${BASH_COLOR_PRIMARY}$MODE${BASH_COLOR_RESET}"

if [ "$IS_BUILD_MODE" = true ]; then
    echo -e "${BASH_COLOR_DARK}Running container build ...${BASH_COLOR_RESET}"
else
    echo -e "${BASH_COLOR_DARK}Starting Docker Laravel ...${BASH_COLOR_RESET}"
fi

# Setup laravel/install composer packages if not present
LARAVEL_BOOTSTRAP_APP_FILE="/data/www/bootstrap/app.php"
COMPOSER_FILE="/data/www/composer.json"
COMPOSER_AUTOLOAD_FILE="/data/www/vendor/autoload.php"
if [ ! -f "$LARAVEL_BOOTSTRAP_APP_FILE" ]; then
    echo -e "${BASH_COLOR_WARNING}No laravel source files detected. Installing a new laravel instance ...${BASH_COLOR_RESET}"

    composer create-project laravel/laravel .

    echo -e "${BASH_COLOR_SUCCESS}Laravel has been installed: ${BASH_COLOR_PRIMARY}$(php artisan --version)${BASH_COLOR_RESET}"
fi

if [ -f "$COMPOSER_FILE" ] && { [ "$IS_BUILD_MODE" = true ] || [ ! -f "$COMPOSER_AUTOLOAD_FILE" ]; }; then
    echo -e "${BASH_COLOR_WARNING}Installing composer dependencies ...${BASH_COLOR_RESET}"

    if [ "$IS_BUILD_MODE" = true ]; then
        composer install --no-interaction --prefer-dist --no-progress --no-dev --optimize-autoloader
    else
        composer install --no-interaction --prefer-dist --no-progress
    fi
fi

if [ -f "$LARAVEL_BOOTSTRAP_APP_FILE" ] && [ ! -f "$COMPOSER_AUTOLOAD_FILE" ]; then
    echo -e "${BASH_COLOR_ERROR}Composer dependencies are missing.${BASH_COLOR_RESET}"
    exit 1
fi

# Setup node_modules for build mode or when missing in dev mode
PACKAGE_FILE="/data/www/package.json"
NODE_MODULES_DIRECTORY="/data/www/node_modules"
if [ -f "$PACKAGE_FILE" ] && { [ "$IS_BUILD_MODE" = true ] || { [ "$IS_DEV_MODE" = true ] && [ ! -d "$NODE_MODULES_DIRECTORY" ]; }; }; then
    npm ci
fi

# Create storage folders (they may not exist when mounted)
mkdir -p \
    /data/www/bootstrap/cache \
    /data/www/storage/app \
    /data/www/storage/mediafiles \
    /data/www/storage/framework/cache \
    /data/www/storage/framework/sessions \
    /data/www/storage/framework/views \
    /data/www/storage/logs

# create storage symlink (because we cannot access storage outside of public directory)
STORAGE_LINK_PATH="/data/www/public/storage"
if [ ! -L "$STORAGE_LINK_PATH" ]; then
    echo -e "${BASH_COLOR_WARNING}Creating laravel storage link ...${BASH_COLOR_RESET}"
    php /data/www/artisan storage:link
fi

# Clear and fill laravel caches
echo -e "${BASH_COLOR_WARNING}Clearing laravel caches ...${BASH_COLOR_RESET}"
php /data/www/artisan config:clear
php /data/www/artisan route:clear
php /data/www/artisan cache:clear
if [ "$APP_ENV" != "local" ]; then # create caches (prepare for production)
    echo -e "Preparing cache for environment ${BASH_COLOR_WARNING}$APP_ENV${BASH_COLOR_RESET}"
    php /data/www/artisan config:cache
    php /data/www/artisan route:cache
fi

# Generate passport keys if not present
if [ "$PASSPORT_ENABLED" = "true" ]; then
    if [ ! -e /data/www/storage/oauth-private.key ]; then
        php /data/www/artisan passport:keys
    fi
fi

# Enable/disable XDEBUG
XDEBUG_INI_PATH="/etc/${PHP_VERSION}/conf.d/xdebug.ini"
if [ "$XDEBUG_ENABLED" = "true" ]; then
    echo -e "${BASH_COLOR_WARNING}Enabling XDEBUG${BASH_COLOR_RESET}"
    ln -sf "/etc/${PHP_VERSION}/templates/xdebug.ini" "$XDEBUG_INI_PATH"
else 
    echo -e "${BASH_COLOR_WARNING}Disabling XDEBUG${BASH_COLOR_RESET}"
    if [ -L "$XDEBUG_INI_PATH" ]; then
        unlink "$XDEBUG_INI_PATH"
    fi
fi

# Do a vite build (in build mode)
if [ "$IS_BUILD_MODE" = true ] && [ -f "$PACKAGE_FILE" ]; then
    echo -e "${BASH_COLOR_WARNING}Running vite build ...${BASH_COLOR_RESET}"
    npm --prefix /data/www run build

    if [ "$INERTIA_SSR_ENABLED" = "true" ]; then
        echo -e "${BASH_COLOR_WARNING}Running vite build for inertia-ssr ...${BASH_COLOR_RESET}"
        npm --prefix /data/www run build -- --ssr
        # Inertia SSR needs node_modules at runtime.
    else
        echo "Deleting node modules ..."
        rm -rf /data/www/node_modules
    fi

    echo "Build complete"
fi

# Set permissions only for paths that Laravel and Vite need to write to.
echo -e "${BASH_COLOR_WARNING}Setting writable directory permissions ...${BASH_COLOR_RESET}"
chown -R nginx:nginx /data/www/bootstrap/cache /data/www/storage
if [ "$IS_DEV_MODE" = true ] || { [ -f "$PACKAGE_FILE" ] && [ -d "$NODE_MODULES_DIRECTORY" ]; }; then
    chown nginx:nginx /data/www/public
fi

# migrate and seed database if needed
if [ -n "$DB_CONNECTION" ]; then
    # migrate database
    if [ "$ONSTART_MIGRATE" = "true" ]; then # default: ONSTART_MIGRATE=false
        echo -e "${BASH_COLOR_WARNING}Migrating database${BASH_COLOR_RESET}"
        php /data/www/artisan migrate --force
    fi

    # seed seeder
    if [ -n "$ONSTART_SEEDER" ] && [ "$ONSTART_SEEDER" != "false" ]; then
        if [ "$ONSTART_SEEDER" = "true" ]; then
            echo -e "${BASH_COLOR_WARNING}Seeding database using default seeder${BASH_COLOR_RESET}"
        else
            echo -e "${BASH_COLOR_WARNING}Seeding database using ${ONSTART_SEEDER}${BASH_COLOR_RESET}"
        fi

        run_seeder() {
            if [ "$ONSTART_SEEDER" = "true" ]; then
                php /data/www/artisan db:seed --force
            else
                php /data/www/artisan db:seed --force --class="$ONSTART_SEEDER"
            fi
        }

        if [ "$ONSTART_SEEDER_WAIT" = "true" ]; then
            run_seeder
        else
            run_seeder &
        fi
    fi
else
    echo -e "${BASH_COLOR_WARNING}No DB_CONNECTION was specified - skipping database migration/seeding${BASH_COLOR_RESET}"
fi

# Allows you to add /entrypoint.sh using your own Dockerfile - to automatically be executed
ADDITIONAL_ENTRYPOINT_FILE="/entrypoint.sh"
if [ -f "$ADDITIONAL_ENTRYPOINT_FILE" ]; then
    echo -e "${BASH_COLOR_WARNING}Found additional entrypoint. Running ${ADDITIONAL_ENTRYPOINT_FILE} ...${BASH_COLOR_RESET}"
    chmod +x "$ADDITIONAL_ENTRYPOINT_FILE"
    exec "$ADDITIONAL_ENTRYPOINT_FILE" "$@"
fi

# Run background jobs (runsv) or execute given CMD
if [ -z "$*" ]; then
    echo -e "${BASH_COLOR_DARK}Starting daemons and background jobs ...${BASH_COLOR_RESET}"
    /usr/bin/runsvdir /etc/service
else
    exec "$@"
fi
