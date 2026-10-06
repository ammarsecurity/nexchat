#!/usr/bin/env bash
# Deploy Flutter web build to web.nexchat.site (server-side).
set -e
echo "=== Deploy Flutter web (web.nexchat.site) ==="
mkdir -p /tmp/nexchat-flutter-web
rm -rf /tmp/nexchat-flutter-web/*
cd /tmp/nexchat-flutter-web
unzip -o /tmp/_deploy_nexchat_flutter_web.zip >/dev/null

SITE=/www/wwwroot/web.nexchat.site
mkdir -p "$SITE"
# Backup previous index
cp "$SITE/index.html" "$SITE/index.html.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

# Clear old SPA / previous Flutter assets (keep backups)
rm -rf "$SITE/assets" "$SITE/canvaskit" "$SITE/icons" "$SITE/flutter.js" "$SITE/flutter_bootstrap.js" \
  "$SITE/flutter_service_worker.js" "$SITE/main.dart.js" "$SITE/main.dart.js.map" \
  "$SITE/manifest.json" "$SITE/version.json" "$SITE/favicon.png" "$SITE/favicon.ico" \
  "$SITE/OneSignalSDKWorker.js" 2>/dev/null || true

# Copy full Flutter web build
cp -a /tmp/nexchat-flutter-web/. "$SITE/"
chown -R www:www "$SITE" 2>/dev/null || true
echo "FLUTTER_WEB_DEPLOY_DONE"
ls -la "$SITE/index.html" "$SITE/main.dart.js" 2>/dev/null | head
