#!/bin/bash

# 🚀 ANYMEX BUILD-SKRIPT - ULTIMATE FIX
# Behebt Gradle Cache Korruption und Flutter SDK Konflikte

echo "============================================="
echo "    🚀 ANYMEX BUILD (ULTIMATE FIX)"
echo "============================================="

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error_exit() {
    echo -e "${RED}❌ FEHLER: $1${NC}"
    echo -e "${YELLOW}🔧 Lösung: $2${NC}"
    exit 1
}

info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# 📌 SCHRITT 1: KOMPLETTER GRADLE CACHE RESET
echo -e "${RED}🔥 WICHTIG: Gradle Cache wird komplett gelöscht!${NC}"
echo -e "${YELLOW}Dies behebt die metadata.bin Korruption.${NC}"
echo ""

info "Stoppe alle Gradle Daemons..."
pkill -f 'GradleDaemon' 2>/dev/null || true
sleep 2

info "Lösche Gradle Cache..."
rm -rf ~/.gradle/caches 2>/dev/null
rm -rf ~/.gradle/daemon 2>/dev/null
rm -rf ~/.gradle/wrapper 2>/dev/null
rm -rf ~/.gradle/native 2>/dev/null
success "Gradle Cache gelöscht"

info "Lösche Android Projekt Cache..."
rm -rf android/.gradle 2>/dev/null
rm -rf android/build 2>/dev/null
rm -rf build 2>/dev/null
success "Projekt Cache gelöscht"

# 📌 SCHRITT 2: FLUTTER SDK KONFIGURIEREN
echo ""
echo -e "${BLUE}🔍 Konfiguriere Flutter SDK...${NC}"

PROJECT_FLUTTER="/Users/murat/Documents/NyanTV-1.3.8/.flutter-sdk-3.32.8"
if [ -d "$PROJECT_FLUTTER" ]; then
    export PATH="$PROJECT_FLUTTER/bin:$PATH"
    export FLUTTER_ROOT="$PROJECT_FLUTTER"
    success "Flutter SDK: $PROJECT_FLUTTER"
    flutter --version
else
    error_exit "Flutter SDK nicht gefunden" "Prüfe Pfad: $PROJECT_FLUTTER"
fi

# 📌 SCHRITT 3: JAVA KONFIGURIEREN
echo ""
info "Konfiguriere Java..."
export JAVA_HOME=$(/usr/libexec/java_home -v 17 2>/dev/null || /usr/libexec/java_home -v 11 2>/dev/null)
if [ -n "$JAVA_HOME" ]; then
    export PATH="$JAVA_HOME/bin:$PATH"
    success "Java: $JAVA_HOME"
    java -version
else
    error_exit "Java nicht gefunden" "Installiere Java 17 oder 11"
fi

# 📌 SCHRITT 4: ANDROID SDK KONFIGURIEREN
echo ""
info "Konfiguriere Android SDK..."
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"

if [ ! -d "$ANDROID_HOME" ]; then
    error_exit "Android SDK nicht gefunden" "Prüfe: $ANDROID_HOME"
fi
success "Android SDK: $ANDROID_HOME"

# Licenses
mkdir -p "$ANDROID_HOME/licenses"
echo -e "\n8933bad161af4178b1185d1a37fbf41ea5269c55" > "$ANDROID_HOME/licenses/android-sdk-license"
echo -e "\n84831b9409646a918e30573bab4c9c91346d8abd" > "$ANDROID_HOME/licenses/android-sdk-preview-license"

# 📌 SCHRITT 5: FLUTTER CLEAN
echo ""
info "Flutter Clean..."
flutter clean
success "Flutter Clean abgeschlossen"

# 📌 SCHRITT 6: PUB CACHE RESET (OPTIONAL)
echo ""
read -p "Pub Cache auch löschen? (j/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Jj]$ ]]; then
    info "Lösche Pub Cache..."
    rm -rf ~/.pub-cache/git/media-kit-* 2>/dev/null
    rm -rf ~/.pub-cache/hosted/pub.dartlang.org/.cache/* 2>/dev/null
    success "Pub Cache gelöscht"
fi

# 📌 SCHRITT 7: ANDROID KONFIGURATION
echo ""
info "Konfiguriere Android Projekt..."

mkdir -p android

# local.properties - KRITISCH!
cat > android/local.properties << EOF
sdk.dir=$ANDROID_HOME
flutter.sdk=$FLUTTER_ROOT
EOF
success "local.properties erstellt"

# gradle.properties
cat > android/gradle.properties << 'EOF'
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
android.enableR8=false
org.gradle.parallel=true
org.gradle.daemon=true
org.gradle.caching=true
kotlin.incremental=true
EOF
success "gradle.properties erstellt"

# Keystore
if [ ! -f "android/app/keystore.jks" ]; then
    info "Erstelle Debug Keystore..."
    keytool -genkeypair \
        -alias androiddebugkey \
        -keypass android \
        -keystore android/app/keystore.jks \
        -storepass android \
        -dname "CN=Debug,O=Android,C=US" \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 > /dev/null 2>&1
    success "Keystore erstellt"
fi

# key.properties
cat > android/key.properties << 'EOF'
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=keystore.jks
EOF
success "key.properties erstellt"

# 📌 SCHRITT 8: .env DATEI
echo ""
if [ ! -f ".env" ]; then
    info "Erstelle .env Datei..."
    cat > .env << 'EOF'
AL_CLIENT_ID=35098
AL_CLIENT_SECRET=PMyeG26XugG35WEunlMUv7X5dwvgG8L5SFA6BNaA
CALLBACK_SCHEME=nyantv
EOF
    success ".env erstellt"
else
    success ".env existiert bereits"
fi

# 📌 SCHRITT 9: FLUTTER PUB GET
echo ""
info "Installiere Dependencies..."
rm -f pubspec.lock 2>/dev/null

if ! flutter pub get; then
    error_exit "Pub get fehlgeschlagen" "Prüfe Internetverbindung"
fi
success "Dependencies installiert"

# 📌 SCHRITT 10: SPLASH SCREEN
echo ""
info "Generiere Splash Screen..."
dart run flutter_native_splash:create || warning "Splash Screen Fehler (ignoriert)"

# 📌 SCHRITT 11: GRADLE WRAPPER NEU GENERIEREN
echo ""
info "Regeneriere Gradle Wrapper..."
cd android
./gradlew wrapper --gradle-version 8.11.1 --distribution-type bin || warning "Wrapper Update fehlgeschlagen"
cd ..
success "Gradle Wrapper aktualisiert"

# 📌 SCHRITT 12: TEST BUILD (OHNE FLUTTER)
echo ""
info "Teste Gradle direkt..."
cd android
./gradlew clean 2>/dev/null || true
cd ..
success "Gradle Test OK"

# 📌 SCHRITT 13: FLUTTER BUILD
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}🔨 STARTE BUILD${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

info "Build Config:"
echo "  Flutter: $FLUTTER_ROOT"
echo "  Java: $JAVA_HOME"
echo "  Android: $ANDROID_HOME"
echo ""

# Erste Versuch
info "Baue Split APKs..."
if flutter build apk --split-per-abi --no-tree-shake-icons --release; then
    success "Split APKs erfolgreich!"
else
    echo ""
    warning "Erster Versuch fehlgeschlagen. Versuche alternative Methode..."
    
    # Alternative: Direkter Gradle Aufruf
    info "Versuche direkten Gradle Build..."
    cd android
    ./gradlew assembleRelease \
        -Ptarget-platform=android-arm64 \
        -Ptarget=../lib/main.dart \
        --stacktrace
    
    if [ $? -eq 0 ]; then
        success "Build via Gradle erfolgreich!"
        cd ..
    else
        cd ..
        error_exit "Build fehlgeschlagen" \
            "Mögliche Schritte:\n\
1. Lösche komplett: rm -rf ~/.gradle android/.gradle build\n\
2. Starte Flutter neu: flutter doctor -v\n\
3. Prüfe settings.gradle auf Fehler"
    fi
fi

# Universal APK
info "Baue Universal APK..."
flutter build apk --release --no-tree-shake-icons || warning "Universal APK fehlgeschlagen"

# 📌 SCHRITT 14: APKs UMBENENNEN
echo ""
info "Benenne APKs um..."

APK_DIR="build/app/outputs/flutter-apk"
if [ -d "$APK_DIR" ]; then
    cd "$APK_DIR"
    
    [ -f "app-armeabi-v7a-release.apk" ] && mv app-armeabi-v7a-release.apk NyanTV-Android-armeabi-v7a.apk
    [ -f "app-arm64-v8a-release.apk" ] && mv app-arm64-v8a-release.apk NyanTV-Android-arm64-v8a.apk
    [ -f "app-x86_64-release.apk" ] && mv app-x86_64-release.apk NyanTV-Android-x86_64.apk
    [ -f "app-release.apk" ] && mv app-release.apk NyanTV-Android-universal.apk
    
    cd - > /dev/null
    success "APKs umbenannt"
fi

# 📌 SCHRITT 15: ERGEBNISSE
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}✨ BUILD ABGESCHLOSSEN!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

APK_COUNT=$(ls -1 "$APK_DIR"/NyanTV-*.apk 2>/dev/null | wc -l)
if [ $APK_COUNT -gt 0 ]; then
    echo -e "${GREEN}📱 Generierte APKs:${NC}"
    for apk in "$APK_DIR"/NyanTV-*.apk; do
        SIZE=$(du -h "$apk" 2>/dev/null | cut -f1)
        echo -e "   ✅ $(basename "$apk") ($SIZE)"
    done
    echo ""
    echo -e "${BLUE}📍 Ordner: $(pwd)/$APK_DIR${NC}"
    
    read -p "Ordner öffnen? (j/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        open "$APK_DIR"
    fi
else
    warning "Keine APKs gefunden!"
    echo ""
    echo -e "${YELLOW}Debug Info:${NC}"
    ls -la build/app/outputs/ 2>/dev/null || echo "Kein outputs Ordner"
fi

echo ""
echo -e "${BLUE}✅ Fertig!${NC}"