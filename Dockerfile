# HelioNET app image builder (Dockerfile lives OUTSIDE app repo)
FROM php:8.3-apache-bookworm

# -----------------------------
# OS packages
# -----------------------------
RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    git \
    unzip \
    curl \
    pkg-config \
    zip unzip libzip-dev \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev libwebp-dev \
    libicu-dev libxml2-dev libpq-dev libssl-dev libonig-dev \
    mariadb-client redis-tools \
    nano \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# -----------------------------
# PHP Extensions
# -----------------------------
RUN pecl install redis \
  && docker-php-ext-enable redis \
  && docker-php-ext-configure gd \
      --with-freetype \
      --with-webp \
      --with-jpeg \
  && docker-php-ext-install -j"$(nproc)" \
      pdo_mysql \
      intl \
      mbstring \
      zip \
      gd \
      pcntl \
  && apt-get autoremove -y

# -----------------------------
# Composer
# -----------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# -----------------------------
# User & group (for Apache workers / file ownership)
# -----------------------------
RUN groupadd -r -g 200 helionet && useradd --no-log-init -r -g helionet -u 200 helionet

# -----------------------------
# Apache config
# -----------------------------
# Enable modules needed for Laravel
RUN a2enmod rewrite headers

# Use your custom vhost (should set DocumentRoot to /var/www/html/public)
COPY apache/helionet.conf /etc/apache2/sites-available/000-default.conf

# Change Apache port 80 -> 8080 (like SeAT does)
RUN sed -i 's/80/8080/g' /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf

# Run Apache worker processes as helionet instead of www-data
# (the parent httpd will still start as root, then drop privileges for workers)
RUN sed -ri 's/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=helionet/' /etc/apache2/envvars \
  && sed -ri 's/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=helionet/' /etc/apache2/envvars

# Make sure Apache log/run dirs are owned by helionet (workers need write access)
RUN mkdir -p /var/log/apache2 /var/run/apache2 /var/lock/apache2 \
  && chown -R helionet:helionet /var/log/apache2 /var/run/apache2 /var/lock/apache2

# -----------------------------
# Application code
# -----------------------------
WORKDIR /var/www/html

# Clean any default stuff
RUN rm -f /var/www/html/index.html /var/www/html/index.php /var/www/html/helionet || true

# Copy your app repo (helionet directory is in build context root)
COPY helionet/ ./

# HelioNET dynamic package scripts
COPY scripts/PackageDirectory.php scripts/bootstrap-packages.php /var/www/html/scripts/
RUN chmod +x /var/www/html/scripts/bootstrap-packages.php

# -----------------------------
# Install dependencies & optimize
# -----------------------------
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress || true \
 && php artisan route:cache || true \
 && php artisan view:cache || true

# -----------------------------
# Permissions – app owned by helionet (Apache workers)
# -----------------------------
RUN chown -R helionet:helionet /var/www/html \
  && find storage -type d -exec chmod 775 {} \; || true \
  && find storage -type f -exec chmod 664 {} \; || true \
  && chmod -R 775 bootstrap/cache || true

# -----------------------------
# Entrypoint
# -----------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# NOTE: we DO NOT switch USER here – root stays the container user.
# Apache parent runs as root (inside the container), workers drop to helionet.

USER helionet

#fix tinker home issue
ENV XDG_CONFIG_HOME=/tmp

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2ctl", "-D", "FOREGROUND"]
