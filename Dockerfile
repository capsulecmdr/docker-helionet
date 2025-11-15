# HelioNET app image builder (Dockerfile lives OUTSIDE app repo)
FROM php:8.3-fpm

# -----------------------------
# System packages & PHP extensions
# -----------------------------
RUN apt-get update && apt-get install -y \
    nginx \
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
    && rm -rf /var/lib/apt/lists/*

# Install Redis PHP extension
RUN pecl install redis \
    && docker-php-ext-enable redis

# Install Horizon dependencies (pcntl)
RUN docker-php-ext-install pcntl

# -----------------------------
# (Removed helios user; use default root + www-data inside processes)
# -----------------------------
# Previously we created a 'helios' user and forced PHP-FPM to run as it.
# That is now removed so we use the defaults (www-data inside FPM / nginx).

# -----------------------------
# Composer
# -----------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# -----------------------------
# Nginx + Supervisor configs (live in docker-helionet repo)
# -----------------------------
RUN rm -f /etc/nginx/nginx.conf /etc/nginx/sites-enabled/default
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/site.conf /etc/nginx/conf.d/default.conf

COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
#COPY supervisor/laravel-worker.conf /etc/supervisor/conf.d/laravel-worker.conf

# -----------------------------
# Ensure nginx log files exist and are readable
# -----------------------------
RUN mkdir -p /var/log/nginx \
    && touch /var/log/nginx/access.log /var/log/nginx/error.log \
    && chmod 644 /var/log/nginx/*.log \
    && chmod 755 /var/log/nginx

# -----------------------------
# Application code
# -----------------------------
WORKDIR /var/www/html

# Clean any default files
RUN rm -f /var/www/html/index.nginx-debian.html /var/www/html/helionet || true

# NOTE:
# If you are baking the app into the image, you would do:
COPY helionet/ ./
# and then run composer/artisan below.
# If you're using a bind mount, these commands are effectively no-ops.

# -----------------------------
# Install dependencies & optimize
# -----------------------------
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress || true

# Only cache routes/views at build time; config should be cached at runtime
RUN php artisan route:cache || true \
 && php artisan view:cache || true

# -----------------------------
# Runtime
# -----------------------------
EXPOSE 80

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
