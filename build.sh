#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="azure桌面小板"
EXEC_NAME="azure-small-panel"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

echo "==> 编译 Swift 源码"
swiftc -O -o "$APP_PATH/Contents/MacOS/$EXEC_NAME" Sources/*.swift

echo "==> 写入 Info.plist"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"

echo "==> 签名（ad-hoc）"
codesign --force --sign - "$APP_PATH"

echo "==> 构建完成: $PWD/$APP_PATH"

if [ "${1:-}" = "--install" ]; then
    # 装进 /Applications 并启动（开机自启用这个路径最稳）
    APP_DST="/Applications/$APP_NAME.app"
    rm -rf "$APP_DST"
    ditto "$APP_PATH" "$APP_DST"
    echo "==> 已安装到 $APP_DST"
    pkill -f "$EXEC_NAME" 2>/dev/null || true
    sleep 0.3
    open "$APP_DST"
    echo "==> 已启动 /Applications 版本"
elif [ "${1:-}" = "--run" ]; then
    pkill -f "$EXEC_NAME" 2>/dev/null || true
    sleep 0.3
    open "$APP_PATH"
    echo "==> 已启动 $APP_NAME"
fi
