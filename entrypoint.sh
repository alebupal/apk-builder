#!/bin/bash
set -euo pipefail

echo "=========================================================="
echo "         COMPILADOR GENÉRICO DE WEB APPS A APK            "
echo "=========================================================="

SRC_DIR="/src-web"
OUT_DIR="/output"
BUILD_DIR="/workspace/build"
KEYSTORE_DIR="/keystore"

# package.json + package-lock.json fijos (carpeta capacitor/ del repo, copiada
# a la imagen): "npm ci" instala exactamente las versiones del lock.
DEPS_DIR="/opt/apk-builder/capacitor"

# Pasa a ASCII y deja solo letras, dígitos, "_" y "-" (nombre del .apk).
slugify() {
    local text
    text=$(printf '%s' "$1" | LC_ALL=C.UTF-8 iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null) || text=$1
    printf '%s' "$text" | tr -cd '[:alnum:]_-'
}

if [ ! -f "$DEPS_DIR/package.json" ] || [ ! -f "$DEPS_DIR/package-lock.json" ]; then
    echo "[-] ERROR: Faltan package.json/package-lock.json en $DEPS_DIR (reconstruye la imagen)."
    exit 1
fi

if [ ! -d "$SRC_DIR" ] || [ ! -f "$SRC_DIR/index.html" ]; then
    echo "[-] ERROR: No se encontró 'index.html' en $SRC_DIR"
    echo "    Asegúrate de montar un directorio web válido con su index.html."
    exit 1
fi

# Detectar o configurar APP_NAME
APP_NAME="${APP_NAME:-}"
if [ -z "$APP_NAME" ]; then
    # Intentar extraer del <title> de index.html
    TITLE_DETECTED=$(grep -iPo '(?<=<title>)(.*?)(?=</title>)' "$SRC_DIR/index.html" 2>/dev/null | head -n 1 | sed 's/^[ \t]*//;s/[ \t]*$//' || true)
    if [ -n "$TITLE_DETECTED" ]; then
        APP_NAME="$TITLE_DETECTED"
    else
        APP_NAME="WebApp"
    fi
fi

# Nombre de archivo seguro (sin caracteres conflictivos para el archivo .apk)
APK_BASENAME=$(slugify "$APP_NAME")
[ -z "$APK_BASENAME" ] && APK_BASENAME="App"

# Detectar o configurar APP_ID (formato com.alebupal.nombre)
APP_ID="${APP_ID:-}"
if [ -z "$APP_ID" ]; then
    CLEAN_ID=$(printf '%s' "$APK_BASENAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    [ -z "$CLEAN_ID" ] && CLEAN_ID="webapp"
    # Cada segmento del Package ID debe empezar por letra.
    [[ "$CLEAN_ID" =~ ^[0-9] ]] && CLEAN_ID="app$CLEAN_ID"
    APP_ID="com.alebupal.$CLEAN_ID"
fi
if [[ ! "$APP_ID" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
    echo "[-] ERROR: Package ID no válido: '$APP_ID'"
    echo "    Debe tener al menos dos segmentos separados por puntos, en minúsculas,"
    echo "    y cada uno empezar por letra (p. ej. com.alebupal.miapp)."
    exit 1
fi

# Versión: X.Y.Z (o X.Y / X). versionCode derivado = X*10000 + Y*100 + Z,
# salvo que se indique APP_VERSION_CODE.
APP_VERSION="${APP_VERSION:-1.0.0}"
if [[ ! "$APP_VERSION" =~ ^([0-9]+)(\.([0-9]+))?(\.([0-9]+))?$ ]]; then
    echo "[-] ERROR: APP_VERSION no válida: '$APP_VERSION' (usa X.Y.Z, p. ej. 1.2.3)"
    exit 1
fi
V_MAJOR=$((10#${BASH_REMATCH[1]}))
V_MINOR=$((10#${BASH_REMATCH[3]:-0}))
V_PATCH=$((10#${BASH_REMATCH[5]:-0}))
APP_VERSION="$V_MAJOR.$V_MINOR.$V_PATCH"
APP_VERSION_CODE="${APP_VERSION_CODE:-}"
if [ -z "$APP_VERSION_CODE" ]; then
    if [ "$V_MINOR" -gt 99 ] || [ "$V_PATCH" -gt 99 ]; then
        echo "[-] ERROR: Con APP_VERSION=$APP_VERSION no se puede derivar versionCode (Y y Z deben ser < 100)."
        echo "    Indica APP_VERSION_CODE explícitamente."
        exit 1
    fi
    APP_VERSION_CODE=$((V_MAJOR * 10000 + V_MINOR * 100 + V_PATCH))
fi
if [[ ! "$APP_VERSION_CODE" =~ ^[1-9][0-9]{0,9}$ ]] || [ "$APP_VERSION_CODE" -gt 2100000000 ]; then
    echo "[-] ERROR: versionCode no válido: '$APP_VERSION_CODE' (entero entre 1 y 2100000000)."
    exit 1
fi

# Firma: release si hay keystore montada en $KEYSTORE_DIR; si no, debug (con la
# debug.keystore del volumen persistente ~/.android).
KEY_ALIAS="${KEY_ALIAS:-release}"
if [ -f "$KEYSTORE_DIR/keystore.jks" ] && [ -f "$KEYSTORE_DIR/password" ]; then
    BUILD_TYPE="release"
    KEY_PASSWORD_FILE="$KEYSTORE_DIR/password"
    [ -f "$KEYSTORE_DIR/key-password" ] && KEY_PASSWORD_FILE="$KEYSTORE_DIR/key-password"
else
    BUILD_TYPE="debug"
fi

echo "[*] Configuración de la aplicación:"
echo "    - Nombre:    $APP_NAME"
echo "    - Package:   $APP_ID"
echo "    - Versión:   $APP_VERSION (versionCode $APP_VERSION_CODE)"
echo "    - Firma:     $BUILD_TYPE"
echo "    - Archivo:   ${APK_BASENAME}.apk"

echo "[*] Limpiando espacio de trabajo temporal..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/www"

echo "[*] Copiando recursos web..."
cp -r "$SRC_DIR"/* "$BUILD_DIR/www/"

cd "$BUILD_DIR"

echo "[*] Preparando dependencias y configuración de Capacitor..."
cp "$DEPS_DIR/package.json" "$DEPS_DIR/package-lock.json" .
# capacitor.config.json sí es dinámico (nombre e ID). Se genera con Node para
# que el nombre de la app se escape correctamente.
node -e '
const fs = require("fs");
const [appName, appId] = process.argv.slice(1);
fs.writeFileSync("capacitor.config.json", JSON.stringify({
  appId: appId,
  appName: appName,
  webDir: "www",
  backgroundColor: "#0b0f19",
  server: { androidScheme: "https" },
  android: { captureInput: true, webContentsDebuggingEnabled: false }
}, null, 2) + "\n");
' "$APP_NAME" "$APP_ID"

# 1. Optimizar viewport y estilos nativos en index.html
if [ -f "$BUILD_DIR/www/index.html" ]; then
    echo "[*] Optimizando HTML para experiencia nativa Android..."
    # Viewport con safe-area y sin zoom accidental
    sed -i 's/<meta name="viewport"[^>]*>/<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">/g' "$BUILD_DIR/www/index.html"

    # Inyectar estilos nativos (sin rebote elástico, soporte notch/safe-area, sin destello de toque)
    NATIVE_CSS=$(mktemp)
    cat << 'STYLES' > "$NATIVE_CSS"
<style id="android-native-tune">
  html, body {
    overscroll-behavior-y: none;
    -webkit-tap-highlight-color: transparent;
  }
  body {
    padding-top: env(safe-area-inset-top, 0px);
    padding-bottom: env(safe-area-inset-bottom, 0px);
    padding-left: env(safe-area-inset-left, 0px);
    padding-right: env(safe-area-inset-right, 0px);
  }
  button, a, input, select {
    touch-action: manipulation;
  }
</style>
STYLES
    sed -i "/<\/head>/e cat $NATIVE_CSS" "$BUILD_DIR/www/index.html"
    rm -f "$NATIVE_CSS"
fi

echo "[*] Instalando dependencias de Capacitor (npm ci, versiones del lock)..."
# La caché npm (npm_config_cache) es el volumen npm-cache: tras la primera vez
# los paquetes salen de ahí. npm ci falla si package.json y el lock no cuadran.
npm ci --prefer-offline --no-audit --no-fund --loglevel=error

echo "[*] Creando proyecto nativo Android..."
npx cap add android

# Personalización nativa de la barra de estado y navegación en styles.xml.
# Solo en un estilo: el de la actividad (AppTheme.NoActionBar) o, si no existe,
# el primero; antes se añadía a todos los </style>.
STYLES_XML="android/app/src/main/res/values/styles.xml"
if [ -f "$STYLES_XML" ]; then
    BAR_ITEMS='    <item name="android:statusBarColor">#0b0f19<\/item>\n        <item name="android:navigationBarColor">#0b0f19<\/item>\n        <item name="android:windowLightStatusBar">false<\/item>\n    <\/style>'
    if grep -q '<style name="AppTheme\.NoActionBar"' "$STYLES_XML"; then
        sed -i '/<style name="AppTheme\.NoActionBar"/,/<\/style>/ s/<\/style>/'"$BAR_ITEMS"'/' "$STYLES_XML"
    else
        sed -i '0,/<\/style>/ s/<\/style>/'"$BAR_ITEMS"'/' "$STYLES_XML"
    fi
fi

# Ajustar teclado suave para que no deforme la pantalla. La plantilla de
# Capacitor 6 no trae windowSoftInputMode: si no existe, se añade a MainActivity.
MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ -f "$MANIFEST" ]; then
    if grep -q 'android:windowSoftInputMode=' "$MANIFEST"; then
        sed -i 's/android:windowSoftInputMode="[^"]*"/android:windowSoftInputMode="adjustResize"/g' "$MANIFEST"
    else
        sed -i 's/^\([[:space:]]*\)android:name="\.MainActivity"/&\n\1android:windowSoftInputMode="adjustResize"/' "$MANIFEST"
    fi
    grep -q 'android:windowSoftInputMode="adjustResize"' "$MANIFEST" \
        || echo "[!] Aviso: no se pudo fijar windowSoftInputMode en $MANIFEST"
fi

# Si el usuario incluyó icon.png o favicon.png, copiarlo a los mipmaps
ICON_SRC=""
if [ -f "$BUILD_DIR/www/icon.png" ]; then
    ICON_SRC="$BUILD_DIR/www/icon.png"
elif [ -f "$BUILD_DIR/www/favicon.png" ]; then
    ICON_SRC="$BUILD_DIR/www/favicon.png"
fi

if [ -n "$ICON_SRC" ]; then
    echo "[*] Icono personalizado detectado, aplicando a recursos de Android..."
    for mipmap_dir in android/app/src/main/res/mipmap-*; do
        if [ -d "$mipmap_dir" ]; then
            # En mipmap-anydpi-v26 van los XMLs adaptativos; omitir para evitar colisión de nombres
            if [[ "$mipmap_dir" == *"anydpi"* ]]; then
                continue
            fi
            cp "$ICON_SRC" "$mipmap_dir/ic_launcher.png" 2>/dev/null || true
            cp "$ICON_SRC" "$mipmap_dir/ic_launcher_round.png" 2>/dev/null || true
            cp "$ICON_SRC" "$mipmap_dir/ic_launcher_foreground.png" 2>/dev/null || true
        fi
    done

    # Ajustar color de fondo del adaptive icon al color oscuro del tema
    # (Capacitor 6 lo define en values/ic_launcher_background.xml; antes, colors.xml).
    for colors_xml in android/app/src/main/res/values/ic_launcher_background.xml \
                      android/app/src/main/res/values/colors.xml; do
        [ -f "$colors_xml" ] || continue
        sed -i 's/<color name="ic_launcher_background">.*<\/color>/<color name="ic_launcher_background">#0b0f19<\/color>/g' "$colors_xml"
    done
fi

# Versión y firma: se añade un bloque android {} al final de app/build.gradle,
# que prevalece sobre los valores de la plantilla (versionCode 1 / "1.0").
# Las contraseñas se leen de los ficheros montados en solo lectura al compilar:
# no pasan por variables de entorno, argumentos ni la salida del script.
APP_GRADLE="android/app/build.gradle"
if [ ! -f "$APP_GRADLE" ]; then
    echo "[-] ERROR: No se encontró $APP_GRADLE en el proyecto generado por Capacitor."
    exit 1
fi
{
    echo ""
    echo "// Añadido por apk-builder"
    echo "android {"
    echo "    defaultConfig {"
    echo "        versionCode $APP_VERSION_CODE"
    echo "        versionName \"$APP_VERSION\""
    echo "    }"
    if [ "$BUILD_TYPE" = "release" ]; then
        echo "    signingConfigs {"
        echo "        apkBuilderRelease {"
        echo "            storeFile file(\"$KEYSTORE_DIR/keystore.jks\")"
        echo "            storePassword new File(\"$KEYSTORE_DIR/password\").text.trim()"
        echo "            keyAlias System.getenv(\"KEY_ALIAS\") ?: \"release\""
        echo "            keyPassword new File(\"$KEY_PASSWORD_FILE\").text.trim()"
        echo "        }"
        echo "    }"
        echo "    buildTypes {"
        echo "        release {"
        echo "            signingConfig signingConfigs.apkBuilderRelease"
        echo "        }"
        echo "    }"
    fi
    echo "}"
} >> "$APP_GRADLE"
export KEY_ALIAS

echo "[*] Compilando APK ($BUILD_TYPE) con Gradle..."
cd android
chmod +x gradlew
if [ "$BUILD_TYPE" = "release" ]; then
    ./gradlew assembleRelease --no-daemon
    APK_GENERADO="app/build/outputs/apk/release/app-release.apk"
else
    ./gradlew assembleDebug --no-daemon
    APK_GENERADO="app/build/outputs/apk/debug/app-debug.apk"
fi

if [ -f "$APK_GENERADO" ]; then
    mkdir -p "$OUT_DIR"
    FINAL_NAME="${APK_BASENAME}.apk"
    # Se borra antes por si existe uno antiguo de otro propietario (antes se
    # compilaba como root): así el nuevo pertenece al usuario y queda en 644.
    rm -f "$OUT_DIR/$FINAL_NAME"
    cp "$APK_GENERADO" "$OUT_DIR/$FINAL_NAME"
    chmod 644 "$OUT_DIR/$FINAL_NAME"

    TAMANO=$(du -h "$OUT_DIR/$FINAL_NAME" | cut -f1)

    echo ""
    echo "=========================================================="
    echo "         ¡APK GENERADO CON ÉXITO!                         "
    echo "=========================================================="
    echo " Archivo final: $OUT_DIR/$FINAL_NAME"
    echo " Tamaño:        $TAMANO"
    echo " Nombre App:    $APP_NAME"
    echo " ID Paquete:    $APP_ID"
    echo " Versión:       $APP_VERSION (versionCode $APP_VERSION_CODE)"
    echo " Firma:         $BUILD_TYPE"
    echo " Modo:          100% Offline (Standalone)"
    echo "=========================================================="
    echo ""
else
    echo "[-] ERROR: La compilación de Gradle finalizó sin generar el archivo APK."
    exit 1
fi
