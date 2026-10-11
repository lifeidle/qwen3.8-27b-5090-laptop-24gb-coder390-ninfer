#!/usr/bin/env bash
# start-ninfer.sh -- Run INSIDE WSL2 (or anywhere docker CLI reaches the engine).
# Usage: ./start-ninfer.sh [a|b]
#   a = Profile A 单王:  1 request, 262K context, ~86 tok/s   (default)
#   b = Profile B 并发:  4 requests, 131K context, agg ~228 tok/s
set -e
PROFILE="${1:-a}"

MODEL="$HOME/models/Qwen3.8-27B-Coder390-EfficientThink-Q3LynnStyle-Q4MTP.ninfer"
# Windows bind-mount variant (no WSL ext4 copy): D:\models\ninfer
MODEL_WIN="/models/Qwen3.8-27B-Coder390-EfficientThink-Q3LynnStyle-Q4MTP.ninfer"
M=""; [ -f "$MODEL" ] && M="$MODEL"
[ -z "$M" ] && [ -f "$MODEL_WIN" ] && M="$MODEL_WIN"
if [ -z "$M" ]; then echo "ERROR: model not found ($MODEL or $MODEL_WIN)"; exit 1; fi

CTX=262144; CONC=1
[ "$PROFILE" = "b" ] && { CTX=131072; CONC=4; }

docker rm -f ninfer-coder390 2>/dev/null || true

docker run -d \
  --gpus all \
  -p 8083:8080 \
  --ulimit memlock=-1 \
  --name ninfer-coder390 \
  -v "$HOME/models:/models" \
  -v ninfer-cache:/cache \
  ghcr.io/iamwavecut/ninfer-all:latest \
  serve "$M" \
  --model-id qwen3.8-27b-coder390-q3-q4mtp \
  --max-context $CTX \
  --kv-capacity $CTX \
  --kv-dtype rk4v4 \
  --max-concurrency $CONC \
  --spec mtp --draft-tokens 3

echo ""
echo "=== started (Profile $PROFILE: ctx=$CTX concurrency=$CONC) ==="
echo "  endpoint : http://127.0.0.1:8083/v1/chat/completions"
echo "  health   : curl -sf http://127.0.0.1:8083/health"
echo "  stats    : curl -s http://127.0.0.1:8083/stats"
echo "  logs     : docker logs -f ninfer-coder390"
echo "  stop     : docker rm -f ninfer-coder390"
