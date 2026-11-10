# 📱 Generador Universal de APKs para Aplicaciones Web (Docker)

Herramienta genérica y aislada basada en Docker para convertir **cualquier proyecto web HTML/CSS/JS** en una aplicación nativa instalable de Android (`.apk`), sin necesidad de instalar Android Studio, Java ni SDKs en tu servidor o PC.

Funciona de forma **100% offline (standalone)** empaquetando todo el código frontend dentro del APK nativo mediante Capacitor y Gradle.

---

## 📁 Estructura del proyecto

```text
apk-builder/
├── Dockerfile           # Imagen con JDK 17 (Temurin), Node.js 24 LTS (imagen oficial), Android SDK Tools (SHA-256 verificado)
├── docker-compose.yml   # Orquestador: usuario no root, volúmenes de caché Gradle/npm y de ~/.android
├── entrypoint.sh        # Generador de estructura Capacitor, integración de icono y Gradle
├── capacitor/           # package.json + package-lock.json fijos de Capacitor (se instalan con npm ci)
├── .dockerignore        # Deja fuera del contexto de build output/, keystore/ y .git
├── generar-apk.sh       # Script principal (interactivo o por línea de comandos)
├── README.md            # Documentación y ejemplos
├── keystore/            # (Opcional) keystore de release, montada en solo lectura
└── output/              # Directorio donde se guardan los archivos .apk compilados
```

---

## 🚀 Modos de Uso

Entra en la carpeta del proyecto:
```bash
cd apk-builder
```

### 1. Modo Interactivo (Asistente paso a paso)
Simplemente ejecuta:
```bash
./generar-apk.sh
```
El script te preguntará:
1. **Ruta del proyecto web (obligatoria, sin valor por defecto):** pega la ruta a tu proyecto HTML/CSS/JS (se admite `~`). Se vuelve a preguntar hasta que sea una carpeta con `index.html`. Sin terminal hay que pasarla como primer argumento. Si usas `docker compose` directamente, exporta `WEB_DIR=/ruta/a/la/web`.
2. **Nombre de la App:** Detecta automáticamente el `<title>` de tu `index.html` o puedes escribir el que quieras.
3. **Package ID:** Si lo dejas vacío se genera uno válido como `com.alebupal.nombre`; si lo escribes, debe cumplir `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`.
4. **Versión:** `X.Y.Z` (por defecto `1.0.0`).

La detección automática del nombre y del Package ID se hace dentro del contenedor (`entrypoint.sh`).

---

### 2. Modo Directo por Línea de Comandos
Puedes pasar los parámetros directamente:

```bash
# Sintaxis:
./generar-apk.sh <ruta_al_proyecto_web> [nombre_app] [package_id] [version]

# Ejemplo 1: Compilar un proyecto web indicando solo su ruta
./generar-apk.sh /ruta/a/mi-proyecto-web

# Ejemplo 2: Especificando nombre personalizado
./generar-apk.sh /ruta/a/mi-proyecto-web "Mi App"

# Ejemplo 3: Especificando nombre y Package ID
./generar-apk.sh /ruta/a/mi-otra-web "Mi Nueva App" "com.alebupal.minuevaapp"

# Ejemplo 4: Con versión (versionCode derivado: 1.2.3 -> 10203)
./generar-apk.sh /ruta/a/mi-otra-web "Mi Nueva App" "com.alebupal.minuevaapp" 1.2.3
```

La imagen se reconstruye en cada ejecución (`docker compose build`); gracias a la caché de Docker solo tarda si algo cambió.

---

## 🔢 Versión de la App

`APP_VERSION` (`X.Y.Z`, cuarto argumento o variable de entorno) se usa como `versionName`, y el `versionCode` se deriva como `X*10000 + Y*100 + Z` (`Y` y `Z` deben ser menores que 100). Para fijarlo a mano exporta `APP_VERSION_CODE`. Para que Android acepte una actualización encima de la app instalada, el `versionCode` debe crecer y la firma debe ser la misma.

---

## 🔐 Firma del APK

- **Debug (por defecto):** se compila con `assembleDebug` y se firma con la `debug.keystore` que Gradle crea en `~/.android`. Ese directorio es el volumen persistente `android-home`, así que la clave se conserva entre compilaciones y las nuevas versiones se pueden instalar encima de las anteriores. Si borras el volumen (`docker volume rm`), la clave cambia y habrá que desinstalar la app antes de instalar la nueva.
- **Release (opcional):** pon en `keystore/` (o en el directorio de `KEYSTORE_DIR`) estos ficheros; se montan en solo lectura en `/keystore`:
  - `keystore.jks`: el almacén de claves.
  - `password`: la contraseña del almacén (y de la clave, salvo que exista `key-password`).
  - `key-password` (opcional): contraseña de la clave si es distinta.

  El alias de la clave se indica con `KEY_ALIAS` (por defecto `release`). Si están `keystore.jks` y `password`, se compila con `assembleRelease`. Las contraseñas las lee Gradle directamente de esos ficheros: no pasan por `ARG`, variables de entorno ni la salida del script. Protégelos con `chmod 600` (el contenedor corre con tu mismo UID, así que puede leerlos).

---

## 👤 Usuario del contenedor

El contenedor no corre como root: usa tu UID/GID (`generar-apk.sh` exporta `HOST_UID`/`HOST_GID`; si usas `docker compose` directamente, expórtalos tú o se usará `1000:1000`). El APK queda a tu nombre con permisos `644`. Las cachés de Gradle y npm van en los volúmenes `gradle-cache-builder` y `npm-cache`. El volumen antiguo `gradle-cache` (creado como root) ya no se usa y se puede borrar.

---

## 📌 Versiones fijadas y dependencias reproducibles

| Componente | Versión | Dónde |
|---|---|---|
| JDK | Temurin 17 (Ubuntu 22.04 jammy), por digest | `Dockerfile` (`BASE_IMAGE`) |
| Node.js | 24.22.2 LTS "Krypton" (soporte hasta 2028-04-30), por digest | `Dockerfile` (`NODE_IMAGE`) |
| Android cmdline-tools | 11076708, SHA-256 verificado | `Dockerfile` |
| Android SDK | platform 34, build-tools 34.0.0 | `Dockerfile` |
| Capacitor (`core`, `android`, `cli`) | 6.2.3 + dependencias transitivas | `capacitor/package-lock.json` |
| Gradle / AGP | 8.2.1 / 8.2.1 (los trae la plantilla de Capacitor 6) | — |

**Por qué Node 24:** Node 20 terminó su soporte el 2026-04-30 y Node 22 lo termina el 2027-04-30. Node 24 está en LTS de mantenimiento hasta 2028-04-30. Node 26 es la LTS activa desde el 2026-10-28, pero es muy reciente y Capacitor 6 se publicó mucho antes; Node 24 da soporte largo con riesgo bajo. Capacitor 6 solo exige `node >= 18` y Node no interviene en la compilación Android (Gradle/AGP usan el JDK 17).

**Dependencias de Capacitor:** `entrypoint.sh` ya no genera `package.json`: copia `capacitor/package.json` y `capacitor/package-lock.json` (incluidos en la imagen, en `/opt/apk-builder/capacitor`) al espacio de trabajo y ejecuta `npm ci`, que instala exactamente lo que dice el lock (con integridad SHA-512) usando la caché del volumen `npm-cache`. `capacitor.config.json` sigue generándose en cada compilación con el nombre y el Package ID de la app.

**Actualizar el lock** (p. ej. para subir Capacitor):

1. Cambia las versiones exactas (sin `^`) en `capacitor/package.json`. Las tres (`@capacitor/core`, `@capacitor/android`, `@capacitor/cli`) deben ir a la par. Versiones publicadas: `npm view @capacitor/cli versions`.
2. Regenera el lock con la misma imagen de Node que usa el `Dockerfile` (así el formato es el mismo, `lockfileVersion` 3):
   ```bash
   docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/.npm \
     -v "$PWD/capacitor:/w" -w /w \
     node:24.22.2-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9 \
     npm install --package-lock-only --no-audit --no-fund
   ```
3. Compila una app de prueba (`./generar-apk.sh`) y versiona los dos ficheros juntos. Si `package.json` y el lock no cuadran, `npm ci` falla en vez de resolver otras versiones.

Ojo: una versión mayor de Capacitor cambia la plantilla Android (AGP, Gradle, `compileSdk`, JDK requerido), así que puede hacer falta tocar el `Dockerfile` (`platforms;android-XX`, `build-tools`, imagen del JDK).

Para actualizar los digests de las imágenes base: `docker buildx imagetools inspect <imagen:tag>` (línea `Digest:`).

---

## 🎨 Icono personalizado de la App (Opcional)

Si dentro de la carpeta web que compilas existe un archivo `icon.png` o `favicon.png`, el compilador lo detectará y lo aplicará automáticamente como el icono de launcher de Android para tu aplicación (y el fondo del icono adaptativo pasa al color oscuro del tema, `#0b0f19`).

Además, en cada compilación se ajusta el proyecto nativo: barras de estado y navegación `#0b0f19` en el tema `AppTheme.NoActionBar`, `windowSoftInputMode="adjustResize"` en `MainActivity`, y en `index.html` el viewport (sin zoom, `viewport-fit=cover`) y unos estilos de safe-area.

---

## 📥 Obtener el APK generado

Todos los APKs se guardan en:
```text
apk-builder/output/<NombreDeLaApp>.apk
```

Para instalarlo en tu móvil:
1. Envía el `.apk` a tu teléfono (vía PairDrop, FileBrowser, Telegram o cable).
2. Toca el archivo en Android y pulsa **Instalar**.
3. ¡Listo! La app se ejecutará de forma independiente, a pantalla completa y sin depender de conexión a internet.
