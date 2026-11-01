#!/usr/bin/env bash
# 打包 Deadliner for macOS（Release，arm64，临时签名，不公证、不发布）。
#
# 用法：scripts/package.sh [输出目录]
# 产物：<输出目录>/Deadliner-for-macOS-<版本>-arm64.dmg 与 .zip（各附 SHA-256）
# 以 DEADLINER_LIFI_MODE=private 构建时文件名带 -private：含闭源 Lifi，只能自用，不能公开分发。
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
suffix=""
[[ "${DEADLINER_LIFI_MODE:-stub}" == "private" ]] && suffix="-private"
base="Deadliner-for-macOS-$version-arm64$suffix"
zip="$out_dir/$base.zip"
rm -f "$zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$zip"

# 解压到临时目录再验证一次，确认分发出去的就是签名完整的包。
check_dir="$(mktemp -d "$build_root/verify.XXXXXX")"
ditto -x -k "$zip" "$check_dir"
codesign --verify --deep --strict "$check_dir/$app_name.app"
rm -rf "$check_dir"

# 磁盘映像：应用 + 「应用程序」文件夹的替身，打开后拖进去即可安装。
dmg="$out_dir/$base.dmg"
staging="$(mktemp -d "$build_root/dmg.XXXXXX")"
ditto --norsrc --noextattr "$app" "$staging/$app_name.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname "$app_name" -srcfolder "$staging" -fs HFS+ -format UDZO -ov -quiet "$dmg"
rm -rf "$staging"

# 挂载检查映像中的应用签名完整。
mount_dir="$(mktemp -d "$build_root/mount.XXXXXX")"
hdiutil attach "$dmg" -readonly -nobrowse -noverify -mountpoint "$mount_dir" -quiet
codesign --verify --deep --strict "$mount_dir/$app_name.app"
hdiutil detach "$mount_dir" -quiet
rmdir "$mount_dir"

( cd "$out_dir" && for file in "$(basename "$dmg")" "$(basename "$zip")"; do shasum -a 256 "$file" | tee "$file.sha256"; done )
printf 'Packaged %s and %s (%s); app bundle: %s\n' "$dmg" "$zip" "$version" "$app"
