#!/usr/bin/env bash
# matrix-round11.sh -- mc 2..4 x draft 2..5, long-context (32K/lane) benchmark. 12 cells.
# Q2 @ 262K window + 294,912 pool + vision + rk4v4 + MTP.
set -u
export PATH="$LOCALAPPDATA/Programs/DockerDesktop/resources/bin:$PATH"
export MSYS_NO_PATHCONV=1
MODEL="/models/Qwen3.8-27B-Coder390-EfficientThink-Q2LynnStyle-Q4MTP.ninfer"
MID="qwen3.8-27b-coder390-q2-q4mtp"
PY="/c/Users/chenhua/.workbuddy/binaries/python/versions/3.13.12/python.exe"
cd /c/Users/chenhua/Desktop/lifeidle/qwen3.8_27b/ninfer-coder390
OUT="matrix-long-mc234-d2345.csv"
echo "mc,draft,status,aggregate,perlane_max,perlane_min,mtp_pct,recall,prefill_mean,perlane_all" > "$OUT"

cstate() { docker inspect -f '{{.State.Status}}' ninfer-coder390 2>/dev/null || echo "missing"; }

for MC in 2 3 4; do
  for D in 2 3 4 5; do
    docker rm -f ninfer-coder390 >/dev/null 2>&1
    docker run -d --gpus all -p 8083:8080 --ulimit memlock=-1 --name ninfer-coder390 \
      -v "D:/models/ninfer:/models" -v ninfer-cache:/cache \
      ghcr.io/iamwavecut/ninfer-all:latest serve "$MODEL" \
      --model-id "$MID" --max-context 262144 --kv-capacity 294912 --kv-dtype rk4v4 \
      --max-concurrency $MC --spec mtp --draft-tokens $D --vision >/dev/null 2>&1
    ST=$(cstate)
    if [ "$ST" != "running" ]; then
      echo "mc$MC d$D -> DOCKER_FAIL"
      echo "$MC,$D,DOCKER_FAIL,,,,,,," >> "$OUT"
      continue
    fi
    STATUS="FAIL"; AGG=""; PMAX=""; PMIN=""; MTP=""; RECALL=""; PF=""; PALL=""
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
      LINE=$("$PY" bench_par_long.py $MC 8083 384 "$MID" 2>/dev/null | tail -1)
      echo "mc$MC d$D -> $LINE"
      AGG=$(echo "$LINE" | grep -oE "aggregate=[0-9.]+" | head -1 | cut -d= -f2)
      PALL=$(echo "$LINE" | grep -oE "per-req decode: [0-9 ]+" | sed 's/per-req decode: //' | xargs)
      PMAX=$(echo $PALL | awk '{m=0; for(i=1;i<=NF;i++) if($i+0>m) m=$i+0; print m}')
      PMIN=$(echo $PALL | awk '{m=$1; for(i=2;i<=NF;i++) if($i+0<m) m=$i+0; print m}')
      MTP=$(echo "$LINE" | grep -oE "MTP=[0-9.]+%" | head -1 | cut -d= -f2 | tr -d %)
      RECALL=$(echo "$LINE" | grep -oE "recall [0-9]/[0-9]" | awk '{print $2}')
      PF=$(echo "$LINE" | grep -oE "per-req prefill: [0-9 ]+" | sed 's/per-req prefill: //' | xargs)
      echo "$MC,$D,$STATUS,$AGG,$PMAX,$PMIN,$MTP,$RECALL,$PF,$PALL" >> "$OUT"
    else
      echo "mc$MC d$D -> FAIL"
      echo "$MC,$D,$STATUS,,,,,,," >> "$OUT"
    fi
  done
done
echo "MATRIX_DONE"
