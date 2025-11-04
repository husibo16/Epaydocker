# syntax=docker/dockerfile:1.6
FROM php:8.2-fpm AS base

# Set up system dependencies and PHP extensions
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        cron \
        git \
        iproute2 \
        iputils-ping \
        libcurl4-openssl-dev \
        libonig-dev \
        libssl-dev \
        libxml2-dev \
        mariadb-client \
        libfcgi-bin \
        netcat-openbsd \
        net-tools \
        procps \
        unzip \
    ; \
    missingDeps=""; \
    check_dep() { \
        if ! dpkg -s "$1" >/dev/null 2>&1; then \
            missingDeps="$missingDeps $1"; \
        fi; \
    }; \
    # Dependencies for PHP extensions (gd, intl, zip)
    check_dep libzip-dev; \
    check_dep libpng-dev; \
    check_dep libjpeg62-turbo-dev; \
    check_dep libfreetype6-dev; \
    check_dep libicu-dev; \
    if [ -n "$missingDeps" ]; then \
        apt-get install -y --no-install-recommends $missingDeps; \
    fi; \
    docker-php-ext-configure gd --with-jpeg --with-freetype; \
    docker-php-ext-install -j"$(nproc)" \
        bcmath \
        exif \
        gd \
        intl \
        mbstring \
        mysqli \
        opcache \
        pcntl \
        pdo_mysql \
        sockets \
        zip \
    ; \
    pecl install redis; \
    docker-php-ext-enable redis; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

WORKDIR /var/www/html

COPY Docker/php.ini /usr/local/etc/php/conf.d/99-overrides.ini
COPY Docker/entrypoint.sh /usr/local/bin/entrypoint
COPY Docker/php-fpm-healthcheck.conf /usr/local/etc/php-fpm.d/zz-healthcheck.conf

RUN chmod +x /usr/local/bin/entrypoint

ENV PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_LIMIT=64M \
    APP_ENV=production

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["php-fpm"]

FROM base AS scheduler
HEALTHCHECK NONE
CMD ["php", "/var/www/html/cron.php"]

FROM base
HEALTHCHECK --interval=30s --timeout=5s --retries=5 --start-period=10s CMD SCRIPT_NAME=/ping SCRIPT_FILENAME=/ping REQUEST_METHOD=GET cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1
CMD ["php-fpm"]