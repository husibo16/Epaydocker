#!/usr/bin/env bash
set -euo pipefail

# Configure PHP limits dynamically
dynamic_ini="/usr/local/etc/php/conf.d/zz-dynamic.ini"
>"${dynamic_ini}"

if [[ -n "${PHP_MEMORY_LIMIT:-}" ]]; then
  echo "memory_limit=${PHP_MEMORY_LIMIT}" >> "${dynamic_ini}"
fi

if [[ -n "${PHP_UPLOAD_LIMIT:-}" ]]; then
  {
    echo "upload_max_filesize=${PHP_UPLOAD_LIMIT}"
    echo "post_max_size=${PHP_UPLOAD_LIMIT}"
  } >> "${dynamic_ini}"
fi

if [[ ! -s "${dynamic_ini}" ]]; then
  rm -f "${dynamic_ini}"
fi

cd /var/www/html

if [[ -d /var/www/html ]]; then
  current_owner="$(stat -c '%U:%G' /var/www/html)"
  if [[ "${current_owner}" != "www-data:www-data" ]]; then
    chown -R www-data:www-data /var/www/html
  fi
fi

if [[ -f composer.json ]]; then
  if [[ ! -f vendor/autoload.php ]]; then
    composer install --no-dev --optimize-autoloader --no-interaction
  fi
  composer dump-autoload --optimize --no-interaction || true
fi

if [[ -f artisan ]]; then
  php artisan config:cache || true
  php artisan route:cache || true
  php artisan view:cache || true
fi

exec "$@"