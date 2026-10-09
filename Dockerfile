FROM php:8.3-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libzip-dev \
    zip \
    unzip \
    git \
    ca-certificates \
    cron \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" gd mysqli pdo pdo_mysql zip \
    && a2enmod rewrite headers

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && printf '\nmemory_limit=256M\nmax_execution_time=120\n' >> "$PHP_INI_DIR/php.ini"

WORKDIR /var/www/html

# The upstream Dockerfile expects Docker Compose to bind-mount the source.
# Render builds an image without that bind mount, so fetch the official source here.
RUN git clone --depth 1 --branch master https://github.com/Shadowss/TravianZ.git /tmp/travianz \
    && cp -a /tmp/travianz/. /var/www/html/ \
    && rm -rf /tmp/travianz /var/www/html/.git \
    && mkdir -p /var/www/html/var \
    && chown -R www-data:www-data /var/www/html

# Render's default web-service port is 10000.
RUN sed -ri 's/Listen 80/Listen 10000/' /etc/apache2/ports.conf \
    && sed -ri 's/<VirtualHost \*:80>/<VirtualHost *:10000>/' /etc/apache2/sites-available/000-default.conf \
    && sed -ri 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# TravianZ v11 moved game automation to cron. Keep it in the same container
# so it can use the configuration created by the web installer.
RUN printf '*/5 * * * * www-data cd /var/www/html && /usr/local/bin/php /var/www/html/cron.php >> /var/log/travianz-cron.log 2>&1\n' > /etc/cron.d/travianz \
    && chmod 0644 /etc/cron.d/travianz

EXPOSE 10000
CMD ["bash", "-lc", "printf 'MARIADB_ROOT_PASSWORD=%s\\nMARIADB_DATABASE=%s\\nMARIADB_USER=%s\\nMARIADB_PASSWORD=%s\\nMYSQL_ROOT_PASSWORD=%s\\nMYSQL_DATABASE=%s\\nMYSQL_USER=%s\\nMYSQL_PASSWORD=%s\\nDB_HOST=%s\\nDB_PORT=%s\\n' \"$MARIADB_ROOT_PASSWORD\" \"$MARIADB_DATABASE\" \"$MARIADB_USER\" \"$MARIADB_PASSWORD\" \"$MARIADB_ROOT_PASSWORD\" \"$MARIADB_DATABASE\" \"$MARIADB_USER\" \"$MARIADB_PASSWORD\" \"$DB_HOST\" \"$DB_PORT\" > /var/www/html/.env && chown www-data:www-data /var/www/html/.env && cron && exec apache2-foreground"]
