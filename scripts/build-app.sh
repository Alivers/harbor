#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${HARBOR_BUILD_DIR:-$project_dir/.build}"
configuration="${HARBOR_CONFIGURATION:-release}"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/module-cache"
swift build --product Harbor --package-path "$project_dir" --scratch-path "$build_dir" --cache-path "$build_dir/cache" --config-path "$build_dir/config" --security-path "$build_dir/security" --disable-sandbox -c "$configuration"
bin_dir="$(swift build --package-path "$project_dir" --scratch-path "$build_dir" --disable-sandbox -c "$configuration" --show-bin-path)"
app="$project_dir/Harbor.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Harbor" "$app/Contents/MacOS/Harbor"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Harbor</string>
<key>CFBundleIdentifier</key><string>dev.local.harbor</string>
<key>CFBundleName</key><string>Harbor</string>
<key>CFBundleDisplayName</key><string>Harbor</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Harbor opens an interactive container shell in Terminal when you choose Terminal.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Built: $app"
