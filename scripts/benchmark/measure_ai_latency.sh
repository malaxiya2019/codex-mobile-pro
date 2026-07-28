#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# AI 请求延迟测量脚本
# 直接 curl 调用本地 mimo2codex 代理，测量首 Token / 完整响应延迟
# ──────────────────────────────────────────────────────────────
# 依赖: curl, jq (optional)
# 用法: bash scripts/benchmark/measure_ai_latency.sh [次数=10]
# ──────────────────────────────────────────────────────────────

set -euo pipefail

COUNT=${1:-10}
API_BASE="${API_BASE:-http://127.0.0.1:8788/v1}"
OUTPUT_DIR="build/benchmark"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/ai_latency_${TIMESTAMP}.txt"

mkdir -p "$OUTPUT_DIR"

echo "═══════════════════════════════════════════════════"
echo "  AI 请求延迟测量"
echo "  API: $API_BASE"
echo "  测试次数: $COUNT"
echo "  输出: $OUTPUT_FILE"
echo "═══════════════════════════════════════════════════"

# 检查代理是否运行
if ! curl -s "$API_BASE/health" > /dev/null 2>&1; then
  echo "⚠️  mimo2codex 代理未运行，尝试启动..."
  mimo2codex --model ds --port 8788 &
  sleep 3
  if ! curl -s "$API_BASE/health" > /dev/null 2>&1; then
    echo "❌ 代理启动失败，请手动启动后重试"
    exit 1
  fi
  echo "✅ 代理已启动"
fi

echo ""
echo "代理状态: $(curl -s "$API_BASE/health")"
echo ""

exec > >(tee "$OUTPUT_FILE") 2>&1

first_token_times=()
full_response_times=()
success_count=0
fail_count=0

for i in $(seq 1 "$COUNT"); do
  echo "─── 请求 $i ───"

  # 测量首 Token 延迟
  start=$(date +%s%3N)
  first_token=""
  full_content=""

  # 流式请求，直到收到第一个 data 或超时
  first_token_received=false
  while IFS= read -r line; do
    if [[ "$line" == data:* ]]; then
      if [ "$first_token_received" = false ]; then
        now=$(date +%s%3N)
        first_token_ms=$((now - start))
        first_token_times+=("$first_token_ms")
        first_token_received=true
        echo "  首 Token: ${first_token_ms}ms"
      fi
      if [[ "$line" == "data: [DONE]" ]]; then
        break
      fi
    fi
  done < <(curl -s -N -X POST "$API_BASE/chat/completions" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer dummy" \
    -d '{
      "model": "deepseek-chat",
      "messages": [{"role":"user","content":"用一句话回答：1+1=？"}],
      "stream": true,
      "max_tokens": 50
    }' 2>/dev/null || true)

  end=$(date +%s%3N)
  full_ms=$((end - start))
  full_response_times+=("$full_ms")

  if [ "$first_token_received" = true ]; then
    success_count=$((success_count + 1))
    echo "  完整响应: ${full_ms}ms ✅"
  else
    fail_count=$((fail_count + 1))
    echo "  ❌ 请求失败（无响应）"
  fi

  echo ""
  sleep 1
done

# ── 统计输出 ──
echo "═══════════════════════════════════════════════════"
echo "  测量结果统计"
echo "═══════════════════════════════════════════════════"
echo ""

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

total=$((success_count + fail_count))
success_rate=$(echo "scale=1; $success_count * 100 / $total" | bc 2>/dev/null || echo "N/A")

echo "📊 请求总数: $total"
echo "✅ 成功: $success_count"
echo "❌ 失败: $fail_count"
echo "📈 成功率: ${success_rate}%"

if [ ${#first_token_times[@]} -gt 0 ]; then
  echo ""
  echo "⏱️ 首 Token 延迟:"
  echo "  平均值: $(calc_avg "${first_token_times[@]}") ms"
  echo "  最小值: $(calc_min "${first_token_times[@]}") ms"
  echo "  最大值: $(calc_max "${first_token_times[@]}") ms"
  echo "  数据: ${first_token_times[*]}"
fi

if [ ${#full_response_times[@]} -gt 0 ]; then
  echo ""
  echo "⏱️ 完整响应延迟:"
  echo "  平均值: $(calc_avg "${full_response_times[@]}") ms"
  echo "  最小值: $(calc_min "${full_response_times[@]}") ms"
  echo "  最大值: $(calc_max "${full_response_times[@]}") ms"
  echo "  数据: ${full_response_times[*]}"
fi

echo ""
echo "═══ 数据已保存到: $OUTPUT_FILE ═══"
