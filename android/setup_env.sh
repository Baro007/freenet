#!/bin/bash
set -e

echo "=== Freenet Android Geliştirme Ortamı Kurulumu ==="

# 1. Homebrew'in varligini dogrula
BREW_BIN=""
if [ -f "/opt/homebrew/bin/brew" ]; then
    BREW_BIN="/opt/homebrew/bin/brew"
elif [ -f "/usr/local/bin/brew" ]; then
    BREW_BIN="/usr/local/bin/brew"
else
    echo "Hata: Homebrew bulunamadi! Lutfen once Homebrew kurun."
    exit 1
fi

echo "Homebrew bulundu: $BREW_BIN"

# 2. Java 17 Kurulumu
if ! $BREW_BIN list --formula | grep -q "openjdk@17"; then
    echo "Java 17 (openjdk@17) kuruluyor..."
    $BREW_BIN install openjdk@17
else
    echo "Java 17 (openjdk@17) zaten kurulu."
fi

# Java yolunu belirle
JAVA_HOME_DIR=""
if [ -d "/opt/homebrew/opt/openjdk@17" ]; then
    JAVA_HOME_DIR="/opt/homebrew/opt/openjdk@17"
else
    JAVA_HOME_DIR="/usr/local/opt/openjdk@17"
fi
echo "Java 17 Yolu: $JAVA_HOME_DIR"

# 3. Android Command-line Tools Kurulumu
if ! $BREW_BIN list --cask | grep -q "android-commandlinetools"; then
    echo "Android Command-line Tools kuruluyor..."
    $BREW_BIN install --cask android-commandlinetools
else
    echo "Android Command-line Tools zaten kurulu."
fi

# SDK Yolunu belirle
ANDROID_SDK_ROOT=""
if [ -d "/opt/homebrew/share/android-commandlinetools" ]; then
    ANDROID_SDK_ROOT="/opt/homebrew/share/android-commandlinetools"
else
    ANDROID_SDK_ROOT="/usr/local/share/android-commandlinetools"
fi
echo "Android SDK Yolu: $ANDROID_SDK_ROOT"

# 4. Lisanslari Kabul Etme ve Gerekli Paketleri Yukleme
SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

if [ ! -f "$SDKMANAGER" ]; then
    echo "Hata: sdkmanager bulunamadi! Yol: $SDKMANAGER"
    exit 1
fi

# Java 17 ile calistirmak icin JAVA_HOME'u geçici olarak ayarlayalim
export JAVA_HOME="$JAVA_HOME_DIR"
export PATH="$JAVA_HOME/bin:$PATH"

echo "Lisanslar kabul ediliyor..."
yes | "$SDKMANAGER" --licenses || true

echo "Gerekli Android SDK bilesenleri kuruluyor (Android 34)..."
"$SDKMANAGER" "platform-tools" "platforms;android-34" "build-tools;34.0.0"

echo "=== Kurulum Basariyla Tamamlandi ==="
echo "Java 17 ve Android SDK (API 34) hazir."
