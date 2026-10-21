# 🐳 Docker Laravel

This Docker image provides everything you need to set up a Laravel application. With this image you can start developing directly without any dependencies.

Following packages are included:
 - Alpine Linux (3.24)
 - PHP and PHP-FPM (8.5.12 or newer)
 - Composer (2.10.3)
 - NGINX (1.31.7)
 - Node.js (24 LTS, from Alpine 3.24)
 - npm (from Alpine 3.24)

Also already included/supported:
 - Cronjobs (using php artisan schedule:run)
 - Queue Worker (using php artisan queue:work or php artisan horizon)
 - Vite

## Local testing

Build the image and run the local entrypoint, PHP-FPM, NGINX, healthcheck, header and service tests:

```sh
./run-tests.sh
```

Additionally build and start a derived production image using a local Laravel application:

```sh
./run-tests.sh --app /absolute/path/to/laravel
```

Repeat the derived-image build without cache and run multiple builds in parallel:

```sh
./run-tests.sh --app /absolute/path/to/laravel --repeat 10 --parallel 3
```

The Laravel project is copied to a temporary test context. Its source files are not modified, and local secrets, `vendor`, `node_modules` and existing Vite build artifacts are excluded. Projects with a `package.json` must also provide a `package-lock.json` or `npm-shrinkwrap.json`, because the production build uses `npm ci`. Functional tests are intentionally local; CI only builds and vulnerability-scans the base image before publishing it.

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
| `QUEUE_CONNECTION`        |               | `sync` / `database` / `redis`          | If configured and not equal to `sync`, a queue worker is started using `php artisan queue:work`
| `QUEUE_CONNECTION_SLEEP`  | `3`           | `0-n`                                  | Defines the sleep timeout in seconds for the queue worker (see Laravel docs for more information)
| `QUEUE_CONNECTION_TRIES`  | `1`           | `0-n`                                  | Defines the amount of (re)tries for the queue worker (see Laravel docs for more information)
| `QUEUE_CONNECTION_MEMORY` | `512`         | `0-n`                                  | Defines the memory limit in megabytes used by the queue worker (see Laravel docs for more information)
| `HORIZON_ENABLED`         | `false`       | `true` / `false`                       | Use Laravel Horizon instead of Laravel Queue Worker (please note: that Laravel Horizon needs to be installed first)
| `PASSPORT_ENABLED`        | `false`       | `true` / `false`                       | If `true` automatically generates OAuth keys, if not already present, using `php artisan passport:keys` (please note: that Laravel Passport needs to be installed first)
| `DB_CONNECTION`           |               | `mysql` / `pgsql`, …                   | This is required to use database functions are described in the following
| `ONSTART_MIGRATE`         | `false`       | `true` / `false`                       | Automatically runs database migrations on start up using `php artisan migrate`
| `ONSTART_SEEDER`          | `false`       | `true` / `false` / `<SeederClassName>` | Automatically runs database seeder on start up. If `true` the default seeder (=DatabaseSeeder) is used, but you can also provide the class name of your own seeder, to use this one instead.
| `ONSTART_SEEDER_WAIT`     | `true`        | `true` / `false`                       | If `true` the seeder is executed on startup and failures stop the container. If `false` the seeder is executed in background, so its result cannot affect the entrypoint exit code.
| `XDEBUG_ENABLED`          | `false`       | `true` / `false`                       | Activate PHP Xdebug for debugging your application
| `INERTIA_SSR_ENABLED`     | `false`       | `true` / `false`                       | Activate Inertia SSR for server side rendering of your Inertia application (please note: that Laravel Inertia SSR needs to be installed first)

The image healthcheck uses the internal NGINX endpoint `http://127.0.0.1:8081/healthz`. It remains available when a derived image replaces `/etc/nginx/conf.d/default.conf`. NGINX version tokens and PHP's `X-Powered-By` response header are disabled globally for all server configurations in `/etc/nginx/conf.d`.

### PHP Xdebug

PHP Xdebug is already preinstalled an would listen to: `host.docker.internal` and port: `9003` as default, which should work fine when working on  You can change this behaviour by overriding: `xdebug.ini`.
To enable PHP Xdebug you have to define: `XDEBUG_ENABLED` environment variable.
You also have to specify settings in your used IDE, for VSCode it would look like that:

**launch.json**

```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Listen for Xdebug",
            "type": "php",
            "request": "launch",
            "port": 9003,
            "pathMappings": {
                "/data/www/": "${workspaceFolder}/src"
            }
        }
    ]
}
```

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
FROM prowect/laravel AS build

# copy your laravel files to /data/www
COPY ./src /data/www

# automatic magic builds your Laravel application with dependencies, etc.
RUN MODE=build /main-entrypoint.sh echo "Build complete"

# BUNDLE
FROM prowect/laravel

# copy pre-built files to the new container (to start even faster)
COPY --from=build /data/www /data/www
```

> First step is building the laravel application. Usually this is done on startup of the image anyway, but for performance reasons we should fully build it and start the container already fully built.
> Set `INERTIA_SSR_ENABLED=true` during the build when the application requires an additional SSR bundle.

During `MODE=build`, the image defaults `CACHE_STORE` and `SESSION_DRIVER` to `array`, `QUEUE_CONNECTION` to `sync`, and `DB_CONNECTION` to `sqlite`. This prevents Laravel's build-time cache preparation from requiring external services. Explicit environment values continue to override these defaults.

## Upgrading from v2

Version 3 is a breaking release. Before changing the image tag, verify the following:

- The image uses the official PHP 8.5.12 release and compiles its extensions against the same PHP version. Update Composer dependencies whose PHP constraints exclude PHP 8.5. Do not bypass this with `--ignore-platform-req=php`.
- The entrypoint exits immediately when Composer, npm, Artisan, migration, synchronous seeding, or another setup command fails. Fix commands that previously failed without stopping the container.
- Production builds use `composer install --no-dev --optimize-autoloader` and `npm ci`. Commit compatible `composer.lock` and `package-lock.json` or `npm-shrinkwrap.json` files.
- The default for `ONSTART_SEEDER_WAIT` is now `true`. Set it to `false` only when asynchronous seeding is explicitly required and failures may be handled separately.
- Custom `/entrypoint.sh` scripts receive the container command and arguments in `"$@"` and should forward or handle them as needed.
- The built-in healthcheck uses `127.0.0.1:8081`; do not bind application services to that internal port.
