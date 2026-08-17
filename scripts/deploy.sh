#!/usr/bin/env bash
# Deploy portal-gphotos to a Meta Portal over adb in one shot:
#   install the APK -> push the OAuth client (+ optional pre-minted token) -> launch.
#
# Idempotent: safe to re-run. Everything but the APK is optional, so this also
# works as a configuration pass on an already-installed app.
#
# Non-destructive: a debug<->release switch changes the signing key, which forces an
# uninstall+install. We preserve the downloaded media + OAuth token across that by
# stashing the app's files dir on /sdcard and moving it back after the fresh install.
#
# Also applies the device settings the frame expects: no Dream (screensaver) ever takes
# over, the screen blanks after 5 minutes idle, and presence wakes it back into whatever
# app was last in front. Pass --no-settings to install without touching device settings.
#
# Usage:
#   scripts/deploy.sh [-s SERIAL] [--apk PATH] [--client client_secret.json]
#                     [--token token.json] [--build] [--no-settings]
#
# Files default to ./client_secret.json and ./token.json if present (else skipped).
# adb is found via $ADB, $ANDROID_HOME/platform-tools, or PATH.
set -euo pipefail

PKG="com.ramnat.portalgphotos"
LEGACY_DREAM="$PKG/$PKG.PhotoDreamService"
FILES_DIR="/sdcard/Android/data/$PKG/files"

SERIAL="${SERIAL:-}"
if [[ -n "${APK:-}" ]]; then
  # Keep whatever the user explicitly passed
  :
elif [[ -f "app-release.apk" ]]; then
  APK="app-release.apk"
elif [[ -f "app/build/outputs/apk/release/app-release.apk" ]]; then
  APK="app/build/outputs/apk/release/app-release.apk"
else
  APK="app/build/outputs/apk/debug/app-debug.apk"
fi

CLIENT="${CLIENT:-client_secret.json}"
TOKEN="${TOKEN:-token.json}"
DO_BUILD=0
SKIP_SETTINGS=0

usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--serial) SERIAL="$2"; shift 2;;
    --apk)       APK="$2"; shift 2;;
    --client)    CLIENT="$2"; shift 2;;
    --token)     TOKEN="$2"; shift 2;;
    --build)     DO_BUILD=1; shift;;
    --no-settings) SKIP_SETTINGS=1; shift;;
    -h|--help)   usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1;;
  esac
done

# --- locate adb ---
ADB="${ADB:-}"
if [[ -z "$ADB" ]]; then
  if command -v adb >/dev/null 2>&1; then ADB="$(command -v adb)"
  elif [[ -n "${ANDROID_HOME:-}" && -x "$ANDROID_HOME/platform-tools/adb" ]]; then ADB="$ANDROID_HOME/platform-tools/adb"
  elif [[ -x "$HOME/Android/Sdk/platform-tools/adb" ]]; then ADB="$HOME/Android/Sdk/platform-tools/adb"
  else echo "adb not found — set ADB=/path/to/adb or ANDROID_HOME" >&2; exit 1; fi
fi

# --- pick the device ---
if [[ -z "$SERIAL" ]]; then
  DEVICES=()
  while IFS= read -r line; do
    DEVICES+=("$line")
  done < <("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}')
  case ${#DEVICES[@]} in
    0) echo "no authorized adb devices — connect the Portal and enable ADB" >&2; exit 1;;
    1) SERIAL="${DEVICES[0]}";;
    *) echo "multiple devices; pass -s SERIAL. Found: ${DEVICES[*]}" >&2; exit 1;;
  esac
fi
adb() { "$ADB" -s "$SERIAL" "$@"; }
echo ">> device: $SERIAL"

# --- optional build ---
if [[ $DO_BUILD -eq 1 ]]; then
  echo ">> ./gradlew assembleRelease"
  ./gradlew assembleRelease
  # Re-evaluate APK if we just built the release one and the user didn't specify one
  if [[ -z "${APK:-}" || "$APK" == "app/build/outputs/apk/debug/app-debug.apk" ]]; then
    APK="app/build/outputs/apk/release/app-release.apk"
  fi
fi
[[ -f "$APK" ]] || { echo "APK not found: $APK (download it, or run with --build)" >&2; exit 1; }

# --- install (non-destructive across debug<->release signature changes) ---
# `adb install -r` fails when the new APK's signing key differs from the installed
# one (debug vs release), and the only way through is uninstall+install — which
# normally wipes the app's external files, losing all downloaded media + the token.
# So on a signature mismatch we move the files dir to a top-level /sdcard backup
# (outside the app dir, so uninstall can't touch it; a rename on the same fs, instant),
# reinstall fresh, then move it back. A plain in-place update keeps data and skips all this.
echo ">> install $APK"
install_out="$(adb install -r "$APK" 2>&1 || true)"
if grep -q "Success" <<<"$install_out"; then
  echo "   ok (in-place update, data preserved)"
elif grep -qiE "INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match" <<<"$install_out"; then
  echo "   signature mismatch (debug<->release) — preserving media + token across reinstall"
  BAK="/sdcard/portal-gphotos-deploy.bak"
  adb shell "rm -rf '$BAK'"
  if adb shell "test -d '$FILES_DIR'"; then
    adb shell "mv '$FILES_DIR' '$BAK'" && echo "   backed up app files -> $BAK"
    HAVE_BAK=1
  else
    HAVE_BAK=0
  fi
  adb uninstall "$PKG" >/dev/null && echo "   uninstalled old build"
  adb install "$APK" >/dev/null && echo "   installed fresh"
  if [[ "${HAVE_BAK:-0}" -eq 1 ]]; then
    adb shell "mkdir -p '$(dirname "$FILES_DIR")' && rm -rf '$FILES_DIR' && mv '$BAK' '$FILES_DIR'" \
      && echo "   restored app files (media + token)"
  fi
else
  echo "   install failed:" >&2
  echo "$install_out" >&2
  exit 1
fi

# --- push config ---
adb shell mkdir -p "$FILES_DIR"
if [[ -f "$CLIENT" ]]; then echo ">> push $CLIENT"; adb push "$CLIENT" "$FILES_DIR/client_secret.json" >/dev/null && echo "   ok"
else echo ">> no $CLIENT found — pass --client PATH to push one, or use a build with baked-in creds"; fi
if [[ -f "$TOKEN" ]]; then echo ">> push $TOKEN (pre-minted)"; adb push "$TOKEN" "$FILES_DIR/token.json" >/dev/null && echo "   ok"; fi

# --- remove the retired automatic screensaver hook from older installs ---
# Read first and change nothing unless the active component is exactly ours. The
# replacement is Android's own recorded default, never a hard-coded Portal component.
CURRENT_DREAM="$(adb shell settings get secure screensaver_components | tr -d '\r')"
if [[ "$CURRENT_DREAM" == "$LEGACY_DREAM" ]]; then
  DEFAULT_DREAM="$(adb shell settings get secure screensaver_default_component | tr -d '\r')"
  if [[ -n "$DEFAULT_DREAM" && "$DEFAULT_DREAM" != "null" ]]; then
    echo ">> clearing retired app Dream from screensaver_components"
    adb shell settings put secure screensaver_components "$DEFAULT_DREAM"
  else
    echo ">> warning: legacy app Dream is active but no stock default is recorded; leaving component unchanged" >&2
  fi
fi

# --- idle/presence behavior ---
# Target: presence wakes the display and restores whatever app was last in front;
# 5 minutes without user activity blanks the screen.
#
# Verified on a Portal Mini (omni_prod). Three caveats worth knowing before changing these:
#
#   * screensaver_enabled=0 and screensaver_activate_on_sleep=0 do NOT stop the launcher's
#     own HomeDreamService — a Dream still starts on screen-off. What matters is
#     screensaver_components: while it points at the launcher, waking lands on the Portal
#     home screen instead of the app you left in front. The launcher repoints it at itself
#     on every boot, so the app carries a guard (ScreensaverGuard) that steers it back.
#     That guard needs a one-time adb grant, applied below.
#   * Portal's Display > Screen Off UI does not show screen_off_timeout. It renders
#     (sleep_timeout - screen_off_timeout), so the two must be written as a pair or the
#     menu reports a value that is neither. 600000-300000 is what makes it read "5 minutes".
#   * The UI also writes a proprietary PosSettings store that adb cannot reach. These keys
#     drive the framework correctly, but if the on-device menu and observed behavior ever
#     disagree, re-pick the value in Portal's UI to resync all three writes.
#
# The device is mains-powered with no battery, so only the _charging variant matters;
# _discharging is deliberately left alone.
if [[ $SKIP_SETTINGS -eq 0 ]]; then
  echo ">> applying idle/presence settings"
  adb shell settings put secure screensaver_enabled 0
  adb shell settings put secure screensaver_activate_on_sleep 0
  adb shell settings put secure screensaver_activate_on_dock 0

  # Blank after 5 min idle. sleep_timeout is the presence-aware timer; keep the pair in sync.
  adb shell settings put system screen_off_timeout 300000
  adb shell settings put secure sleep_timeout 600000
  adb shell settings put secure sleep_timeout_charging 600000

  # Motion/tap wake.
  adb shell settings put secure wake_gesture_enabled 1
  adb shell settings put secure double_tap_to_wake 1

  # Lets ScreensaverGuard repoint screensaver_components after each boot. Persists across
  # reboots and in-place updates; only a full uninstall drops it.
  if adb shell pm grant "$PKG" android.permission.WRITE_SECURE_SETTINGS 2>/dev/null; then
    echo "   granted WRITE_SECURE_SETTINGS (screensaver guard active)"
  else
    echo "   warning: could not grant WRITE_SECURE_SETTINGS — the launcher's Dream will win" >&2
    echo "   after each reboot and waking will land on the Portal home screen" >&2
  fi
  echo "   ok (screen off after 5 min idle; presence wakes and restores the last app)"
else
  echo ">> skipping idle/presence settings (--no-settings)"
fi

# --- launch ---
echo ">> launch"
adb shell am start -n "$PKG/.MainActivity" >/dev/null
echo ">> done. If this is a first install with no token, tap 'Sign in on this device'."
