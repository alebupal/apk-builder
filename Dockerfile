# Imágenes base fijadas por digest (índice multiarquitectura) para que la
# compilación sea reproducible. Digests consultados en Docker Hub el 2026-11-10.
# Para actualizarlos:
#   docker buildx imagetools inspect eclipse-temurin:17-jdk-jammy   (línea "Digest:")
#   docker buildx imagetools inspect node:24.22.2-bookworm-slim
# Se pueden sobrescribir con --build-arg BASE_IMAGE=... / NODE_IMAGE=...
ARG BASE_IMAGE=eclipse-temurin:17-jdk-jammy@sha256:057a0daec60e87c96571bf5c9c7792065bcb19e804d584cd37d4144038a35717
ARG NODE_IMAGE=node:24.22.2-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9

# Node.js 24 LTS ("Krypton", soporte hasta 2028-04-30) sale de la imagen oficial
# (en lugar de "curl | bash" de NodeSource). Node 20 terminó su soporte el
# 2026-04-30 y Node 22 lo termina el 2027-04-30. El binario copiado pide como
# máximo GLIBC_2.28 y GLIBCXX_3.4.21 (objdump -T); jammy trae glibc 2.35 y
# GLIBCXX_3.4.30, así que funciona aunque la imagen de Node sea bookworm.
FROM ${NODE_IMAGE} AS node

FROM ${BASE_IMAGE}

# Evitar prompts interactivos
ENV DEBIAN_FRONTEND=noninteractive

# Variables de entorno para Android SDK
# El SHA-256 corresponde a commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip
# (comprobado contra el SHA-1 del manifiesto oficial
# https://dl.google.com/android/repository/repository2-3.xml). Si cambias la
# versión, actualiza también el hash (developer.android.com/studio lo publica
# para la versión vigente).
ARG ANDROID_SDK_VERSION=11076708
ARG ANDROID_SDK_SHA256=2d2d50857e4eb553af5a6dc3ad507a17adf43d115264b1afc116f95c92e5e258
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/build-tools/34.0.0

# Usuario sin privilegios que ejecuta la compilación (mismo UID/GID que el
# usuario del host, para que el APK y las cachés le pertenezcan).
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
ENV HOME=/home/builder \
    GRADLE_USER_HOME=/home/builder/.gradle \
    ANDROID_USER_HOME=/home/builder/.android \
    npm_config_cache=/home/builder/.npm

# Instalar dependencias base (libstdc++6 lo necesita el binario de Node)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    git \
    ca-certificates \
    libstdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24 + npm desde la imagen oficial
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node --version && npm --version

# Instalar Android SDK Command-line Tools (con verificación SHA-256)
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools /tmp/sdk \
    && curl -fsSL --proto '=https' -o /tmp/sdk/cmdline-tools.zip \
       "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_VERSION}_latest.zip" \
    && echo "${ANDROID_SDK_SHA256}  /tmp/sdk/cmdline-tools.zip" | sha256sum -c - \
    && unzip -q /tmp/sdk/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools \
    && mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest \
    && rm -rf /tmp/sdk

# Aceptar licencias e instalar componentes esenciales de Android (API 34).
# Sin "|| true": si sdkmanager falla (red, licencias), la construcción falla.
# (/bin/sh no usa pipefail, así que el SIGPIPE de "yes" no cuenta como error.)
RUN yes | sdkmanager --licenses > /dev/null \
    && sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" > /dev/null \
    && chmod -R a+rX ${ANDROID_HOME}

# Usuario de compilación con HOME y cachés escribibles. Los volúmenes con nombre
# de docker-compose se inicializan con este propietario la primera vez.
RUN groupadd -o -g "${BUILDER_GID}" builder \
    && useradd -o -m -d /home/builder -u "${BUILDER_UID}" -g "${BUILDER_GID}" -s /bin/bash builder \
    && mkdir -p /home/builder/.gradle /home/builder/.android /home/builder/.npm /workspace \
    && chown -R "${BUILDER_UID}:${BUILDER_GID}" /home/builder /workspace

WORKDIR /workspace

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh

# Dependencias de Capacitor fijadas: entrypoint.sh copia estos dos ficheros al
# espacio de trabajo y ejecuta "npm ci" (ver README para actualizar el lock).
# (Sin --chmod: aplicaría también a los directorios creados y los dejaría sin
# permiso de acceso para el usuario builder.)
COPY capacitor/package.json capacitor/package-lock.json /opt/apk-builder/capacitor/

USER builder

ENTRYPOINT ["/bin/bash", "/usr/local/bin/entrypoint.sh"]
