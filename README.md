# 🐳 Docker Laravel

This Docker image provides everything you need to set up a Laravel application. With this image you can start developing directly without any dependencies.

Following packages are included:
 - PHP (8.1)
 - PHP-FPM (8.1)
 - Composer
 - NGINX (1.23)
 - Node (19.7)
 - NPM

Also already included/supported:
 - Cronjobs (using php artisan schedule:run)
 - Queue Worker (using php artisan queue:work or php artisan horizon)
 - Vite

## Getting started

Actually, you only need to run the Docker image and you can start right away.

**docker-compose-dev.yml**

```yml
version: '3'

services:
    laravel:
        image: prowect/laravel
        environment:
            APP_ENV: local
            # TODO: your laravel envs
        volumes:
            - "./src:/data/www"
        ports:
            - "8080:80"
            - "5173:5173"

```

**docker-compose-production.yml**

```yml
version: '3'

services:
    laravel:
        image: prowect/laravel
        restart: unless-stopped
        environment:
            APP_ENV: production
            # TODO: your laravel envs
        volumes:
            - "./src/storage:/data/www/storage"
        ports:
            - "8080:80"

```


## Configuration

Following environments are known by the image:

| Environment variable      | Default value | Possible values                        | Description
|---------------------------|---------------|----------------------------------------|-------------
| `APP_ENV`                 | `production`  | see Laravel docs                       | If `APP_ENV` is equal to `production` runs setup for production mode, otherweise development mode is used
| `CRONJOBS_ENABLED`        | `false`       | `true` / `false`                       | If `true` cronjobs are executed using `php artisan schedule:run`
| `QUEUE_CONNECTION`        |               | `database` / `redis`                   | If value does not equal `sync` queue worker will be started using `php artisan queue:work`
| `QUEUE_CONNECTION_SLEEP`  | `3`           | `0-n`                                  | Defines the sleep timeout in seconds for the queue worker (see Laravel docs for more information)
| `QUEUE_CONNECTION_TRIES`  | `1`           | `0-n`                                  | Defines the amount of (re)tries for the queue worker (see Laravel docs for more information)
| `QUEUE_CONNECTION_MEMORY` | `512M`        |                                        | Defines the memory used by the queue worker (see Laravel docs for more information)
| `HORIZON_ENABLED`         | `false`       | `true` / `false`                       | Use Laravel Horizon instead of Laravel Queue Worker (please note: that Laravel Horizon needs to be installed first)
| `PASSPORT_ENABLED`        | `false`       | `true` / `false`                       | If `true` automatically generates OAuth keys, if not already present, using `php artisan passport:keys` (please note: that Laravel Passport needs to be installed first)
| `DB_CONNECTION`           |               | `mysql` / `pgsql`, …                   | This is required to use database functions are described in the following
| `ONSTART_MIGRATE`         | `false`       | `true` / `false`                       | Automatically runs database migrations on start up using `php artisan migrate`
| `ONSTART_SEEDER`          | `false`       | `true` / `false` / `<SeederClassName>` | Automatically runs database seeder on start up. If `true` the default seeder (=DatabaseSeeder) is used, but you can also provide the class name of your own seeder, to use this one instead.


### Vite

When using Vite in development mode, please provide following config in your `vite.config.js`, to ensure it works properly:

Vite:
```js
export default defineConfig({
    server: {
        host: '0.0.0.0'
    }
});
```

> If you are using an different (custom) port for Vite, please note that this has to be configured in `vite.config.js` too.

## Production tips

For using this image in production we suggest: building your own Docker image, using this one as a base image.

```Dockerfile
# BUILD
FROM prowect/laravel as build

# copy your laravel files to /data/www
COPY ./src /data/www

# automatic magic builds your Laravel application with dependencies, etc.
RUN /main-entrypoint.sh echo "Build complete"

# BUNDLE
FROM prowect/laravel

# copy pre-built files to the new container (to start even faster)
COPY --from=build /data/www /data/www
```

> First step is building the laravel application. Usually this is done on startup of the image anyway, but for performance reasons we should fully build it and start the container already fully built.
