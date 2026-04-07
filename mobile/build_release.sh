#!/bin/bash
# Build release APK avec l'URL API de production
# Usage: ./build_release.sh
#        ./build_release.sh "https://votre-backend.up.railway.app/api"

API_URL="${1:-https://backend-production-195ed.up.railway.app/api}"

echo "========================================"
echo "  E-School Mobile - Build Release APK"
echo "========================================"
echo "API URL: $API_URL"
echo ""

flutter pub get
# Après modification d'assets (ex. logo.png), si l'ancienne image reste dans l'APK : décommenter la ligne suivante
# flutter clean
flutter build apk --release --dart-define=API_BASE_URL="$API_URL"

echo ""
echo "APK genere: build/app/outputs/flutter-apk/app-release.apk"
