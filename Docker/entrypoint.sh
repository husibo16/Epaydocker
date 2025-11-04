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

sanitize_timezone() {
  local tz="$1"
  tz="$(printf '%s' "${tz}" | tr -d '\r')"
  tz="$(printf '%s' "${tz}" | awk '{$1=$1;print}')"
  if [[ "${tz}" == \"*\" && "${tz: -1}" == '"' ]]; then
    tz="${tz:1:${#tz}-2}"
  elif [[ "${tz}" == "'*" && "${tz: -1}" == "'" ]]; then
    tz="${tz:1:${#tz}-2}"
  fi
  printf '%s' "${tz}"
}

timezone_value=""

attempt_timezone() {
  local candidate="$1"
  local label="$2"
  local sanitized
  sanitized="$(sanitize_timezone "${candidate}")"
  if [[ -z "${sanitized}" ]]; then
    return 1
  fi
  if [[ "${sanitized}" == \#* ]]; then
    echo "[entrypoint] Ignoring ${label} value because it looks like a comment" >&2
    return 1
  fi
  if TZ_CHECK="${sanitized}" php -r 'exit(in_array(getenv("TZ_CHECK"), DateTimeZone::listIdentifiers(), true) ? 0 : 1);' >/dev/null 2>&1; then
    timezone_value="${sanitized}"
    return 0
  fi
  echo "[entrypoint] Warning: invalid ${label} timezone '${sanitized}', falling back to default" >&2
  return 1
}

if [[ -n "${PHP_TIMEZONE:-}" ]] && attempt_timezone "${PHP_TIMEZONE}" "PHP_TIMEZONE"; then
  :
elif [[ -n "${TZ:-}" ]]; then
  attempt_timezone "${TZ}" "TZ" || true
fi

if [[ -n "${timezone_value}" ]]; then
  echo "date.timezone=${timezone_value}" >> "${dynamic_ini}"
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
