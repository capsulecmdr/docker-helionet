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
# Create unprivileged app user 'helios'
# -----------------------------
ARG APP_USER=helios
ARG APP_GROUP=helios
ARG APP_UID=1000
ARG APP_GID=1000

RUN groupadd -g ${APP_GID} ${APP_GROUP} \
    && useradd -u ${APP_UID} -g ${APP_GROUP} -m -d /var/www/html ${APP_USER}

# Make PHP-FPM run as helios instead of www-data
RUN sed -ri 's/^user = www-data/user = helios/' /usr/local/etc/php-fpm.d/www.conf \
 && sed -ri 's/^group = www-data/group = helios/' /usr/local/etc/php-fpm.d/www.conf

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
# Ensure nginx log files exist and are readable by PHP (helios + Log Viewer)
# -----------------------------
RUN mkdir -p /var/log/nginx \
    && touch /var/log/nginx/access.log /var/log/nginx/error.log \
    && chown ${APP_USER}:${APP_GROUP} /var/log/nginx/*.log \
    && chmod 644 /var/log/nginx/*.log \
    && chmod 755 /var/log/nginx

# -----------------------------
# Application code
# -----------------------------
WORKDIR /var/www/html

# Clean any default files
RUN rm -f /var/www/html/index.nginx-debian.html /var/www/html/helionet || true

# Copy app code from ./helionet subfolder and give ownership to helios
COPY --chown=${APP_USER}:${APP_GROUP} helionet/ ./

# -----------------------------
# Install dependencies & optimize (as helios)
# -----------------------------
USER ${APP_USER}

RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress || true

# Only cache routes/views at build time; config should be cached at runtime
RUN php artisan route:cache || true \
 && php artisan view:cache || true

# -----------------------------
# Final permissions tweaks (still helios-owned, but ensure writable paths)
# -----------------------------
USER root

# Keep storage + cache owned by helios and ensure read/write perms
RUN chown -R ${APP_USER}:${APP_GROUP} /var/www/html/storage /var/www/html/bootstrap/cache || true \
    && chmod -R ug+rw /var/www/html/storage /var/www/html/bootstrap/cache || true \
    && find /var/www/html/storage -type d -exec chmod 775 {} \; || true \
    && find /var/www/html/storage -type f -exec chmod 664 {} \; || true

# -----------------------------
# Runtime
# -----------------------------
EXPOSE 80

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
