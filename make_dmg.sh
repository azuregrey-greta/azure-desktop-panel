#!/bin/bash
# 打 DMG 安装包：双击打开 → 把 app 拖进 Applications 文件夹即完成安装
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="azure桌面小板"
VERSION="1.1"
BUILD_DIR=".build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="dist"
DMG_PATH="$DIST_DIR/azure-desktop-panel-${VERSION}.dmg"

echo "==> 先构建 app"
./build.sh

mkdir -p "$DIST_DIR"

echo "==> 组装 DMG 内容（app + Applications 快捷方式）"
rm -rf "$DIST_DIR/staging"
mkdir -p "$DIST_DIR/staging"
cp -R "$APP_PATH" "$DIST_DIR/staging/"
ln -s /Applications "$DIST_DIR/staging/Applications"

echo "==> 生成 DMG"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DIST_DIR/staging" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$DIST_DIR/staging"

echo "==> 完成: $PWD/$DMG_PATH"
