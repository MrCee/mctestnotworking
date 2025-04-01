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

# Install runtime & build deps (split for cleanup)
RUN apk add --no-cache \
      patch \
      curl \
      unzip \
      nginx \
      mariadb-client \
      shadow \
      libwebp \
      libpng \
      freetype \
      libjpeg-turbo \
      icu-libs \
      oniguruma \
      libxml2 \
      libxslt \
      libxpm \
  && apk add --no-cache --virtual .build-deps \
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
      libxpm-dev \
  && docker-php-ext-configure gd \
      --enable-gd --with-freetype --with-jpeg --with-webp --with-xpm --enable-gd-jis-conv \
  && docker-php-ext-install -j$(nproc) gd intl bcmath dom mysqli \
  && apk del .build-deps \
  && rm -rf /var/cache/apk/* /tmp/* /usr/src/php*

# Runtime dirs
RUN mkdir -p /run/php /var/tmp && \
    chmod 1777 /var/tmp && \
    chmod 770 /run/php && \
    chown -R www-data:nginx /run/php

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

# Remove outdated vendor
RUN rm -rf /build/vendor

# Copy in patches and apply them
COPY patches /tmp/patches
RUN if [ -d /tmp/patches ] && [ "$(ls -A /tmp/patches)" ]; then \
      echo "🩹 Applying patches from /tmp/patches..."; \
      cd /build && \
      for patch in /tmp/patches/*.patch; do \
        echo "🔧 Applying $patch..."; \
        patch -p1 --batch --forward < "$patch" || echo "⚠️ Failed to apply $patch"; \
      done; \
    fi && rm -rf /tmp/patches

# Composer install (after patching)
COPY composer.json composer.lock /build/
WORKDIR /build
RUN composer install --no-dev --optimize-autoloader

# --------------------------------------------
# Stage 2: Final Runtime Image
# --------------------------------------------
FROM base

# Copy configs and startup scripts
COPY setup/php.ini /usr/local/etc/php/php.ini
COPY setup/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY setup/nginx.conf /etc/nginx/nginx.conf
# COPY setup/default.conf /etc/nginx/http.d/default.conf
COPY setup/start.sh /usr/local/bin/start.sh
COPY setup/wait-for-db.sh /usr/local/bin/wait-for-db.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/wait-for-db.sh \
 && mv /usr/local/etc/php-fpm.d/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.disabled || true

# App files (patched and installed)
COPY --from=composer-builder /build /var/www/html

# Optional .env fallback
COPY .env.example /var/www/html/.env.example

# Backup baseline app state to _html_default_ for bind-mounts
RUN mkdir -p /var/www/html_default && \
    cp -a /var/www/html/. /var/www/html_default/ && \
    chown -R www-data:nginx /var/www/html /var/www/html_default

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/start.sh"]
CMD ["nginx", "-g", "daemon off;"]


