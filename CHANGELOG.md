# Changelog

All notable changes to this project are documented in this file.

## [3.0.1] - 2026-07-20

### Security

- Upgraded NGINX from 1.31.2 to 1.31.3 to fix the `map` and regular-expression heap buffer overflow tracked as CVE-2026-42533.
- The NGINX update also fixes CVE-2026-60005 in `ngx_http_slice_module` and CVE-2026-56434 in `ngx_http_ssi_module`.
- Updated and pinned the NGINX base image to Alpine Linux 3.24 to prevent packages from different Alpine releases being mixed.
- Kept the bundled Node.js runtime on the 24 LTS release line while updating Alpine packages.

## [3.0.0] - 2026-07-19

### Breaking changes

- Upgraded the runtime from PHP 8.3 to PHP 8.5. Applications must use Composer dependencies compatible with PHP 8.5.
- Upgraded Alpine Linux from 3.22 to 3.23, NGINX from 1.29 to 1.31, and the bundled Node.js runtime to 24.15.
- The entrypoint now uses strict error handling and exits as soon as a setup command fails. Builds or containers that depended on ignored Composer, npm, Artisan, migration, or seeding failures must be corrected.
- Production build mode now runs `composer install --no-dev --optimize-autoloader` and always runs `npm ci` when a `package.json` is present. Lock files must be present and compatible.
- `ONSTART_SEEDER_WAIT` now defaults to `true`, so seeder failures stop startup by default.
- Custom `/entrypoint.sh` scripts now receive the image command and all arguments through `"$@"`.
- The Docker healthcheck now uses the reserved internal endpoint `http://127.0.0.1:8081/healthz`.

### Added

- Added deterministic, verified Composer 2.10.2 installation.
- Added build-only Laravel defaults that avoid external cache, session, queue, and database dependencies unless explicitly configured.
- Added local base-image and derived-Laravel test scripts, including repeatable parallel builds.
- Added a Trivy vulnerability scan to GitHub Actions for high and critical vulnerabilities.
- Added an isolated NGINX health server that remains available when derived images replace the public server configuration.

### Security

- Disabled NGINX version tokens globally.
- Disabled PHP version exposure and removed the `X-Powered-By` response header globally.
- Disabled `cgi.fix_pathinfo`.
- Updated Alpine packages during the image build.

### Fixed

- Composer dependencies are installed deterministically during every image build, preventing intermittent missing `vendor` directories in derived images.
- Entrypoint failures now propagate their original exit code.
- Synchronous seeder failures now stop startup.
- Queue workers no longer start when no asynchronous queue connection is configured.
- Inertia SSR builds retain runtime Node.js dependencies only when explicitly enabled.
