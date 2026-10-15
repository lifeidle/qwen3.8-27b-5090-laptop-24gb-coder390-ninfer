#!/usr/bin/env python
"""bench_par_long.py -- N parallel requests, EACH carrying a ~32K-token long context.
Unique prefix per lane (no cache sharing) = honest cold-concurrency measurement.
Usage: python bench_par_long.py [n] [port] [max_tokens] [model]"""
import json, sys, threading, time, urllib.request

n = int(sys.argv[1]) if len(sys.argv) > 1 else 4
port = int(sys.argv[2]) if len(sys.argv) > 2 else 8083
max_tokens = int(sys.argv[3]) if len(sys.argv) > 3 else 384
model = sys.argv[4] if len(sys.argv) > 4 else "qwen3.8-27b-coder390-q2-q4mtp"

para = ("小镇的清晨总是从面包房的香气开始。老陈推开木门，把第一炉吐司摆上柜台，"
        "窗外的梧桐叶被风吹得沙沙作响。邮递员骑车经过，铃声惊起了屋檐下的鸽子。")
BODY = para * 565  # ≈ 49.7K chars ≈ 32K tokens
NEEDLE = "【重要暗号：紫罗兰在星期二会开出第七朵花。】"

results = [None] * n
def worker(i):
    prompt = (f"【第{i+1}路任务】" + BODY + "\n\n" + NEEDLE +
              f"\n\n上面的长文里藏了一个重要暗号。请复述暗号原文，然后回答：你是第几路任务？")
    body = json.dumps({"model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens, "stream": False}).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/chat/completions",
        data=body, headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.loads(r.read())
    results[i] = (time.time() - t0, d)

t0 = time.time()
threads = [threading.Thread(target=worker, args=(i,)) for i in range(n)]
for t in threads: t.start()
for t in threads: t.join()
wall = time.time() - t0

ok = [r for r in results if r]
tot_out = sum(r[1]["usage"]["completion_tokens"] for r in ok)
tot_in = sum(r[1]["usage"]["prompt_tokens"] for r in ok)
agg = tot_out / wall
prefills = [r[1]["timings"]["prompt_per_second"] for r in ok]
decodes = [r[1]["timings"]["predicted_per_second"] for r in ok]
cached = sum(r[1]["usage"].get("prompt_tokens_details", {}).get("cached_tokens", 0) for r in ok)
ta = sum(r[1]["timings"].get("draft_n_accepted") or 0 for r in ok)
td = sum(r[1]["timings"].get("draft_n") or 0 for r in ok)
mtp = ta / td * 100 if td else 0
recall = sum(1 for r in ok if "紫罗兰" in (r[1]["choices"][0]["message"]["content"] or ""))
pfs = " ".join(f"{x:.0f}" for x in sorted(prefills, reverse=True))
pds = " ".join(f"{x:.0f}" for x in sorted(decodes, reverse=True))
print(f"C{n} long-ctx | aggregate={agg:.1f} tok/s (out {tot_out} / wall {wall:.1f}s) | "
      f"per-req decode: {pds} | per-req prefill: {pfs} | "
      f"prompt_tok: {tot_in} cached: {cached} | MTP={mtp:.1f}% | recall {recall}/{n} | "
      f"perlane_max={max(decodes):.0f} perlane_min={min(decodes):.0f}")
