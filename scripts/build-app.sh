#!/bin/bash
# 组装可分发的 TodoBoard.app：通用二进制（arm64 + x86_64）+ ad-hoc 签名 + zip
set -euo pipefail
cd "$(dirname "$0")/.."

BIN_NAME="TodoBoardApp"
OUT="dist"
APP="$OUT/TodoBoard.app"

echo "==> 通用二进制构建（Release, arm64 + x86_64）"
swift build --scratch-path .build-local -c release --arch arm64 --arch x86_64 -Xswiftc -debug-prefix-map -Xswiftc "$PWD=."

BUILT=".build-local/apple/Products/Release/$BIN_NAME"
if [ ! -f "$BUILT" ]; then
  BUILT=".build-local/release/$BIN_NAME"
fi
echo "==> 二进制: $BUILT"
lipo -archs "$BUILT"

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILT" "$APP/Contents/MacOS/$BIN_NAME"
cp -R Sources/BoardUI/Avatars "$APP/Contents/Resources/Avatars"
cp -R runtime "$APP/Contents/Resources/runtime"
cp -R integrations "$APP/Contents/Resources/integrations"
cp pyproject.toml README.md LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
find "$APP/Contents/Resources/runtime" -type d -name __pycache__ -prune -exec rm -rf {} +
cp Resources/Info.plist "$APP/Contents/Info.plist"

strip -S "$APP/Contents/MacOS/$BIN_NAME"
echo "==> ad-hoc 签名"
codesign --force --sign - "$APP"
codesign --verify "$APP"

echo "==> zip"
ditto -c -k --keepParent "$APP" "$OUT/TodoBoard.zip"

echo ""
echo "✅ 完成："
echo "   $APP"
echo "   $OUT/TodoBoard.zip（拷到其他 Mac，解压后右键→打开）"
