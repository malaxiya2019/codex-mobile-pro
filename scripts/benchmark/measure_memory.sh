#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 内存/CPU 占用测量脚本
# 使用 adb shell dumpsys meminfo + top 采集
# ──────────────────────────────────────────────────────────────
# 依赖: adb (Android Debug Bridge)
# 用法: bash scripts/benchmark/measure_memory.sh
# ──────────────────────────────────────────────────────────────

set -euo pipefail

PACKAGE="com.codexmobile.app"
OUTPUT_DIR="build/benchmark"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/memory_cpu_${TIMESTAMP}.txt"

mkdir -p "$OUTPUT_DIR"

echo "═══════════════════════════════════════════════════"
echo "  内存/CPU 占用测量"
echo "  包名: $PACKAGE"
echo "  输出: $OUTPUT_FILE"
echo "═══════════════════════════════════════════════════"

# ── 检查设备连接 ──
if ! adb devices | grep -q "device$"; then
  echo "❌ 未检测到 Android 设备，请连接设备并启用 USB 调试"
  exit 1
fi

exec > >(tee "$OUTPUT_FILE") 2>&1

echo "设备: $(adb shell getprop ro.product.model)"
echo "Android: $(adb shell getprop ro.build.version.release)"
echo "测量时间: $(date)"
echo ""

# ── 阶段 1：空闲状态 ──
echo "═══════════════════════════════════════════════════"
echo "  阶段 1：空闲状态（应用在后台）"
echo "═══════════════════════════════════════════════════"

# 确保应用在后台
adb shell input keyevent KEYCODE_HOME
sleep 3

echo ""
echo "── dumpsys meminfo ──"
adb shell dumpsys meminfo "$PACKAGE" | grep -E "(TOTAL|Native Heap|Dalvik Heap|PSS Total)" || echo "  (应用未运行)"

echo ""
echo "── CPU 占用 (top) ──"
adb shell top -n 1 -b | grep "$PACKAGE" || echo "  (应用未运行)"

sleep 2

# ── 阶段 2：首页显示 ──
echo ""
echo "═══════════════════════════════════════════════════"
echo "  阶段 2：首页显示（应用在前台）"
echo "═══════════════════════════════════════════════════"

adb shell am start -W "$PACKAGE/.MainActivity" > /dev/null 2>&1
sleep 5

echo ""
echo "── dumpsys meminfo ──"
adb shell dumpsys meminfo "$PACKAGE" | grep -E "(TOTAL|Native Heap|Dalvik Heap|PSS Total)"

echo ""
echo "── CPU 占用 (top) ──"
adb shell top -n 1 -b | grep "$PACKAGE" || echo "  (未找到进程)"

sleep 2

# ── 阶段 3：AI 对话页面（模拟对话） ──
echo ""
echo "═══════════════════════════════════════════════════"
echo "  阶段 3：AI 对话页面"
echo "═══════════════════════════════════════════════════"

# 这里需要根据实际路由调整 — 如果已经集成了 AI 对话路由则可用
echo ""
echo "── dumpsys meminfo ──"
adb shell dumpsys meminfo "$PACKAGE" | grep -E "(TOTAL|Native Heap|Dalvik Heap|PSS Total)"

echo ""
echo "── CPU 占用 (top) ──"
adb shell top -n 1 -b | grep "$PACKAGE" || echo "  (未找到进程)"

# ── 汇总 ──
echo ""
echo "═══════════════════════════════════════════════════"
echo "  原始数据已保存到: $OUTPUT_FILE"
echo "═══════════════════════════════════════════════════"
