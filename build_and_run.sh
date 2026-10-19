#!/bin/bash
# Compila ConvertBRUH, lo empaqueta como .app, lo instala en /Applications y lo ejecuta.
# (El login item y los permisos de macOS funcionan mejor con la app en /Applications.)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "🔨 Compilando ConvertBRUH (release)..."
"$ROOT_DIR/scripts/build-app.sh" --install
