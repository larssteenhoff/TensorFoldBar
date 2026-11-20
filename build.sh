#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/dist/TensorFold Bar.app"
mkdir -p dist
osacompile -s -o "$app" TensorFoldBar.applescript
resources="$app/Contents/Resources"
cp update.sh "$resources/update.sh"
cp benchmark.rb "$resources/benchmark.rb"
plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Set :LSUIElement true' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.larssteenhoff.TensorFoldBar' "$plist" 2>/dev/null || true
if [[ -n "${TENSORFOLD_RUNTIME:-}" ]]; then
 ditto "$TENSORFOLD_RUNTIME" "$resources/runtime"
else
 mkdir -p "$resources/runtime"
 /bin/bash update.sh "$resources/runtime"
fi
codesign --force --sign - "$app"
echo "Built: $app"
