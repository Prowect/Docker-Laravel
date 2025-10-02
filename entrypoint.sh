#!/bin/sh

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
export IS_BUILD_MODE=$([ "$MODE" = "build" ] && echo true || echo false)
export IS_DEV_MODE=$([ "$MODE" = "dev" -o "$APP_ENV" = "local" ] && echo true || echo false)
export IS_RUN_MODE=$([ "$MODE" = "run" -o "$APP_ENV" = "production" ] && echo true || echo false)

echo -e "${BASH_COLOR_DARK}Current mode: ${BASH_COLOR_PRIMARY}$MODE${BASH_COLOR_RESET}"

if [ "$IS_BUILD_MODE" = true ]; then
    echo -e "${BASH_COLOR_DARK}Running container build ...${BASH_COLOR_RESET}"
else
    echo -e "${BASH_COLOR_DARK}Starting Docker Laravel ...${BASH_COLOR_RESET}"
fi

# Setup laravel/install composer packages if not present
LARAVEL_BOOTSTRAP_APP_FILE="/data/www/bootstrap/app.php"
COMPOSER_DIRECTORY="/data/www/vendor"
if [[ ! -f "$LARAVEL_BOOTSTRAP_APP_FILE" ]]; then
    echo -e "${BASH_COLOR_WARNING}No laravel source files detected. Installing a new laravel instance ...${BASH_COLOR_RESET}"

    composer create-project laravel/laravel .

    echo -e "${BASH_COLOR_SUCCESS}Laravel has been installed: ${BASH_COLOR_PRIMARY}$(php artisan --version)${BASH_COLOR_RESET}"
elif [[ ! -d "$COMPOSER_DIRECTORY" ]]; then
    echo -e "${BASH_COLOR_WARNING}Installing composer dependencies ...${BASH_COLOR_RESET}"

    composer install --no-scripts
fi

# Setup node_modules if not present
NODE_MODULES_DIRECTORY="/data/www/node_modules";
# only for build or dev mode
if [ ! -d "$NODE_MODULES_DIRECTORY" ] && { [ "$IS_BUILD_MODE" = true ] || [ "$IS_DEV_MODE" = true ]; }; then
    npm ci
fi

# Create storage folders (they may not exist when mounted)
mkdir -p /data/www/storage && \
mkdir -p /data/www/storage/app && \
mkdir -p /data/www/storage/mediafiles && \
mkdir -p /data/www/storage/framework/cache && \
mkdir -p /data/www/storage/framework/sessions && \
mkdir -p /data/www/storage/framework/views && \
mkdir -p /data/www/storage/logs

# create storage symlink (because we cannot access storage outside of public directory)
STORAGE_LINK_PATH="/data/www/public/storage"
if [[ ! -L "$STORAGE_LINK_PATH" ]]; then
    echo -e "${BASH_COLOR_WARNING}Creating laravel storage link ...${BASH_COLOR_RESET}"
    php /data/www/artisan storage:link
fi

# Clear and fill laravel caches
echo -e "${BASH_COLOR_WARNING}Clearing laravel caches ...${BASH_COLOR_RESET}"
php /data/www/artisan cache:clear
php /data/www/artisan config:clear
php /data/www/artisan route:clear
APP_ENV=${APP_ENV:="production"}
if [ "$APP_ENV" != "local" ]; then # create caches (prepare for production)
    echo -e "Preparing cache for environment ${BASH_COLOR_WARNING}$APP_ENV${BASH_COLOR_RESET}"
    php /data/www/artisan config:cache
    php /data/www/artisan route:cache
fi

# Generate passport keys if not present
if [ ! -z "$PASSPORT_ENABLED" ]; then
    if [ "$PASSPORT_ENABLED" == "true" ]; then
        if [ ! -e /data/www/storage/oauth-private.key ]; then
            php /data/www/artisan passport:keys
        fi
    fi
fi

# Enable/disable XDEBUG
XDEBUG_INI_PATH="/etc/${PHP_VERSION}/conf.d/xdebug.ini"
if [[ ! -z "$XDEBUG_ENABLED" ]] && [[ "$XDEBUG_ENABLED" == "true" ]]; then
    echo -e "${BASH_COLOR_WARNING}Enabling XDEBUG${BASH_COLOR_RESET}"
    ln -sf /etc/${PHP_VERSION}/templates/xdebug.ini $XDEBUG_INI_PATH
else 
    echo -e "${BASH_COLOR_WARNING}Disabling XDEBUG${BASH_COLOR_RESET}"
    if [ -L ${XDEBUG_INI_PATH} ] ; then
        unlink $XDEBUG_INI_PATH
    fi
fi

# Do a vite build (in build mode)
if [ "$IS_BUILD_MODE" = true ]; then
    VITE_BUILD_DIRECTORY="/data/www/public/build"
    if [ ! -d "$VITE_BUILD_DIRECTORY" ] || [ -z "$(ls -A "$VITE_BUILD_DIRECTORY")" ]; then
        echo -e "${BASH_COLOR_WARNING}Running vite build ...${BASH_COLOR_RESET}"
        npm --prefix /data/www run build

        echo "Deleting node modules ..."
        rm -rf /data/www/node_modules
        echo "Build complete"
    fi
fi

# Set permissions for nginx /data/www
echo -e "${BASH_COLOR_WARNING}Setting permissions for /data/www ...${BASH_COLOR_RESET}"
if [ "$IS_BUILD_MODE" = true ]; then
    chown -R nginx:nginx /data/www
else
    chown -R nginx:nginx /data/www &
fi

# migrate and seed database if needed
if [ ! -z "$DB_CONNECTION" ]; then
    # migrate database
    if [ "$ONSTART_MIGRATE" == "true" ]; then # default: ONSTART_MIGRATE=false
        echo -e "${BASH_COLOR_WARNING}Migrating database${BASH_COLOR_RESET}"
        php /data/www/artisan migrate --force
    fi

    # seed seeder
    if [ ! -z "$ONSTART_SEEDER" ]; then # default: ONSTART_SEEDER=
        SEEDER_WAIT=${ONSTART_SEEDER_WAIT:-false}
        SEED_CMD="php /data/www/artisan db:seed --force"
        if [ "$ONSTART_SEEDER" == "true" ]; then
            echo -e "${BASH_COLOR_WARNING}Seeding database using default seeder${BASH_COLOR_RESET}"
        else
            echo -e "${BASH_COLOR_WARNING}Seeding database using ${ONSTART_SEEDER}${BASH_COLOR_RESET}"
            SEED_CMD="$SEED_CMD --class=$ONSTART_SEEDER"
        fi
        if [ "$SEEDER_WAIT" == "true" ]; then
            $SEED_CMD
        else
            $SEED_CMD &
        fi
    fi
else
    echo -e "${BASH_COLOR_WARNING}No DB_CONNECTION was specified - skipping database migration/seeding${BASH_COLOR_RESET}"
fi

# Allows you to add /entrypoint.sh using your own Dockerfile - to automatically be executed
ADDITIONAL_ENTRYPOINT_FILE="/entrypoint.sh"
if [[ -f "$ADDITIONAL_ENTRYPOINT_FILE" ]]; then
    echo -e "${BASH_COLOR_WARNING}Found additional entrypoint. Running ${ADDITIONAL_ENTRYPOINT_FILE} ...${BASH_COLOR_RESET}"
    chmod +x $ADDITIONAL_ENTRYPOINT_FILE
    exec $ADDITIONAL_ENTRYPOINT_FILE
fi

# Run background jobs (runsv) or execute given CMD
if [ -z "$*" ]; then
    echo -e "${BASH_COLOR_DARK}Starting daemons and background jobs ...${BASH_COLOR_RESET}"
    /usr/bin/runsvdir /etc/service
else
    exec "$@"
fi
