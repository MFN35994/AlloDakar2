#!/bin/bash

# Configuration
PROJECT_ID="allo-dakar-b6a20"
APP_ID="1:743590908369:android:cd3fd414ced552195cd0f0"
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
RELEASE_NOTES="Allô Dakar v1.0.0 - Préparation au lancement. Support parrainage et badges vérifiés."

echo "🚀 Début de la distribution sur Firebase App Distribution..."

# Vérification du fichier APK
if [ ! -f "$APK_PATH" ]; then
    echo "❌ Erreur: Le fichier APK est introuvable à l'adresse $APK_PATH"
    echo "Assurez-vous d'avoir lancé 'flutter build apk --release' d'abord."
    exit 1
fi

# Distribution
firebase appdistribution:distribute "$APK_PATH" \
    --app "$APP_ID" \
    --release-notes "$RELEASE_NOTES" \
    --groups "testers-allô-dakar" \
    --project "$PROJECT_ID"

if [ $? -eq 0 ]; then
    echo "✅ Succès ! L'application est maintenant disponible pour les testeurs."
else
    echo "❌ Échec de la distribution. Vérifiez votre connexion et les permissions Firebase."
    exit 1
fi
