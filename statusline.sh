#!/bin/bash
# Claude Code statusLine: model · % context · effort · git branch · tokens · session cost
export LC_ALL=C
input=$(cat)

MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // "?"')
IN=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0')
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0 | round')
COST=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // 0')
WIN=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // 0')
EFFORT=$(printf '%s' "$input" | jq -r '.effort.level // ""')
DIR=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // "."')

# 15500 -> 15.5k, 1200000 -> 1.2M, <1000 as-is
fmt() { awk -v n="$1" 'BEGIN{ if(n>=1000000) printf "%.1fM",n/1000000; else if(n>=1000) printf "%.1fk",n/1000; else printf "%d",n }'; }
IN=$(fmt "$IN")
OUT=$(fmt "$OUT")

# context window: 200000 -> 200k, 1000000 -> 1M (no decimals)
WINLABEL=""
[ "$WIN" -gt 0 ] 2>/dev/null && WINLABEL=" $(awk -v n="$WIN" 'BEGIN{ if(n>=1000000) printf "%gM",n/1000000; else printf "%gk",n/1000 }')"

BRANCH=$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
GIT=""
[ -n "$BRANCH" ] && GIT=" | git:$BRANCH"

EFF=""
[ -n "$EFFORT" ] && EFF=" | eff:$EFFORT"

COST_FMT=$(printf '%.2f' "$COST")

printf '[%s%s | %s%%%s]%s | in:%s out:%s | $%s\n' "$MODEL" "$WINLABEL" "$PCT" "$EFF" "$GIT" "$IN" "$OUT" "$COST_FMT"
