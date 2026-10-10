FROM php:8.3-apache-bookworm

ARG MOODLE_BRANCH=MOODLE_501_STABLE
ENV APACHE_DOCUMENT_ROOT=/var/www/moodle/public

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git libcurl4-openssl-dev libfreetype6-dev \
      libicu-dev libjpeg62-turbo-dev libonig-dev libpng-dev \
      libxml2-dev libzip-dev unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j"$(nproc)" \
      bcmath curl exif gd intl mbstring mysqli opcache soap xml zip \
    && a2enmod rewrite headers \
    && sed -ri 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf \
    && sed -ri 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' \
      /etc/apache2/sites-available/000-default.conf \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "${MOODLE_BRANCH}" \
      https://github.com/moodle/moodle.git /var/www/moodle \
    && chown -R root:www-data /var/www/moodle \
    && find /var/www/moodle -type d -exec chmod 0755 {} + \
    && find /var/www/moodle -type f -exec chmod 0644 {} +

COPY moodle-vhost.conf /etc/apache2/sites-available/000-default.conf
COPY entrypoint.sh /usr/local/bin/moodle-entrypoint
RUN chmod 0755 /usr/local/bin/moodle-entrypoint

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/moodle-entrypoint"]
CMD ["apache2-foreground"]
