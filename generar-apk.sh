#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colores para salida estética
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}=========================================================="
echo -e "${BOLD}       GENERADOR UNIVERSAL DE APKs DESDE WEB HTML         "
echo -e "${CYAN}==========================================================${NC}"

# Comprobar que Docker está instalado
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[-] Error: Docker no está instalado en este sistema.${NC}"
    exit 1
fi

INPUT_DIR="${1:-}"
INPUT_NAME="${2:-}"
INPUT_ID="${3:-}"
INPUT_VERSION="${4:-${APP_VERSION:-}}"

# Ruta del proyecto web: sin valor por defecto. Si no se pasa como argumento, se pregunta
# (hasta que sea una carpeta válida con index.html).
resolver_dir() {  # resolver_dir ruta -> imprime la ruta absoluta o falla
    local d="$1"
    d="${d/#\~/$HOME}"
    if [ -d "$d" ]; then
        readlink -f "$d"
    elif [ -d "$SCRIPT_DIR/$d" ]; then
        readlink -f "$SCRIPT_DIR/$d"
    else
        return 1
    fi
}

TARGET_DIR=""
while [ -z "$TARGET_DIR" ]; do
    if [ -z "$INPUT_DIR" ]; then
        if [ ! -t 0 ]; then
            echo -e "${RED}[-] ERROR: indica la carpeta del proyecto web como primer argumento.${NC}"
            echo -e "    Uso: $0 <carpeta-web> [nombre] [package-id] [versión]"
            exit 1
        fi
        echo -e "${YELLOW}Introduce la ruta de la carpeta que contiene tu proyecto web (HTML/CSS/JS):${NC}"
        read -r -e -p "Ruta: " INPUT_DIR
        [ -n "$INPUT_DIR" ] || { echo -e "${RED}[-] La ruta es obligatoria.${NC}"; continue; }
    fi

    if ! TARGET_DIR="$(resolver_dir "$INPUT_DIR")"; then
        echo -e "\n${RED}[-] ERROR: El directorio especificado no existe: $INPUT_DIR${NC}"
        TARGET_DIR=""
    elif [ ! -f "$TARGET_DIR/index.html" ]; then
        echo -e "\n${RED}[-] ERROR: No se encontró 'index.html' en: $TARGET_DIR${NC}"
        echo -e "    El directorio debe contener al menos un archivo index.html."
        TARGET_DIR=""
    fi

    if [ -z "$TARGET_DIR" ]; then
        # Con la ruta pasada por argumento (o sin terminal) no se insiste: se sale con error.
        if [ -n "${1:-}" ] || [ ! -t 0 ]; then exit 1; fi
        INPUT_DIR=""
    fi
done

# Nombre, Package ID y versión: si se dejan vacíos, entrypoint.sh los deduce
# (título de index.html, com.alebupal.<nombre> y 1.0.0). La detección está solo allí.
if [ -t 0 ]; then
    if [ -z "$INPUT_NAME" ]; then
        echo -e "\n${YELLOW}Nombre para la aplicación Android:${NC}"
        read -r -p "Nombre [automático: <title> de index.html]: " INPUT_NAME
    fi
    if [ -z "$INPUT_ID" ]; then
        echo -e "\n${YELLOW}Identificador de paquete Android (Package ID):${NC}"
        read -r -p "Package ID [automático: com.alebupal.<nombre>]: " INPUT_ID
    fi
    if [ -z "$INPUT_VERSION" ]; then
        echo -e "\n${YELLOW}Versión de la aplicación (X.Y.Z):${NC}"
        read -r -p "Versión [1.0.0]: " INPUT_VERSION
    fi
fi

mkdir -p "$SCRIPT_DIR/output" "${KEYSTORE_DIR:-$SCRIPT_DIR/keystore}"

echo ""
echo -e "${CYAN}----------------------------------------------------------${NC}"
echo -e "${BOLD}Resumen de compilación:${NC}"
echo -e " 📁 Origen web:   ${GREEN}$TARGET_DIR${NC}"
echo -e " 📱 Nombre App:   ${GREEN}${INPUT_NAME:-(automático)}${NC}"
echo -e " 🏷️  Package ID:   ${GREEN}${INPUT_ID:-(automático)}${NC}"
echo -e " 🔢 Versión:      ${GREEN}${INPUT_VERSION:-1.0.0}${NC}"
echo -e " 📦 Destino APK:  ${GREEN}$SCRIPT_DIR/output/${NC}"
echo -e "${CYAN}----------------------------------------------------------${NC}"
echo ""

# Asegurar permisos de ejecución del script de entrada
chmod +x "$SCRIPT_DIR/entrypoint.sh" 2>/dev/null || true

# El contenedor corre con el UID/GID del usuario (no root): el APK y las cachés
# le pertenecen. (UID es de solo lectura en bash, por eso HOST_UID/HOST_GID.)
export HOST_UID HOST_GID WEB_DIR
WEB_DIR="$TARGET_DIR"   # obligatorio en docker-compose.yml (también para el build)
HOST_UID="$(id -u)"
HOST_GID="$(id -g)"

# 1. Construir/actualizar la imagen siempre: con la caché de Docker es casi
# instantáneo si nada cambió, y así no se queda una imagen obsoleta.
echo -e "${YELLOW}[*] Preparando imagen de compilación Docker...${NC}"
docker compose build

# 2. Ejecutar compilación pasando las variables
echo -e "${YELLOW}[*] Lanzando contenedor para empaquetar y compilar...${NC}"
APP_NAME="$INPUT_NAME" \
APP_ID="$INPUT_ID" \
APP_VERSION="${INPUT_VERSION:-1.0.0}" \
OUTPUT_DIR="$SCRIPT_DIR/output" \
docker compose run --rm apk-builder

echo -e "\n${GREEN}[✓] Proceso finalizado. Revisa la carpeta '$SCRIPT_DIR/output/' para obtener tu APK.${NC}\n"
