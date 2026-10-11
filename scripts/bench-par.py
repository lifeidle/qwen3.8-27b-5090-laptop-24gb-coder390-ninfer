#!/usr/bin/env python
"""bench_par.py -- N parallel requests against ninfer; reports aggregate throughput.
Usage: python bench_par.py [n] [port] [max_tokens]
Server-side per-request timings + wall-clock aggregate (tokens/wall)."""
import json, sys, threading, time, urllib.request

n = int(sys.argv[1]) if len(sys.argv) > 1 else 4
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8083
max_tokens = int(sys.argv[3]) if len(sys.argv) > 3 else 512

prompts = [
    "写一个 Python 函数实现快速排序（快排），包含注释。",
    "写一个 Python 函数实现归并排序（merge sort），包含注释。",
    "写一个 Python 函数实现堆排序（heap sort），包含注释。",
    "写一个 Python 函数实现插入排序（insertion sort），包含注释。",
    "写一个 Python 函数实现基数排序（radix sort），包含注释。",
    "写一个 Python 函数实现希尔排序（shell sort），包含注释。",
    "写一个 Python 函数实现桶排序（bucket sort），包含注释。",
    "写一个 Python 函数实现计数排序（counting sort），包含注释。",
][:n]

results = [None] * n
def worker(i):
    body = json.dumps({"model": "qwen3.8-27b-coder390-q3-q4mtp",
        "messages": [{"role": "user", "content": prompts[i]}],
        "max_tokens": max_tokens, "stream": False}).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",
        data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=900) as r:
        d = json.loads(r.read())
    results[i] = (time.time() - t0, d)

t0 = time.time()
threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
for t in threads: t.start()
for t in threads: t.join()
wall = time.time() - t0

tot_out = sum(r[1]["usage"]["completion_tokens"] for r in results if r)
decodes = [r[1]["timings"]["predicted_per_second"] for r in results if r]
agg = tot_out / wall
print(f"C{n} parallel={n} | aggregate={agg:.1f} tok/s (out {tot_out} tok / wall {wall:.1f}s) | "
      f"per-req decode: {' '.join(f'{x:.0f}' for x in sorted(decodes, reverse=True))} | "
      f"max_tokens_cap={max_tokens}")
