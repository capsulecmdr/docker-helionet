# HelioNET app image builder (Dockerfile lives OUTSIDE app repo)
FROM php:8.3-fpm

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




COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Nginx + Supervisor configs live in docker-helionet repo
RUN rm -f /etc/nginx/nginx.conf /etc/nginx/sites-enabled/default
COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/site.conf /etc/nginx/conf.d/default.conf

COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor/laravel-worker.conf /etc/supervisor/conf.d/laravel-worker.conf

WORKDIR /var/www/html

# ---- HERE is the magic: COPY app code from ./helionet subfolder ----
COPY helionet/ ./

RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress || true

RUN php artisan config:cache || true \
 && php artisan route:cache || true \
 && php artisan view:cache || true

RUN chown -R www-data:www-data /var/www

EXPOSE 80
CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
