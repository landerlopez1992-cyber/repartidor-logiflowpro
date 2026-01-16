#!/bin/bash
# Script para encontrar el keystore correcto basado en el SHA1 esperado

EXPECTED_SHA1="17:A5:BF:96:A8:50:A8:1F:EA:51:0E:47:21:9E:C2:D2:F7:10:78:54"

echo "🔍 Buscando keystore con SHA1: $EXPECTED_SHA1"
echo ""

# Buscar en ubicaciones comunes
SEARCH_PATHS=(
    "$HOME/Desktop"
    "$HOME/Documents"
    "$HOME/Downloads"
    "$HOME/Android"
    "$HOME/.android"
    "$HOME"
)

for path in "${SEARCH_PATHS[@]}"; do
    if [ -d "$path" ]; then
        echo "Buscando en: $path"
        find "$path" -type f \( -name "*.jks" -o -name "*.keystore" \) 2>/dev/null | while read keystore; do
            echo "  Verificando: $keystore"
            # Intentar obtener SHA1 (puede requerir password)
            SHA1=$(keytool -list -v -keystore "$keystore" -storepass android 2>/dev/null | grep -i "SHA1:" | head -1 | awk '{print $2}')
            if [ "$SHA1" = "$EXPECTED_SHA1" ]; then
                echo ""
                echo "✅ ¡ENCONTRADO! Keystore: $keystore"
                echo "   SHA1: $SHA1"
                exit 0
            fi
        done
    fi
done

echo ""
echo "❌ No se encontró el keystore con el SHA1 esperado"
echo ""
echo "Opciones:"
echo "1. Si tienes el keystore en otra ubicación, ejecuta:"
echo "   keytool -list -v -keystore /ruta/al/keystore.jks"
echo ""
echo "2. Si perdiste el keystore, contacta a Google Play Support"
echo "   o crea una nueva app en Google Play Console"
