#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/Scrip.app"

cd "$root"
swift run ScripCoreCheck
swift build -c release --product Scrip
bin="$(swift build -c release --product Scrip --show-bin-path)"

rm -rf "$app" "$root/AIUsageBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/js"
cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$bin/Scrip" "$app/Contents/MacOS/Scrip"
cp "$root/Sources/ScripWeb/Resources/js/"*.js "$app/Contents/Resources/js/"

if ls "$bin"/*.bundle >/dev/null 2>&1; then
  cp -R "$bin"/*.bundle "$app/Contents/Resources/"
fi

echo "Built $app"
