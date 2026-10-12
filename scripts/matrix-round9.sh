#!/usr/bin/env bash
# matrix-round9.sh -- acceptance-aware sweep: mc 2..7 x draft 2..9 (48 cells)
# Q2 @ 262K pool + vision + rk4v4 + MTP. CSV: mc,draft,status,aggregate,perlane_max,mtp_pct,perlane_all
set -u
export PATH="$LOCALAPPDATA/Programs/DockerDesktop/resources/bin:$PATH"
export MSYS_NO_PATHCONV=1
MODEL="/models/Qwen3.8-27B-Coder390-EfficientThink-Q2LynnStyle-Q4MTP.ninfer"
MID="qwen3.8-27b-coder390-q2-q4mtp"
PY="/c/Users/chenhua/.workbuddy/binaries/python/versions/3.13.12/python.exe"
cd /c/Users/chenhua/Desktop/lifeidle/qwen3.8_27b/ninfer-coder390
OUT="matrix-mc2-7-d2-9-mtp.csv"
echo "mc,draft,status,aggregate,perlane_max,mtp_pct,perlane_all" > "$OUT"

cstate() { docker inspect -f '{{.State.Status}}' ninfer-coder390 2>/dev/null || echo "missing"; }

for MC in 2 3 4 5 6 7; do
  for D in 2 3 4 5 6 7 8 9; do
    docker rm -f ninfer-coder390 >/dev/null 2>&1
    docker run -d --gpus all -p 8083:8080 --ulimit memlock=-1 --name ninfer-coder390 \
      -v "D:/models/ninfer:/models" -v ninfer-cache:/cache \
      ghcr.io/iamwavecut/ninfer-all:latest serve "$MODEL" \
      --model-id "$MID" --max-context 262144 --kv-capacity 262144 --kv-dtype rk4v4 \
      --max-concurrency $MC --spec mtp --draft-tokens $D --vision >/dev/null 2>&1
    ST=$(cstate)
    if [ "$ST" != "running" ]; then
      echo "mc$MC d$D -> DOCKER_FAIL"
      echo "$MC,$D,DOCKER_FAIL,,,, " >> "$OUT"
      continue
    fi
    STATUS="FAIL"; AGG=""; PMAX=""; PALL=""; MTP=""
    for i in $(seq 1 40); do
      sleep 5
      ST=$(cstate)
      if [ "$ST" != "running" ]; then STATUS="FAIL"; break; fi
      L=$(docker logs ninfer-coder390 2>&1 | grep -E "engine ready|startup failed" | tail -1)
      case "$L" in
        *"engine ready"*)  STATUS="OK"; break ;;
        *"startup failed"*) STATUS="FAIL"; break ;;
      esac
    done
    if [ "$STATUS" = "OK" ]; then
      sleep 3
      LINE=$("$PY" bench_par.py $MC 8083 512 "$MID" 2>/dev/null | tail -1)
      echo "mc$MC d$D -> $LINE"
      AGG=$(echo "$LINE" | grep -oE "aggregate=[0-9.]+" | head -1 | cut -d= -f2)
      PALL=$(echo "$LINE" | grep -oE "per-req decode: [0-9 ]+" | sed 's/per-req decode: //' | xargs)
      PMAX=$(echo $PALL | awk '{m=0; for(i=1;i<=NF;i++) if($i+0>m) m=$i+0; print m}')
      MTP=$(echo "$LINE" | grep -oE "MTP=[0-9.]+%" | head -1 | cut -d= -f2 | tr -d %)
      echo "$MC,$D,$STATUS,$AGG,$PMAX,$MTP,$PALL" >> "$OUT"
    else
      echo "mc$MC d$D -> FAIL"
      echo "$MC,$D,$STATUS,,,," >> "$OUT"
    fi
  done
done
echo "MATRIX_DONE"
