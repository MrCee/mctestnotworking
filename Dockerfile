# --------------------------------------------
# Stage 0: Base Setup (PHP, NGINX, Runtime Libs)
# --------------------------------------------
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm-alpine AS base

ARG IP_VERSION
ARG IP_SOURCE
ARG IP_LANGUAGE
ARG IP_IMAGE
ARG PUID
ARG PGID
ARG BUILD_DATE

ENV PHP_VERSION=${PHP_VERSION} \
    IP_VERSION=${IP_VERSION} \
    IP_SOURCE=${IP_SOURCE} \
    IP_LANGUAGE=${IP_LANGUAGE} \
    IP_IMAGE=${IP_IMAGE} \
    PUID=${PUID} \
    PGID=${PGID} \
    TMPDIR=/var/tmp \
    BUILD_DATE=${BUILD_DATE}

# Install runtime & build deps
RUN apk add --no-cache \
      nginx \
      mariadb-client \
      vim \
      curl \
      unzip \
      patch \
      bash \
      shadow \
      libwebp \
      libpng \
      freetype \
      libjpeg-turbo \
      icu-libs \
      oniguruma \
      libxml2 \
      libxslt \
      libxpm && \
    apk add --no-cache --virtual .build-deps \
      build-base \
      linux-headers \
      autoconf \
      file \
      g++ \
      gcc \
      libc-dev \
      make \
      pkgconf \
      re2c \
      binutils \
      zlib-dev \
      libtool \
      automake \
      freetype-dev \
      libjpeg-turbo-dev \
      libwebp-dev \
      libpng-dev \
      icu-dev \
      oniguruma-dev \
      libxml2-dev \
      libxslt-dev \
      libxpm-dev && \
    docker-php-ext-configure gd \
      --enable-gd --with-freetype --with-jpeg --with-webp --with-xpm --enable-gd-jis-conv && \
    docker-php-ext-install -j$(nproc) gd intl bcmath dom mysqli && \
    apk del .build-deps && \
    rm -rf /var/cache/apk/* /tmp/* /usr/src/php*

# Runtime dirs
RUN mkdir -p /var/tmp && chmod 1777 /var/tmp
RUN mkdir -p /run && chown www-data:nginx /run

# --------------------------------------------
# Stage 1: Composer Builder (download + patch + install)
# --------------------------------------------
FROM base AS composer-builder
WORKDIR /build

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Download & extract InvoicePlane
RUN VERSION=$(echo ${IP_VERSION} | grep -q '^v' && echo ${IP_VERSION} || echo "v${IP_VERSION}") && \
    curl -L ${IP_SOURCE}/${VERSION}/${VERSION}.zip -o /tmp/app.zip && \
    unzip /tmp/app.zip -d /tmp && \
    mv /tmp/ip/* /build && \
    rm -rf /tmp/app.zip /tmp/ip

# Remove vendor & re-install clean
RUN rm -rf /build/vendor

COPY composer.json composer.lock /build/
COPY patches /tmp/patches
RUN if [ -d /tmp/patches ] && [ "$(ls -A /tmp/patches)" ]; then \
      echo "🩹 Applying patches from /tmp/patches..."; \
      cd /build && \
      for patch in /tmp/patches/*.patch; do \
        echo "🔧 Applying $patch..."; \
        patch -p1 --batch --forward < "$patch" || echo "⚠️ Failed to apply $patch"; \
      done; \
    fi && rm -rf /tmp/patches

WORKDIR /build
RUN composer install --no-dev --optimize-autoloader

# --------------------------------------------
# Stage 2: Final Runtime Image
# --------------------------------------------
FROM base

# 🌍 Working directory
WORKDIR /var/www/html

# 📦 Copy application files
COPY --from=composer-builder /build /var/www/html

# 🔄 Copy default fallback for bind-mounts
RUN mkdir -p /var/www/html_default && \
    cp -a /var/www/html/. /var/www/html_default/

# 📁 Configs and scripts
COPY setup/php.ini /usr/local/etc/php/php.ini
COPY setup/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY setup/default.conf /etc/nginx/http.d/default.conf
COPY setup/wait-for-db.sh /usr/local/bin/wait-for-db.sh
COPY setup/verify-permissions.sh /usr/local/bin/verify-permissions.sh
COPY setup/setup-watcher.sh /usr/local/bin/setup-watcher.sh
COPY setup/custom-complete.php /usr/local/share/custom-complete.php
COPY kickstart.sh /usr/local/bin/kickstart.sh 
COPY .env.example /var/www/html/.env.example
RUN mv /usr/local/etc/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.disabled || true

# 🚀 Final ENTRYPOINT: Smart cross-platform bootstrapper
COPY setup/entrypoint.sh /usr/local/bin/entrypoint.sh

# ✅ Permissions & ownership
RUN chmod +x /usr/local/bin/*.sh && \
    chown -R www-data:nginx /var/www/html /var/www/html_default

# 🔥 Expose port 80
EXPOSE 80

# 🧠 Entrypoint now handles everything (env, config, services)
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]


