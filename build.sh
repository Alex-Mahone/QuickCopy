#!/bin/zsh
# QuickCopy 命令行构建（无需完整 Xcode，仅需 Command Line Tools）。
# 生成 build/QuickCopy.app，并使用固定的本机自签证书签名。
#
# 为什么不用 ad-hoc：ad-hoc 的 cdhash 每次编译都会变，macOS 会把新构建
# 当成另一个 App，导致辅助功能授权反复失效。自签证书的 designated
# requirement 固定为 “bundle id + 证书”，重编后授权仍然有效。
#
# 首次运行会自动创建身份（私钥在独立钥匙串中，不影响登录钥匙串）。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="QuickCopy"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

IDENTITY="QuickCopy Local Signing"
SIGN_DIR="$HOME/Library/Application Support/QuickCopy/signing"
KEYCHAIN_DB="$SIGN_DIR/QuickCopy.keychain-db"
KEYCHAIN_PASS="quickcopy"

ARCH="$(uname -m)"
if [[ "$ARCH" == "x86_64" ]]; then
    TARGET="x86_64-apple-macos13.0"
else
    TARGET="arm64-apple-macos13.0"
fi

# 确保固定签名身份存在；只在缺失时生成一次。
# 自签证书不受系统信任，find-identity 始终返回 0，故用 find-certificate 判断。
if ! security find-certificate -c "$IDENTITY" "$KEYCHAIN_DB" >/dev/null 2>&1; then
    ./tools/make_signing_cert.sh
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "QuickCopy/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "QuickCopy/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

sources=("${(@f)$(find QuickCopy -name '*.swift' -print | sort)}")

xcrun swiftc \
    -O \
    -swift-version 5 \
    -sdk "$SDK" \
    -target "$TARGET" \
    -module-name "$APP_NAME" \
    -o "$APP/Contents/MacOS/$APP_NAME" \
    "${sources[@]}"

security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_DB"

codesign \
    --force \
    --keychain "$KEYCHAIN_DB" \
    --sign "$IDENTITY" \
    --entitlements "QuickCopy/Resources/QuickCopy.entitlements" \
    "$APP"

codesign --verify --strict "$APP"

echo "Built: $(pwd)/$APP"
echo "Signing: $IDENTITY"
echo "Launch: open \"$(pwd)/$APP\""
