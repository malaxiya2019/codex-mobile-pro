#!/usr/bin/env bash
# ============================================================
#  Codex Mobile Pro — Flutter 项目初始化脚本
#  在开发机上运行（需要 Flutter SDK）
#  用法: bash setup_flutter_project.sh
# ============================================================

set -euo pipefail

echo "🚀 Codex Mobile Pro — Flutter 项目初始化"
echo "========================================"

# 1. 检查 Flutter 是否安装
if ! command -v flutter &>/dev/null; then
    echo "❌ 未检测到 Flutter SDK，请先安装 Flutter："
    echo "   https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✅ Flutter 已安装: $(flutter --version | head -1)"

# 2. 生成 Flutter 工程脚手架（android/ ios/ 等）
cd "$(dirname "$0")"

if [ -d "android" ] || [ -d "ios" ]; then
    echo "⚠️  android/ 或 ios/ 目录已存在，跳过 flutter create"
else
    echo "📦 生成 Flutter 工程脚手架..."
    # 创建临时目录，复制必要文件
    TEMP_DIR=$(mktemp -d)
    flutter create --project-name codex_mobile_pro \
        --org com.codexmobile \
        --platforms android \
        "$TEMP_DIR/codex_mobile_pro"

    # 复制 android/ 目录
    cp -r "$TEMP_DIR/codex_mobile_pro/android" .
    # 复制其他必需文件
    cp "$TEMP_DIR/codex_mobile_pro/.gitignore" . 2>/dev/null || true

    # 清理
    rm -rf "$TEMP_DIR"
    echo "✅ Flutter 工程脚手架已生成"
fi

# 3. 安装依赖
echo "📦 安装依赖..."
flutter pub get

# 4. 运行分析
echo "🔍 运行静态分析..."
flutter analyze

# 5. 运行测试
echo "🧪 运行测试..."
flutter test

echo ""
echo "========================================"
echo "🎉 初始化完成！"
echo ""
echo "下一步："
echo "  flutter run              # 运行 App"
echo "  flutter build apk --debug # 构建 APK"
echo "========================================"
