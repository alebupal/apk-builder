# 📱 Generador Universal de APKs para Aplicaciones Web (Docker)

Herramienta genérica y aislada basada en Docker para convertir **cualquier proyecto web HTML/CSS/JS** en una aplicación nativa instalable de Android (`.apk`), sin necesidad de instalar Android Studio, Java ni SDKs en tu servidor o PC.

Funciona de forma **100% offline (standalone)** empaquetando todo el código frontend dentro del APK nativo mediante Capacitor y Gradle.

---

## 📁 Estructura del proyecto

```text
apk-builder/
├── Dockerfile           # Imagen con OpenJDK 17, Node.js 20 (imagen oficial), Android SDK Tools (SHA-256 verificado)
├── docker-compose.yml   # Orquestador: usuario no root, volúmenes de caché Gradle/npm y de ~/.android
├── entrypoint.sh        # Generador de estructura Capacitor, integración de icono y Gradle
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

Las versiones de Capacitor están fijadas (sin `^`) en `entrypoint.sh` (`CAPACITOR_VERSION`), y las imágenes base y el zip de Android cmdline-tools, por digest/SHA-256 en el `Dockerfile`.

---

## 🎨 Icono personalizado de la App (Opcional)

Si dentro de la carpeta web que compilas existe un archivo `icon.png` o `favicon.png`, el compilador lo detectará y lo aplicará automáticamente como el icono de launcher de Android para tu aplicación.

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
