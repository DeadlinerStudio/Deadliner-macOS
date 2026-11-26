#!/usr/bin/env bash
# 安装锁定的 macOS framework 到 Frameworks/Shared.framework。
#
# - 不修改 Core 仓库：framework 导出由 scripts/deadliner-mac.init.gradle 在构建时补上。
# - DEADLINER_CORE_SOURCE=local 从本地源码构建，可通过 DEADLINER_LIFI_MODE 选择实现。
#
# 用法：scripts/build-core.sh [debug|release]
# 环境变量：
#   DEADLINER_CORE_DIR   Core 仓库位置（默认 ../DeadlinerCore）
#   DEADLINER_LIFI_MODE  private（默认）/ stub / auto
#   CONFIGURATION        Xcode 传入的 Debug / Release，未指定参数时使用
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case "${DEADLINER_CORE_SOURCE:-package}" in
  package) exec /usr/bin/env python3 "$project_dir/scripts/core_package.py" macos "$project_dir/Frameworks/Shared.framework" --lock "$project_dir/core-package.lock.json" ;;
  local) ;;
  *) echo "DEADLINER_CORE_SOURCE must be package or local" >&2; exit 2 ;;
esac
core_dir="${DEADLINER_CORE_DIR:-$project_dir/../DeadlinerCore}"
lifi_mode="${DEADLINER_LIFI_MODE:-private}"

case "$lifi_mode" in
  private|stub|auto) ;;
  *) printf 'error: DEADLINER_LIFI_MODE must be private, stub or auto.\n' >&2; exit 2 ;;
esac
if [[ "$lifi_mode" == private && ! -f "$core_dir/.private/lifi/lifi-api-version" ]]; then
  printf 'error: Private Lifi missing. Run %s/runscript/setupLifi.sh or set DEADLINER_LIFI_MODE=stub.\n' "$core_dir" >&2
  exit 1
fi

configuration="${1:-${CONFIGURATION:-Debug}}"
case "$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')" in
  debug) variant=Debug; build_dir=debugFramework ;;
  release) variant=Release; build_dir=releaseFramework ;;
  *) printf 'Unknown configuration: %s (expected debug or release)\n' "$configuration" >&2; exit 2 ;;
esac

if [[ ! -x "$core_dir/gradlew" ]]; then
  printf 'error: DeadlinerCore not found at %s. Set DEADLINER_CORE_DIR.\n' "$core_dir" >&2
  exit 1
fi

if [[ -z "${JAVA_HOME:-}" ]]; then
  JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || /usr/libexec/java_home -v 17+ 2>/dev/null || true)"
fi
if [[ -z "$JAVA_HOME" ]]; then
  printf 'error: JDK 17+ is required to build DeadlinerCore.\n' >&2
  exit 1
fi
export JAVA_HOME

# Xcode 的脚本环境会带上 SDKROOT 等变量，Kotlin/Native 需要自己选择 macOS SDK。
unset SDKROOT SDK_NAME PLATFORM_NAME ARCHS

printf 'Building DeadlinerCore (%s, lifiMode=%s) from %s\n' "$variant" "$lifi_mode" "$core_dir"
(
  cd "$core_dir"
  ./gradlew -PlifiMode="$lifi_mode" \
    --init-script "$project_dir/scripts/deadliner-mac.init.gradle" \
    ":shared:link${variant}FrameworkMacosArm64" --console=plain --quiet
)

source_framework="$core_dir/shared/build/bin/macosArm64/$build_dir/Shared.framework"
target_dir="$project_dir/Frameworks"
if [[ ! -d "$source_framework" ]]; then
  printf 'error: framework was not produced at %s\n' "$source_framework" >&2
  exit 1
fi

mkdir -p "$target_dir"
staging="$(mktemp -d "$target_dir/.Shared.XXXXXX")"
cp -R "$source_framework" "$staging/Shared.framework"
rm -rf "$target_dir/Shared.framework"
mv "$staging/Shared.framework" "$target_dir/Shared.framework"
rmdir "$staging"
printf 'Deployed %s\n' "$target_dir/Shared.framework"
