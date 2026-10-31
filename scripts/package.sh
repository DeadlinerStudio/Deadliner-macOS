#!/usr/bin/env bash
# 打包 Deadliner for macOS（Release，arm64，临时签名，不公证、不发布）。
#
# 用法：scripts/package.sh [输出目录]
# 产物：<输出目录>/Deadliner-for-macOS-<版本>-arm64.zip（附 SHA-256）
#
# 构建放在 ~/Library/Caches 下：Documents 由文件提供程序管理，会给文件夹加上 FinderInfo 等扩展属性，
# 导致签名校验失败（"resource fork, Finder information, or similar detritus not allowed"）。
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
out_dir="${1:-$project_dir/build/package}"
build_root="${DEADLINER_BUILD_DIR:-$HOME/Library/Caches/DeadlinerMacBuild}"
derived="$build_root/DerivedData"
app_name="Deadliner for macOS"

cd "$project_dir"
scripts/build-core.sh release
xcodegen generate --quiet
xattr -cr Frameworks/Shared.framework

xcodebuild -project DeadlinerMac.xcodeproj -scheme DeadlinerMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build -quiet

app="$derived/Build/Products/Release/$app_name.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"

codesign --verify --deep --strict "$app"
lipo -archs "$app/Contents/MacOS/$app_name" | grep -qx arm64
lipo -archs "$app/Contents/Frameworks/Shared.framework/Shared" | grep -qx arm64
if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'get-task-allow'; then
  echo "error: release build still carries debug entitlements" >&2
  exit 1
fi

mkdir -p "$out_dir"
zip="$out_dir/Deadliner-for-macOS-$version-arm64.zip"
rm -f "$zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"

# 解压到临时目录再验证一次，确认分发出去的就是签名完整的包。
check_dir="$(mktemp -d "$build_root/verify.XXXXXX")"
ditto -x -k "$zip" "$check_dir"
codesign --verify --deep --strict "$check_dir/$app_name.app"
rm -rf "$check_dir"

( cd "$out_dir" && shasum -a 256 "$(basename "$zip")" | tee "$(basename "$zip").sha256" )
printf 'Packaged %s (%s); app bundle: %s\n' "$zip" "$version" "$app"
