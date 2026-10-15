# Qwen3.8 · RTX 5090 Laptop 24GB 极限实录

**Qwen3.8 家族在这块 24GB 笔记本卡上的完整对决与定版 —— 27B Dense 双引擎路线，3 路并发 × 262K 满窗，短文并发 194.8 tok/s，每个数字都是服务端计时实测**

[English →](./README_EN.md) ｜ [工具脚本 →](./scripts) ｜ [原始数据 →](./data)

![Model](https://img.shields.io/badge/model-Coder390%20Q2%20LynnStyle-7c3aed) ![Platform](https://img.shields.io/badge/platform-RTX%205090%20Laptop%2024GB-76b900) ![Aggregate](https://img.shields.io/badge/aggregate-192.2~194.8%20short-par-d97706) ![Context](https://img.shields.io/badge/context-262K%20×%203路-2563eb) ![Vision](https://img.shields.io/badge/vision-OCR%20级常驻-059669) ![Engine](https://img.shields.io/badge/NInfer--all%200.12-WSL2%20%2B%20Docker-0ea5e9) ![Alt](https://img.shields.io/badge/备胎-llama.cpp%20b11223%20%2B%20TWIN--TURBO-6b7280) ![License](https://img.shields.io/badge/license-MIT%20%2B%20CC%20BY%204.0-059669)

---

## 🥊 三大对决总览

| # | 对决 | 最终答案 |
|---|---|---|
| **一** | **并发取舍**（10-12 定版）：单路满速 vs 多路吞吐，Q2 @ 262K 满窗 + 视觉 | **mc3 × d3 + 360K 池**：短文并发 192.2-194.8、稳态解码 126.5、单发 92.7-100.4 |
| **二** | **部署路线**：llama.cpp 原生 vs NInfer（WSL2 + Docker） | 两条都可跑；NInfer 快 10-25%、llama.cpp 免 Docker |
| **三** | **模型架构**：27B Dense vs Flash-Next 125B MoE | 24GB 单卡 → **27B Dense 唯一正解**；Flash-Next 需双卡起步 |

---

## 🥊 对决一 · 并发取舍（2026-10-12 定版）：Q2 @ 262K 满窗 + 视觉

**模型换小、窗口开满、并发拉高**——Q2 LynnStyle（12.6 GiB）比 Q3 轻 3.8GB，这 3.8GB 在 262K 池下全部变成并发工作区：Q3 连 2 路都起不来，**Q2 一路爬到 7 路**。

### 定版配置与成绩

```bash
--max-context 262144 --kv-capacity 360000 --kv-dtype rk4v4 \
--max-concurrency 3 --spec mtp --draft-tokens 3 --vision
```

| 指标 | 数值 |
|---|---:|
| 聚合吞吐（3 路短文并发，两批） | **192.2 / 194.8 tok/s**（稳态解码 126.5） |
| 单发 decode | 80-83 tok/s |
| 并发时单路 | 59-76 tok/s |
| 上下文 | 262,144 原生满窗（池 360,000 = mc3 探针天花板，排队余量 ~98K） |
| MTP 接受率 | 48.7-61.0%（d3）；d2 档 53-65% |
| 视觉 | ✅ OCR 级图片理解 |

### 并发数怎么选（三轮会话验证，±5-9% 方差）

| 路数 | 聚合 | 单路峰值 | 适合 |
|---|---:|---:|---|
| mc1 | 83.4（单发） | 83.4 | 极限单任务（无视觉可到 262K） |
| mc2 | 137.9 | **87** | 双开，接近满速 |
| mc4 | 215.3 | 77 | 均衡 |
| **mc3 ★** | **192.2 / 194.8**（两批） | 68-74（稳态 46-63） | **定版：3 路多任务，体感与吞吐平衡** |
| mc7 | 316.3 | 59 | 跑批极限（8 路带视觉全灭） |

**三条硬规律**（48 格 + 21 格复测，三轮会话背书）：① MTP 接受率随草稿长度单调跌（d2 80% → d9 28-37%），**d5 以上是负资产**；② 每加一路 ≈ +0.5-1GB 工作区，mc7 是 262K+视觉的并发天花板；③ 池可超配到 288K（探针实测），但单请求仍封顶原生窗口 262,144。

| 并发爬梯（聚合 + 单路峰值） | MTP 接受率 vs 草稿长度 |
|---|---|
| ![并发爬梯](assets/chart15-concurrency-ladder.svg) | ![MTP接受率](assets/chart16-mtp-acceptance.svg) |

### KV 格式对决：为什么选 rk4v4（FP4）

| KV 格式对决（rk4v4 胜出） | KV 池天花板（mc6 实测 288K） |
|---|---|
| ![KV格式](assets/chart17-kv-format.svg) | ![池天花板](assets/chart18-pool-ceiling.svg) |

完整记录（含故障档案）→ [`data/q2-262k-tuning-log.md`](./data/q2-262k-tuning-log.md)

---

## 🥊 对决二 · 部署路线：llama.cpp 原生 vs NInfer（WSL2 + Docker）

同一块 24GB 卡，两代主力方案正面对决，全部数字为服务端计时口径：

| metric | TWIN-TURBO + llama.cpp（备胎路线） | Coder390 Q2 + NInfer（定版路线） |
|---|---:|---:|
| 单发 decode | 74-78 tok/s | **80-83 tok/s** |
| 并发单路峰值 | 73 | **76-100（长文首路）/ 95（mc2 × d7）** |
| 聚合（多路） | ~115（np2） | **192-195（3 路短文）** |
| 上下文 | 160K | **262,144 原生满窗** |
| 部署 | ★ 双击即用 | ★★★ WSL2 + Docker（官方镜像） |
| 质量 | 无公开三联 | GPQA 87.4% / MMLU 449 / LCB 92 |

- 📊 完整数据与选型建议 → [`data/ninfer-vs-turbo.md`](./data/ninfer-vs-turbo.md)
- 🔧 NInfer 部署实录（含 `finalizing target` 三连炸根因链、KV 格式实测单价、池天花板探针）→ [`docs/ninfer-wsl2-deployment.md`](./docs/ninfer-wsl2-deployment.md)

一句话选型：**要省事、要视觉、双击即用 → llama.cpp 路线；要最快、要 262K、要真并发、不介意 Docker → NInfer 路线。** 两条路线端口互斥（8082/8083）可共存，随时切换。

---

## 🥊 对决三 · 模型架构：27B Dense（本仓主角）vs Flash-Next 125B MoE

同族两条架构路线：稠密 27B vs 125B MoE（512 专家，每 token 激活 ~6B）。Flash-Next 更聪明，但它的胃口是**双卡级**的。

| | **27B Dense**（本仓） | **Flash-Next 125B MoE** |
|---|---|---|
| 权重 | 15.75-17.3 GB | Q2_0 **35.9 GiB** + n-gram 表 **26.8 GiB** |
| 24GB 单卡笔记本 | ✅ 原生全 GPU + 视觉 + 6 路并发 | ❌ 装不下；专家必须主机内存/磁盘流式 |
| 桌面 5090 短答 decode | 236 tok/s（DFlash2 官方口径） | 136 tok/s（专家全 GPU，**需 2 卡**） |
| 专家在主机内存 | — | 74 tok/s（**−69%**） |
| 专家磁盘冷读 | — | 25 tok/s（不可交互） |
| 质量 | Coder390：GPQA 87.4% / MMLU 449 / LCB 92 | Q2_0（双 5090）：**AIME 93.3%** / GPQA-D 86.4% |
| 定位 | 单卡性价比之王 | 多卡工作站的数学/推理特化 |

**本仓结论**：24GB 约束下 27B Dense 是唯一能「全 GPU 常驻 + 视觉 + 多路并发」的路线。Flash-Next 的 6B 激活 MoE 在数学推理上确有上限优势（AIME 93.3%），但那需要第二张卡买单。详细数据 → [`data/dense-vs-flashnext.md`](./data/dense-vs-flashnext.md)

![dense-vs-moe](assets/chart19-dense-vs-moe.svg)

---

## 🏆 当前主力（双路线并列 · 按需切换）

### 🅝 路线 N：Coder390 Q2 + NInfer（2026-10-12 定版 · 日常默认 · 内网可访问）

桌面双击 **`启动本地大模型-内网8083.bat`**：自动拉起 Docker → 起容器 → 健康检查 → 打印内网地址（首次内网访问需在防火墙放行 8083）。等价命令：

```powershell
docker run -d --gpus all -p 8083:8080 --ulimit memlock=-1 --name ninfer-coder390 -v "D:\models\ninfer:/models" -v ninfer-cache:/cache ghcr.io/iamwavecut/ninfer-all:latest serve /models/Qwen3.8-27B-Coder390-EfficientThink-Q2LynnStyle-Q4MTP.ninfer --model-id qwen3.8-27b-coder390-q2-q4mtp --max-context 262144 --kv-capacity 360000 --kv-dtype rk4v4 --max-concurrency 3 --spec mtp --draft-tokens 3 --vision
```

| **3 路并发 × 262K 满窗 + 360K 池** | 聚合 **272.9**（峰值 316.3） | 单路 59-76 | 视觉 OCR 级 | 内网 `:8083` |
|---|---|---|---|---|

> 端点：`http://<本机IP>:8083/v1/chat/completions` · model 名 `qwen3.8-27b-coder390-q2-q4mtp` · 停止：`docker rm -f ninfer-coder390`

### 🅣 路线 T：TWIN-TURBO + llama.cpp（备胎 · 免 Docker）

![前单卡王配置](assets/chart12-champion-stack.svg)

**一行命令启动**（PowerShell 粘贴回车；关闭窗口即停止）：

```powershell
& "D:\llama-upstream-b11223\llama-server.exe" -m "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf" --mmproj "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf" -ngl 99 -fa on -fit off -c 163840 -np 1 --ctx-checkpoints 4 --load-mode none --jinja --cache-type-k q8_0 --cache-type-v q8_0 --spec-type draft-mtp --spec-draft-n-max 3 --reasoning-effort xhigh --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --host 127.0.0.1 --port 8082
```

路线 T 规格速览：**74-78 tok/s** 解码（MTP ~1.8×）· 160K 稳定上下文 · 视觉 3.9 秒/张 · 思考 −93%（模型层修复）。深度调优记录见下方归档与 [data/tturbo-adoption.md](data/tturbo-adoption.md)。

> ⚠️ 路线 T 刻意不用 `--reasoning-budget` 与 `--chat-template-file`：模型自带 10 种模式系统，旧运行时补丁与其冲突。
>
> 📦 三件套：① [TWIN-TURBO NVFP4 MID-HIGH](https://huggingface.co/esatapedico/Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-GGUF)（15.75 GB）· ② [mmproj](https://huggingface.co/Qwen/Qwen3.8-27B)（建议自量化 Q8_0）· ③ [llama.cpp b11223+ Windows CUDA 包](https://github.com/ggml-org/llama.cpp/releases)。国内换 `hf-mirror.com`。

---

## 🎯 10 秒决策

| 你的场景 | 选择 |
| --- | --- |
| 日常使用 / 内网多端访问 | **桌面双击 `启动本地大模型-内网8083.bat`**（NInfer Q2 mc3 × d3）✅ |
| 跑批 / 多 agent 并行 | NInfer **mc7 × d3**（聚合 316.3，见对决一） |
| 单任务极限长文 | NInfer mc1 @ 262K（无视觉）；带视觉 mc1 @ 192K |
| 双开且每路要快 | mc2 × d2（单路 87、接受率 80.1%） |
| 免 Docker、双击即用 | 路线 T：TWIN-TURBO 一行命令（8082） |
| 灌 26 万 token 大材料 | Q2 262K 原生 ✅（T 路线用 q4_0 KV 备用配置，见归档） |
| 思考停不下来 | Coder390 / TWIN-TURBO 均已**模型层修复**，无需补丁 |

---

## 🔁 复现

```powershell
# ── 路线 N（NInfer · 默认）──
# 1. WSL2 + Docker Desktop + ghcr.io/iamwavecut/ninfer-all 镜像（见 docs/ninfer-wsl2-deployment.md）
# 2. 模型：nerkyor Q2LynnStyle-Q4MTP.ninfer（ModelScope / hf-mirror）
# 3. 启动
桌面双击「启动本地大模型-内网8083.bat」    # 或 scripts/start-ninfer-lan.bat
# 4. 验证
curl http://127.0.0.1:8083/health         # 期望 {"status":"ok"}

# ── 路线 T（llama.cpp · 备胎）──
.\scripts\start-twin-turbo-daily.ps1      # 验证 curl http://127.0.0.1:8082/health
```

**验收基线**：NInfer 路线单发 92.7-100.4 tok/s、3 路短文并发 192-195（服务端计时）；T 路线 74-78 tok/s。±10% 波动来自 MTP 接受率的内容随机性。

**测量纪律**（本项目所有数字的来源规则）：

1. 只读**服务端计时**（`timings` / `/stats`），不用客户端耗时差
2. 单发是噪声 → 结论必须**复测一致**；聚合结论至少两批
3. 跨会话对比不可靠（±10-31% 温控/时钟方差）→ 同会话内相对排序才可信
4. 「free 0 B」偏保守 → **真实边界必须探针实测**

**测速与扫描脚本**：[`scripts/bench-one.py`](scripts/bench-one.py)（单发，读服务端 timings）· [`scripts/bench-par.py`](scripts/bench-par.py)（并发基准 + MTP 接受率）· [`scripts/matrix-round9.sh`](scripts/matrix-round9.sh)（48 格矩阵自动跑批）· [`scripts/start-ninfer-lan.bat`](scripts/start-ninfer-lan.bat)（NInfer 双击启动器）

---

## 🗄️ 归档：被否掉的方案（都有实测数据，点开看为什么）

<details>

<summary><b>❌ DFlash2 草稿（2026-09-28 测试）—— 微调模型上接受率仅 4%</b></summary>

官方有 Qwen3.8-27B 配套 DFlash2 草稿（[z-lab GGUF](https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2-GGUF)，llama.cpp 支持 PR [#27342](https://github.com/ggml-org/llama.cpp/pull/27342) 已合并）。实测：Q4_K_M 草稿 + n-max 7 + 160K，**25.2 tok/s（比 MTP 慢 67%），草稿接受率 4%**（2,059 个草稿只中 86）——草稿按官方原版训练，预测不了 TWIN-TURBO 大改微调的分布。MTP 快是因为用微调自带的 nextn 头。**跑官方原版时值得开，微调上别碰。**

</details>

<details>  
<summary><b>❌ NVFP4-MTP-LOW（第 1–8 轮旧主力）—— 被 TWIN-TURBO 取代</b></summary>  
三方量化对决的速度双冠（79.6 tok/s / 200K），但输出头 Q5_0 + IQ4_XS 精度低于 MID-HIGH 的全 Q8_0，且不带 TWIN-TURBO 的模型层思考修复。完整决策：[data/tturbo-adoption.md](data/tturbo-adoption.md)。262K + q4_0 KV 备用配置保留（见 10 秒决策表）。  
</details>

<details>  
<summary><b>❌ 192K+ 上下文（T 路线）—— VRAM 溢出 −25%</b></summary>  
184K 起掉 12%、192K 起 −25%、224K 一样。显存 98% 满后 KV 页被换出到内存。168-176K 刀锋双峰。唯一例外：旧 NVFP4-LOW 配置下 192K 曾可用（权重更小），TWIN-TURBO 的 15.75GB 权重让悬崖前移。**NInfer + Q2 路线已突破此限：262K 满窗无悬崖（rk4v4 KV 19KB/token vs q8_0 26KB）。**  
</details>

<details>  
<summary><b>❌ 运行时思考补丁（reasoning-budget + 模板注入）—— 与模型自带模式系统冲突</b></summary>  
TWIN-TURBO 在权重层把过度思考训练掉了（−93%），旧双保险叠加后反而更慢、思考更多 → 退役。历史修复思路（对未微调模型仍有效）：[docs/xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md)、[docs/reasoning-guide.md](docs/reasoning-guide.md)  
</details>

<details>  
<summary><b>❌ 53 → 1 量化筛选中被排除的（IQ3_S / UD-Q4_K_S / SSMFIX / iMatrix 等）</b></summary>  
筛选漏斗与排除理由：<a href="#-筛选过程-53--1">原第 8 轮前记录</a> · iMatrix 混合量化（−27% 速度）：[data/round2-new-results.md](data/round2-new-results.md) · YaRN 1M（4-5 tok/s）与 262K 硬上限：[docs/context-limits-and-yarn.md](docs/context-limits-and-yarn.md)  
</details>

<details>  
<summary><b>❌ KV 格式 rk8v4（NInfer 路线）—— 慢 25% 且 MTP 接受率腰斩</b></summary>  
四种 KV 格式实测（Q2 @ 262K）：rk4v4 19KB/tok **84-86 tok/s、接受率 67-74%**；fp8 32.6KB 80.7；rk8v4 28.6KB 63.6 且接受率腰斩到 44%；bf16 52.7KB 只能开 ~64-96K 池。结论：**FP4 系（rk4v4）又快又省又稳**，单针捞针三格式全部一字不差。详见 [data/q2-262k-tuning-log.md](data/q2-262k-tuning-log.md) §4。  
</details>

## 📜 调优历程

| 轮次 | 主题               | 关键收获                                                                                                 |
| -- | ---------------- | ---------------------------------------------------------------------------------------------------- |
| 1  | **量化选型**（53 → 1） | NVFP4-LOW 胜出（速度双冠、质量打平）                                                                              |
| 2  | **KV + MTP 调优**  | MTP n-max 3（生成 +40%）                                                                                 |
| 3  | **思考控制**         | xhigh 修复：`--reasoning-budget` + 模板注入                                                                 |
| 4  | **自编译引擎**        | CUDA 13.3 官方配对：prefill +13% · 修复上游 bug（[#28790](https://github.com/ggml-org/llama.cpp/issues/28790)） |
| 5  | **上下文修正**        | `-np 1` 释放显存，150K → 180K                                                                             |
| 6  | **穷尽复查**         | 40+ 参数全排查                                                                                            |
| 7  | **上下文真相**        | q4_0 KV 让 256K 可用 · 静默封顶与 YaRN 真相                                                                    |
| 8  | **模型换代**         | **TWIN-TURBO MID-HIGH 转正**：思考 −93%、全 Q8_0、补丁退役                                                       |
| 9  | **引擎刷新（09-28）**  | 官方 b11146/b11223 CUDA 13.4：MTP 草稿启用 CUDA 图——峰值持平、**下限抬升**                                            |
| 10 | **终局微调（09-28）**  | MTP 深度复验（3 仍最优）· DFlash2 否决 · 双流 +50% · **上下文悬崖测绘**：160K 定稿                                          |
| 11 | **引擎换代（10-11）**  | **NInfer-all 进驻**（WSL2 + Docker）：262K 满窗、mc1-7 并发、视觉常驻、`finalizing` 故障链全部排明                        |
| 12 | **并发定版（10-12）**  | **Coder390 Q2 转正**：省 3.8GB 换 6 路 · 48+21 格矩阵 · KV 格式对决（rk4v4 胜）· 池天花板 288K · 接受率规律实证              |

---

## ❓ FAQ

**Q：上下文 262K 是输入还是输出？**  
A：**输入 + 输出共享**。一条请求的硬上限 = max-context，输入吃掉多少输出就剩多少；输出不固定，由 EOS / max_tokens 参数 / 剩余窗口三层控制。

**Q：Q2 量化这么狠（BPW 3.89），质量掉多少？**  
A：官方全量三联 GPQA 177（与 FP8 持平）/ MMLU 433（−16，广度受损）/ LCB 90（持平）。65K 深处捞针一字不差。要知识广度用 Q3（但 262K 下只有 1-2 路）。

**Q：为什么 mc7 是并发天花板？**  
A：每路 0.5-1GB 工作区（buffers + 草稿 KV + 状态），mc8 带视觉必爆；mc9 是引擎硬限制（1..8）。

**Q：T 路线为什么不直接开 256K？**  
A：llama.cpp + q8_0 KV（26KB/token）下 192K 就溢出（−25%），160K 是稳定值。NInfer + rk4v4（19KB/token）+ Q2 权重已突破此限：262K 满窗无悬崖。

**Q：q8_0 / rk4v4 KV 损失质量吗？**  
A：均近无损。长文召回测试全部通过（T 路线 12K/150K 深度；NInfer 路线 65K 深处捞针一字不差）。

**Q：为什么不用 vLLM / SGLang？**  
A：无 Windows 原生支持（WSL2 里还要再套一层），且 NInfer 的共享 KV 池并发效率实测更高（3 路 192-195 tok/s）。llama.cpp 则提供免 Docker 对照。

**Q：桌面版 5090 会快多少？**  
A：prefill 快 2–3 倍、decode 快 1.5–2 倍（575W vs 145W）。容量结论可参考方法自行复测。

**Q：16GB 卡怎么办？**  
A：路线 T 换小档模型 + q8_0 KV + ~96K；NInfer 路线换更小量化档（Q2 已是当前最小，更大卡才谈得上并发）。

**Q：可以同时跑两个实例吗？**  
A：装不下两个 27B。NInfer 单容器内 mc3 并发是正解（192-195 tok/s）；llama.cpp 路线 `-np 2`。

**Q：模型支持图像吗？**  
A：两路线都原生 VLM。NInfer：Q2 包内置视觉（`--vision`，OCR 级实测）；T 路线：`--mmproj` 加载（Q8_0 自量化 600MB）。视觉组件都占显存，是并发上限的一部分。

---

## 🔧 故障排查

### NInfer 路线

| 症状 | 原因与解法 |
| --- | --- |
| `startup failed \| finalizing target`（毫秒级） | KV 池 + 工作区超显存。**显式指定 `--kv-capacity`**（auto 不可靠）、降并发或降池；默认 KV 是 bf16（52.7KB/token）必爆 |
| mc8 / 高并发起不来 | 每路 0.5-1GB 工作区。降并发或降池（见 [data/q2-262k-tuning-log.md](data/q2-262k-tuning-log.md) §6） |
| mc9 报错退出 | 引擎硬限制 `--max-concurrency 1..8` |
| Docker 引擎起不来、卡「验证」 | Desktop 的 auth enforcer 连 hub.docker.com 超时（~30s+）才放行。只影响冷启动；根治 = WSL2 内直装 docker-ce |
| mc7 × d8/d9 起不来 | **长草稿也吃工作区**——高并发时草稿长度先降档 |
| 首启慢（路由校准 51s） | 设备 profile 存 /cache 卷；删卷会重校准 |

### T 路线（llama.cpp）

| 症状 | 原因与解法 |
| --- | --- |
| 启动即退出、日志无内容 | 参数不兼容。新版引擎已移除 `--no-mmap`，用 `--load-mode none` |
| `failed to allocate buffer for kv cache` | 上下文超出显存。降 `-c` |
| 同配置忽快忽慢（差 20%+） | 显存 98% 满的刀锋边缘。降 ctx 到有余量的档位 |
| 输出乱码 | 请求体未按 UTF-8 编码（写 JSON 文件 + `curl --data-binary @file`） |

---

## 📚 完整数据与文档索引

### 当前路线（2026-10-11 ~ 10-12）

| 文件 | 内容 |
| --- | --- |
| [data/ninfer-vs-turbo.md](data/ninfer-vs-turbo.md) | **对决二总表**：两路线正面对决（定版更新） |
| [data/q2-262k-tuning-log.md](data/q2-262k-tuning-log.md) | **对决一全记录**：Q2 @ 262K 调优（R5-R11，并发爬梯 / 48 格矩阵 / KV 对决 / 池探针） |
| [data/dense-vs-flashnext.md](data/dense-vs-flashnext.md) | **对决三**：27B Dense vs Flash-Next 125B MoE |
| [data/matrix-mc2-7-d2-9-mtp.csv](data/matrix-mc2-7-d2-9-mtp.csv) · [data/matrix-mc2-9-d2-9.csv](data/matrix-mc2-9-d2-9.csv) | 48 格 / 64 格原始矩阵数据 |
| [docs/ninfer-wsl2-deployment.md](docs/ninfer-wsl2-deployment.md) | NInfer WSL2 + Docker 部署实录与故障档案 |
| [scripts/start-ninfer-lan.bat](scripts/start-ninfer-lan.bat) | **双击启动器**（内网 8083） |
| [scripts/matrix-round9.sh](scripts/matrix-round9.sh) · [scripts/bench-par.py](scripts/bench-par.py) · [scripts/bench-one.py](scripts/bench-one.py) | 矩阵 / 并发 / 单发基准脚本（服务端计时） |

### 历史记录（T 路线 llama.cpp 时代，`data/`）

| 文件 | 内容 |
| --- | --- |
| [2026-09-28-final-stack-tuning.md](data/2026-09-28-final-stack-tuning.md) | **第 9-10 轮**：引擎刷新 / MTP 复验 / DFlash2 / 双流 / 上下文悬崖 |
| [tturbo-adoption.md](data/tturbo-adoption.md) | **第 8 轮**：换模决策（NInfer / Bonsai 为什么落选） |
| [nmax-3-vs-4-comparison.md](data/nmax-3-vs-4-comparison.md) | MTP 深度严格对比（交叉设计） |
| [context-scaling-history.md](data/context-scaling-history.md) | 上下文探索全史：88K → 256K |
| [final-benchmark.md](data/final-benchmark.md) | 最终配置基准（8 轮稳定性 / TTFT / 视觉） |
| [speed-results.md](data/speed-results.md) ｜ [round2-new-results.md](data/round2-new-results.md) ｜ [round3-6-latest.md](data/round3-6-latest.md) | 第 1–6 轮原始数据 |
| [thermal-stress-12min-100rounds.txt](data/thermal-stress-12min-100rounds.txt) | 12 分钟满载散热原始日志 |

### 技术文档（`docs/`）

| 文件 | 内容 |
| --- | --- |
| [ninfer-wsl2-deployment.md](docs/ninfer-wsl2-deployment.md) | NInfer WSL2 + Docker 部署与故障档案 |
| [dense-vs-flashnext.md（data/）](data/dense-vs-flashnext.md) | 架构对决（27B vs 125B MoE） |
| [context-limits-and-yarn.md](docs/context-limits-and-yarn.md) | 262K 硬上限 / q4_0 / YaRN 真相 |
| [xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md) · [reasoning-guide.md](docs/reasoning-guide.md) | 思考控制历史方案（对未微调模型仍有效） |

---

## 许可与法律

本仓库所有实测数据与文档按 **CC BY 4.0** 授权，脚本按 **MIT** 授权。Qwen3.8 系列模型权重遵循其原始许可证（Apache-2.0 / Qwen 许可）。

## 致谢

Qwen 团队（Qwen3.8 / Flash-Next 基座）· NInfer-all 与 llama.cpp 社区 · esatapedico（TWIN-TURBO NVFP4）· nerkyor（Coder390 后训练）· ISTA-DASLab（GSQ-RCO 量化）· 桌面与笔记本 5090 上所有先行者的公开实测。
