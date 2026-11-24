#!/usr/bin/env bash
set -euo pipefail

export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
AVD=Android12
IMAGE='system-images;android-31;google_apis_playstore;x86_64'

case "${1:-}" in
 setup)
   mkdir -p "$ANDROID_HOME/cmdline-tools"
   if ! command -v sdkmanager >/dev/null; then
     tmp=$(mktemp -d)
     trap 'rm -rf "$tmp"' EXIT
     curl --fail --location --retry 3 https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o "$tmp/sdk.zip"
     unzip -q "$tmp/sdk.zip" -d "$tmp"
     mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
   fi
   sdkmanager --licenses
   sdkmanager "platform-tools" "emulator" "$IMAGE"
   if ! avdmanager list avd | grep -q "Name: $AVD$"; then
     printf 'no\n' | avdmanager create avd -n "$AVD" -k "$IMAGE"
   fi
   mkdir -p apks
   ;;
 start)
   command -v emulator >/dev/null || { echo "Execute setup primeiro."; exit 1; }
   export DISPLAY=:77
   mkdir -p "$HOME/.config/android-lab"
   password="$HOME/.config/android-lab/vnc.pass"
   umask 077
   if [[ ! -f "$password" ]]; then
     x11vnc -storepasswd "$password"
   fi
   pids=()
   cleanup() {
     for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
   }
   trap cleanup EXIT
   trap 'exit 130' INT TERM
   Xvfb "$DISPLAY" -screen 0 1280x1024x24 -nolisten tcp &
   pids+=("$!")
   sleep 2
   x11vnc -display "$DISPLAY" -localhost -rfbport 5900 -rfbauth "$password" -forever -shared &
   pids+=("$!")
   websockify --web=/usr/share/novnc 127.0.0.1:6080 127.0.0.1:5900 &
   pids+=("$!")
   accel=auto
   if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
     accel=off
     echo "KVM indisponível: tentando emulação por software, sem garantia."
   fi
   echo "Interface: http://localhost:6080/vnc.html (porta privada)"
   emulator -avd "$AVD" -accel "$accel" -gpu swiftshader_indirect -no-audio -no-snapshot -memory 2048 -cores 2 -port 5554 -no-boot-anim &
   pids+=("$!")
   wait "${pids[3]}"
   ;;
 install)
   [[ $# -eq 2 && -f "$2" && "$2" == *.apk ]] || { echo "Uso: bash android.sh install arquivo.apk"; exit 1; }
   adb -s emulator-5554 install "$2"
   ;;
 status)
   if [[ -r /dev/kvm && -w /dev/kvm ]]; then echo "KVM acessível"; else echo "KVM indisponível"; fi
   if command -v emulator >/dev/null; then emulator -accel-check || true; fi
   if command -v adb >/dev/null; then adb devices -l; adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null || true; fi
   ;;
 *) echo "Uso: bash android.sh {setup|start|install arquivo.apk|status}"; exit 1 ;;
esac
