#!/bin/bash
# MotoGo24 Web PHP — lokální dev server
# Použití: ./start.sh [port]

PORT="${1:-8000}"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🏍️  MotoGo24 Web PHP"
echo "📂  $DIR"
echo "🌐  http://localhost:$PORT"
echo "    Ctrl+C pro zastavení"
echo ""

cd "$DIR" && php -S localhost:$PORT
