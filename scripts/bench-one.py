#!/usr/bin/env python
"""bench_one.py -- one timed request against ninfer-coder390; prints server-side timings.
Usage: python bench_one.py [port] [max_tokens] [prompt] [concurrent_note]
Reads ONLY server-reported timings (memory rule: no client-side stopwatch)."""
import json, sys, urllib.request

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8083
max_tokens = int(sys.argv[2]) if len(sys.argv) > 2 else 512
prompt = sys.argv[3] if len(sys.argv) > 3 else "写一个 Python 函数实现快速排序（快排），包含注释和简要说明。"
note = sys.argv[4] if len(sys.argv) > 4 else ""

body = json.dumps({
    "model": "qwen3.8-27b-coder390-q3-q4mtp",
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": max_tokens,
    "stream": False,
}).encode()

req = urllib.request.Request(
    f"http://127.0.0.1:{port}/v1/chat/completions",
    data=body, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req, timeout=600) as r:
    d = json.loads(r.read())

t = d.get("timings", {})
u = d.get("usage", {})
acc_n = t.get("draft_n_accepted"); dr_n = t.get("draft_n")
acc = f"{acc_n}/{dr_n} ({acc_n/dr_n*100:.1f}%)" if dr_n else "n/a"
print(f"{note}decode={t.get('predicted_per_second',0):.1f} tok/s | "
      f"prefill={t.get('prompt_per_second',0):.1f} tok/s | "
      f"TTFT={t.get('prompt_ms',0):.0f}ms | out={u.get('completion_tokens')} tok | "
      f"MTP={acc} | finish={d['choices'][0].get('finish_reason')}")
