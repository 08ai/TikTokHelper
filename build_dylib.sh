#!/bin/bash
# build_dylib.sh — 编译 TikTokHelper.dylib
# 用法: bash build_dylib.sh

echo "=== 编译 TikTokHelper.dylib ==="

# 查找 SDK 路径
SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

if [ -z "$SDK" ]; then
    echo "未找到 iPhoneOS SDK，尝试使用本地 clang..."
    clang -arch arm64 -dynamiclib \
        -framework Foundation -framework UIKit -framework CoreGraphics \
        -fobjc-arc \
        -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk \
        -miphoneos-version-min=14.0 \
        -o TikTokHelper.dylib \
        TikTokHelper.m 2>&1
else
    echo "SDK: $SDK"
    clang -arch arm64 -dynamiclib \
        -framework Foundation -framework UIKit -framework CoreGraphics \
        -fobjc-arc \
        -isysroot "$SDK" \
        -miphoneos-version-min=14.0 \
        -o TikTokHelper.dylib \
        TikTokHelper.m
fi

if [ $? -eq 0 ]; then
    echo "✓ 编译成功: TikTokHelper.dylib"
    ls -lh TikTokHelper.dylib
    echo ""
    echo "=== 注入方式 ==="
    echo "1. Frida:   frida -U -l inject.js TikTok"
    echo "2. FridaGadget: 将 dylib 放入 .app，配合 FridaGadget.dylib 自动加载"
    echo "3. Theos:   make package install"
else
    echo "✗ 编译失败!"
    exit 1
fi
