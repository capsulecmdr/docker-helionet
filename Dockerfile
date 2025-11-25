# HelioNET app image builder (Dockerfile lives OUTSIDE app repo)
FROM php:8.3-apache

# -----------------------------
# System packages & PHP extensions
# -----------------------------
RUN apt-get update && apt-get install -y \
    supervisor \
    git \
    unzip \
    curl \
    pkg-config \
    libzip-dev \
    libpng-dev \
    libicu-dev \
    libxml2-dev \
    libpq-dev \
    libssl-dev \
    libonig-dev \
    && docker-php-ext-install \
        pdo_mysql \
        intl \
        mbstring \
        zip \
        pcntl \
    && rm -rf /var/lib/apt/lists/*

# Redis PHP extension
RUN pecl install redis \
    && docker-php-ext-enable redis

# -----------------------------
# Apache config
# -----------------------------
# Enable modules Laravel needs
RUN a2enmod rewrite headers

# Optional but nice: custom vhost instead of default
# (we'll create apache/helionet.conf in the docker-helionet repo)
COPY apache/helionet.conf /etc/apache2/sites-available/000-default.conf

# Make sure Apache logs dir exists (base image already has it, but this is safe)
RUN mkdir -p /var/log/apache2 \
    && touch /var/log/apache2/access.log /var/log/apache2/error.log \
    && chmod 644 /var/log/apache2/*.log

# -----------------------------
# Composer
# -----------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# -----------------------------
# Supervisor config (lives in docker-helionet repo)
# -----------------------------
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
# If you have extra program configs, you can keep them in conf.d as before:
# COPY supervisor/laravel-worker.conf /etc/supervisor/conf.d/laravel-worker.conf

# -----------------------------
# Application code
# -----------------------------
WORKDIR /var/www/html

# Clean any default files
RUN rm -f /var/www/html/index.html /var/www/html/index.php /var/www/html/helionet || true

# NOTE:
# If you are baking the app into the image, you would do:
COPY helionet/ ./

# -----------------------------
# HelioNET dynamic package scripts
# -----------------------------
COPY scripts/PackageDirectory.php scripts/bootstrap-packages.php /var/www/html/scripts/
RUN chmod +x /var/www/html/scripts/bootstrap-packages.php

# -----------------------------
# Install dependencies & optimize
# -----------------------------
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress || true

# Only cache routes/views at build time; config should be cached at runtime
RUN php artisan route:cache || true \
 && php artisan view:cache || true

# -----------------------------
# Permissions (storage + cache)
# -----------------------------
RUN chown -R www-data:www-data /var/www/html \
    && find storage -type d -exec chmod 775 {} \; || true \
    && find storage -type f -exec chmod 664 {} \; || true \
    && chmod -R 775 bootstrap/cache || true

# -----------------------------
# Entrypoint
# -----------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# -----------------------------
# Runtime
# -----------------------------
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
