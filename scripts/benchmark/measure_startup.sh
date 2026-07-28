#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# 冷/热启动时间测量脚本
# 使用 adb logcat 抓取 ActivityManager 日志计算启动耗时
# ──────────────────────────────────────────────────────────────
# 依赖: adb (Android Debug Bridge)
# 用法: bash scripts/benchmark/measure_startup.sh [次数=5]
# ──────────────────────────────────────────────────────────────

set -euo pipefail

COUNT=${1:-5}
PACKAGE="com.codexmobile.app"
ACTIVITY=".MainActivity"

echo "═══════════════════════════════════════════════════"
echo "  冷/热启动时间测量"
echo "  包名: $PACKAGE"
echo "  测试次数: $COUNT"
echo "═══════════════════════════════════════════════════"

cold_times=()
hot_times=()

for i in $(seq 1 "$COUNT"); do
  echo ""
  echo "─── 第 $i 次 ───"

  # ── 冷启动 ──

  # 先强制停止应用
  adb shell am force-stop "$PACKAGE" 2>/dev/null || true
  sleep 2

  # 清除旧日志
  adb logcat -c 2>/dev/null || true

  # 启动应用
  adb shell am start -W "$PACKAGE/$ACTIVITY" > /tmp/am_start_cold.txt 2>&1 &
  sleep 1

  # 抓取 TotalTime
  cold_ms=$(grep "TotalTime" /tmp/am_start_cold.txt 2>/dev/null | awk '{print $2}' || echo "")
  if [ -n "$cold_ms" ] && [ "$cold_ms" -gt 0 ] 2>/dev/null; then
    cold_times+=("$cold_ms")
    echo "  冷启动: ${cold_ms}ms"
  else
    echo "  ⚠️ 冷启动测量失败（可能未连接设备）"
  fi

  # 等应用完全加载
  sleep 3

  # ── 热启动 ──

  # 按 Home 键
  adb shell input keyevent KEYCODE_HOME
  sleep 2

  # 清除旧日志
  adb logcat -c 2>/dev/null || true

  # 重新启动
  adb shell am start -W "$PACKAGE/$ACTIVITY" > /tmp/am_start_hot.txt 2>&1 &
  sleep 1

  hot_ms=$(grep "TotalTime" /tmp/am_start_hot.txt 2>/dev/null | awk '{print $2}' || echo "")
  if [ -n "$hot_ms" ] && [ "$hot_ms" -gt 0 ] 2>/dev/null; then
    hot_times+=("$hot_ms")
    echo "  热启动: ${hot_ms}ms"
  else
    echo "  ⚠️ 热启动测量失败"
  fi

  sleep 2
done

# ── 统计输出 ──

echo ""
echo "═══════════════════════════════════════════════════"
echo "  测量结果统计"
echo "═══════════════════════════════════════════════════"

calc_avg() {
  local arr=("$@")
  local sum=0
  for v in "${arr[@]}"; do ((sum+=v)); done
  echo $((sum / ${#arr[@]}))
}

calc_max() {
  local arr=("$@")
  local max=0
  for v in "${arr[@]}"; do [ "$v" -gt "$max" ] && max=$v; done
  echo "$max"
}

calc_min() {
  local arr=("$@")
  local min=${arr[0]}
  for v in "${arr[@]}"; do [ "$v" -lt "$min" ] && min=$v; done
  echo "$min"
}

if [ ${#cold_times[@]} -gt 0 ]; then
  echo ""
  echo "❄️ 冷启动:"
  echo "  平均值: $(calc_avg "${cold_times[@]}") ms"
  echo "  最小值: $(calc_min "${cold_times[@]}") ms"
  echo "  最大值: $(calc_max "${cold_times[@]}") ms"
  echo "  数据: ${cold_times[*]}"
fi

if [ ${#hot_times[@]} -gt 0 ]; then
  echo ""
  echo "🔥 热启动:"
  echo "  平均值: $(calc_avg "${hot_times[@]}") ms"
  echo "  最小值: $(calc_min "${hot_times[@]}") ms"
  echo "  最大值: $(calc_max "${hot_times[@]}") ms"
  echo "  数据: ${hot_times[*]}"
fi

echo ""
echo "═══════════════════════════════════════════════════"
