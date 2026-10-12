# Qwen3.8-27B · 单卡 24GB 极限调优实录

**把 TWIN-TURBO 调到 RTX 5090 Laptop 24GB 上的实际极限 —— 每一个数字都有对照组实测**

[English →](./README_EN.md) ｜ [工具脚本 →](./scripts) ｜ [原始数据 →](./data)

![Model](https://img.shields.io/badge/model-Qwen3.8--27B%20TWIN--TURBO-7c3aed)

![Platform](https://img.shields.io/badge/platform-RTX%205090%20Laptop%2024GB-76b900)



![Throughput](https://img.shields.io/badge/decode-74~78%20tok%2Fs-d97706)

![Context](https://img.shields.io/badge/context-160K%20max%20stable-2563eb)

![Engine](https://img.shields.io/badge/llama.cpp-b11223%20CUDA%2013.4-0ea5e9)

![License](https://img.shields.io/badge/license-MIT%20%2B%20CC%20BY%204.0-059669)

---

## 🥊 三大对决总览

| #     | 对决                                                | 最终答案                                                    |
| ----- | ------------------------------------------------- | ------------------------------------------------------- |
| **一** | **并发取舍**（10-12 定版）：单路满速 vs 多路吞吐，Q2 @ 262K 满窗 + 视觉 | **mc6 × d3**：聚合 272.9（峰值 316.3）、单路 76、262K 原生窗 + 288K 池 |
| **二** | **部署路线**：llama.cpp 原生 vs NInfer（WSL2 + Docker）    | 两条都可跑；NInfer 快 10-25%、llama.cpp 免 Docker                |
| **三** | **模型架构**：27B Dense vs Flash-Next 125B MoE         | 24GB 单卡 → **27B Dense 唯一正解**；Flash-Next 需双卡起步           |

---

## 🥊 对决一 · 并发取舍（2026-10-12 定版）：Q2 @ 262K 满窗 + 视觉

**模型换小、窗口开满、并发拉高**——Q2 LynnStyle（12.6 GiB）比 Q3 轻 3.8GB，这 3.8GB 在 262K 池下全部变成并发工作区：Q3 连 2 路都起不来，**Q2 一路爬到 7 路**。

### 定版配置与成绩

```bash
--max-context 262144 --kv-capacity 294912 --kv-dtype rk4v4 \
--max-concurrency 6 --spec mtp --draft-tokens 3 --vision
```

| 指标        |                                             数值 |
| --------- | ---------------------------------------------: |
| 聚合吞吐（6 路） |        **272.9 tok/s** 稳定 / **316.3 峰值**（历史最高） |
| 单发 decode |                                    80-83 tok/s |
| 并发时单路     |                                    59-76 tok/s |
| 上下文       | 262,144 原生满窗（池 294,912 = +32K 排队余量，天花板实测 288K） |
| MTP 接受率   |                            59-64%（d3）；d2 档 80% |
| 视觉        |                                    ✅ OCR 级图片理解 |

### 并发数怎么选（三轮会话验证，±5-9% 方差）

| 路数        |        聚合 |   单路峰值 | 适合                  |
| --------- | --------: | -----: | ------------------- |
| mc1       |  83.4（单发） |   83.4 | 极限单任务（无视觉可到 262K）   |
| mc2       |     137.9 | **87** | 双开，接近满速             |
| mc4       |     215.3 |     77 | 均衡                  |
| **mc6 ★** | **272.9** |     76 | **定版：总吞吐与单路体感的平衡点** |
| mc7       |     316.3 |     59 | 跑批极限（8 路带视觉全灭）      |

**三条硬规律**（48 格 + 21 格复测，三轮会话背书）：① MTP 接受率随草稿长度单调跌（d2 80% → d9 28-37%），**d5 以上是负资产**；② 每加一路 ≈ +0.5-1GB 工作区，mc7 是 262K+视觉的并发天花板；③ 池可超配到 288K（探针实测），但单请求仍封顶原生窗口 262,144。

![并发爬梯](assets/chart15-concurrency-ladder.svg)

![MTP接受率](assets/chart16-mtp-acceptance.svg)

### KV 格式对决：为什么选 rk4v4（FP4）

![KV格式](assets/chart17-kv-format.svg)

### KV 池天花板：288K（探针实测）

![池天花板](assets/chart18-pool-ceiling.svg)

完整记录（含 KV 格式对决、池探针、故障档案）→ [`data/q2-262k-tuning-log.md`](./data/q2-262k-tuning-log.md)

---

## 🥊 对决二 · 部署路线：llama.cpp 原生 vs NInfer（WSL2 + Docker）

同一块 24GB 卡，两代主力方案正面对决，全部数字为服务端计时口径：

| 指标         | TWIN-TURBO + llama.cpp（本页主角） | Coder390 Q3 LynnStyle + NInfer（新路线） |
| ---------- | ---------------------------: | ----------------------------------: |
| 单请求 decode |                  74-78 tok/s |            **84-86 tok/s**（+11~15%） |
| 单请求上下文     |                         160K |                     **262,144 满窗口** |
| 4 路并发聚合    |               ~110-120 tok/s |                     **227.7 tok/s** |
| prefill    |                 ~1,675 tok/s |                         1,395 tok/s |
| 满载惩罚（65K）  |                            重 |                           仅降 12-18% |
| 质量三联（官方全量） |                        无公开数据 |    **GPQA 173 / MMLU 449 / LCB 92** |
| 反「停不下来」    |                 思考 −93%（模型层） |                    94K 截断 13→3（模型层） |
| 部署         |                       ★ 双击即用 |             ★★★ WSL2 + Docker（官方镜像） |

- 📊 完整数据与选型建议 → [`data/ninfer-vs-turbo.md`](./data/ninfer-vs-turbo.md)
- 🔧 NInfer 部署实录（含 `finalizing target` 三连炸根因链、KV 格式实测单价、双 Profile 启动脚本）→ [`docs/ninfer-wsl2-deployment.md`](./docs/ninfer-wsl2-deployment.md)
- ⚙️ 脚本 → [`scripts/start-ninfer.sh`](./scripts/start-ninfer.sh) · [`scripts/bench-one.py`](./scripts/bench-one.py) · [`scripts/bench-par.py`](./scripts/bench-par.py)

一句话选型：**要省事、要视觉、双击即用 → llama.cpp 路线；要最快、要 262K、要真并发、不介意 Docker → NInfer 路线。** 两条路线端口互斥（8082/8083）可共存，随时切换。

---

## 🥊 对决三 · 模型架构：27B Dense（本仓主角）vs Flash-Next 125B MoE

同族两条架构路线：稠密 27B vs 125B MoE（512 专家，每 token 激活 ~6B）。Flash-Next 更聪明，但它的胃口是**双卡级**的。

|                   | **27B Dense**（本仓）                       | **Flash-Next 125B MoE**                    |
| ----------------- | --------------------------------------- | ------------------------------------------ |
| 权重                | 15.75-17.3 GB                           | Q2_0 **35.9 GiB** + n-gram 表 **26.8 GiB**  |
| 24GB 单卡笔记本        | ✅ 原生全 GPU + 视觉 + 6 路并发                  | ❌ 装不下；专家必须主机内存/磁盘流式                        |
| 桌面 5090 短答 decode | 236 tok/s（DFlash2 官方口径）                 | 136 tok/s（专家全 GPU，**需 2 卡**）               |
| 专家在主机内存           | —                                       | 74 tok/s（**−69%**）                         |
| 专家磁盘冷读            | —                                       | 25 tok/s（不可交互）                             |
| 质量                | Coder390：GPQA 87.4% / MMLU 449 / LCB 92 | Q2_0（双 5090）：**AIME 93.3%** / GPQA-D 86.4% |
| 定位                | 单卡性价比之王                                 | 多卡工作站的数学/推理特化                              |

**本仓结论**：24GB 约束下 27B Dense 是唯一能「全 GPU 常驻 + 视觉 + 多路并发」的路线。Flash-Next 的 6B 激活 MoE 在数学推理上确有上限优势（AIME 93.3%），但那需要第二张卡买单。详细数据 → [`data/dense-vs-flashnext.md`](./data/dense-vs-flashnext.md)

![dense-vs-moe](assets/chart19-dense-vs-moe.svg)

---

## 🏆 当前主力（双路线并列 · 按需切换）

### 🅝 路线 N：Coder390 Q2 + NInfer（2026-10-12 定版 · 日常默认 · 内网可访问）

桌面双击 **`启动本地大模型-内网8083.bat`**：自动拉起 Docker → 起容器 → 健康检查 → 打印内网地址（首次内网访问需在防火墙放行 8083）。等价命令：

```powershell
docker run -d --gpus all -p 8083:8080 --ulimit memlock=-1 --name ninfer-coder390 -v "D:\models\ninfer:/models" -v ninfer-cache:/cache ghcr.io/iamwavecut/ninfer-all:latest serve /models/Qwen3.8-27B-Coder390-EfficientThink-Q2LynnStyle-Q4MTP.ninfer --model-id qwen3.8-27b-coder390-q2-q4mtp --max-context 262144 --kv-capacity 294912 --kv-dtype rk4v4 --max-concurrency 6 --spec mtp --draft-tokens 3 --vision
```

| **6 路并发 × 262K 满窗** | 聚合 **272.9**（峰值 316.3） | 单路 59-76 | 视觉 OCR 级 | 内网 `:8083` |
| ------------------- | ---------------------- | -------- | -------- | ---------- |

> 端点：`http://<本机IP>:8083/v1/chat/completions` · model 名 `qwen3.8-27b-coder390-q2-q4mtp` · 停止：`docker rm -f ninfer-coder390`

### 🅣 路线 T：TWIN-TURBO + llama.cpp（前单卡王 · 免 Docker 备胎）

![当前主力配置](assets/chart12-champion-stack.svg)

**一行命令启动**（PowerShell 粘贴回车；关闭窗口即停止）：

```powershell
& "D:\llama-upstream-b11223\llama-server.exe" -m "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf" --mmproj "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf" -ngl 99 -fa on -fit off -c 163840 -np 1 --ctx-checkpoints 4 --load-mode none --jinja --cache-type-k q8_0 --cache-type-v q8_0 --spec-type draft-mtp --spec-draft-n-max 3 --reasoning-effort xhigh --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --host 127.0.0.1 --port 8082
```

### 这套方案解决了什么

| 问题              | 状态                                                                                      |
| --------------- | --------------------------------------------------------------------------------------- |
| **思考失控 / 过度思考** | ✅ **模型层修复 −93%**（失控 prompt：19,859 → 1,318 字符，31.7 秒给出 6,034 字符正文）——权重里直接训练掉了，不需要任何运行时补丁 |
| **精度**          | ✅ **全 Q8_0 链路**（输出头 + MTP 头 + KV cache 全部近无损量化），多轮长对话累积最稳                               |
| **长任务续航**       | ✅ 12 分钟满载 100 轮**零衰减**（78.7 → 83.7 tok/s，笔记本散热完全扛得住 agent 负载）                           |
| **视觉**          | ✅ 开启，**3.9 秒/张**（自量化的 q8_0 mmproj，质量与 BF16 无差）                                          |
| **速度**          | ✅ **74–78 tok/s** 解码（含视觉），MTP 草稿带来 ~1.8×                                                |
| **唯一牺牲：上下文**    | ⚠️ **封顶 160K** —— 显存悬崖实测在 ~180K（192K 直接 −25%），这是这台卡上"稳定跑"能换到的最大值                        |

> ⚠️ **刻意不用** `--reasoning-budget` 和 `--chat-template-file`：模型自带 10 种模式系统（5 reasoning + 5 instruct，einstein/spoon/xhigh…，聊天中实时切换），旧运行时补丁与它**冲突**（叠加后更慢、思考更多）。
>
> 📦 **需要下载的三件套**：① [esatapedico / TWIN-TURBO-NVFP4-GGUF](https://huggingface.co/esatapedico/Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-GGUF) 选 **MID-HIGH** 档（15.75 GB）· ② [mmproj](https://huggingface.co/Qwen/Qwen3.8-27B)（~0.9 GB，建议自量化成 Q8_0 = 600 MB）· ③ [llama.cpp b11223+ Windows CUDA 包](https://github.com/ggml-org/llama.cpp/releases)（主程序 + cudart 两个 zip）。国内把 `huggingface.co` 换成 `hf-mirror.com`。

---

## 📈 两组关键实测图

**① MTP 草稿深度：3 就是甜点**（2026-09-28 在 b11223 上复验）

![MTP草稿深度](assets/chart13-mtp-depth.svg)

**② 上下文悬崖：160K 是"稳定跑"的最大值**

![上下文悬崖](assets/chart14-ctx-cliff.svg)

- 非溢出区间内 ctx 大小**不影响速度**（152K-176K 全是 74-77 tok/s）
- **168-176K 是"刀锋边缘"**：同一命令不同启动，双峰 74.7 ↔ 55-59（显存 98% 满，是否溢出看碎片运气）——比匀速慢更糟的不可预测
- **184K 起真实掉速**（−12%，复测一致），**192K 起 −25%**（KV 溢出到内存）
- KV 成本实测 **43.97 KiB/token**；160K 的 KV ≈ 6.9 GiB，整卡账本 23.96/24.46 GiB

---

## 🎯 10 秒决策

| 你的场景                   | 选择                                                                                                                                  |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 日常对话 / 编码 / agent（要视觉） | **上面的一行命令** ✅                                                                                                                       |
| 需要灌 20 万+ tokens 大材料   | 备用配置：NVFP4-MTP-LOW + q4_0 KV + 262K（见 [data/context-scaling-history.md](data/context-scaling-history.md)）                           |
| 两个客户端同时用               | `-np 2`：第一条流无损、第二条 −17%、**总吞吐 +50%**，代价是每槽 80K（见 [data/2026-09-28-final-stack-tuning.md](data/2026-09-28-final-stack-tuning.md) §4） |
| 真正的 1M 交互              | 32GB+ 显存（vLLM 路线）                                                                                                                   |
| 思考停不下来                 | **TWIN-TURBO 已在模型层修复**（−93%），无需补丁                                                                                                   |

---

## 🔁 复现

```powershell
# 1. 引擎：llama.cpp 官方 Windows CUDA 包（主程序 + cudart 两个 zip 解压到同一目录），b11223 或更新
# 2. 模型：上方三件套（国内 hf-mirror.com 镜像）
# 3. 启动
.\scripts\start-twin-turbo-daily.ps1     # 或 README 顶部的一行命令
# 4. 验证
curl http://127.0.0.1:8082/health        # 期望 {"status":"ok"}
```

**验收基线**：384-token 生成 **74–78 tok/s**（服务端计时；±10% 波动来自 MTP 接受率的内容随机性）；prompt cache 命中后长输入秒级。

**测量纪律**（本项目所有数字的来源规则）：

1. 只读**服务端计时**（response `timings` / slot `print_timing`），不用客户端耗时差
2. 单发是噪声（同配置实测 50.6–79.4 都出现过）→ 结论必须**复测一致**
3. 扫参数必须**倒序复测端点**，排除热漂移假象（本轮"96K 最快 84"即被证伪）
4. 警惕"刀锋边缘"配置：同一配置多次启动出现双峰 → 不可预测 = 不可用

**测速与扫描脚本**：[`scripts/bench-parallel.py`](scripts/bench-parallel.py)（并发基准，读服务端 timings）· [`scripts/bench-mtp-sweep.ps1`](scripts/bench-mtp-sweep.ps1)（自适应扫参）· [`scripts/bench-ctx-fine.ps1`](scripts/bench-ctx-fine.ps1)（带倒序复测的 ctx 扫描）· [`scripts/start-tt-bench.ps1`](scripts/start-tt-bench.ps1)（参数化启动器）

---

## 🗄️ 归档：被否掉的方案（都有实测数据，点开看为什么）

<details>

<summary><b>❌ DFlash2 草稿（2026-09-28 测试）—— 微调模型上接受率仅 4%</b></summary>

官方有 Qwen3.8-27B 配套 DFlash2 草稿（[z-lab GGUF](https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2-GGUF)，llama.cpp 支持 PR [#27342](https://github.com/ggml-org/llama.cpp/pull/27342) 已合并）。实测：Q4_K_M 草稿 + n-max 7 + 160K，**25.2 tok/s（比 MTP 慢 67%），草稿接受率 4%**（2,059 个草稿只中 86）——草稿按官方原版训练，预测不了 TWIN-TURBO 大改微调的分布。MTP 快是因为用微调自带的 nextn 头。**跑官方原版时值得开，微调上别碰。**

</details>

<details>

<summary><b>❌ NVFP4-MTP-LOW（第 1–8 轮旧主力）—— 被 TWIN-TURBO 取代</b></summary>

三方量化对决的速度双冠（79.6 tok/s / 200K），但输出头 Q5_0 + IQ4_XS 精度低于 MID-HIGH 的全 Q8_0，且不带 TWIN-TURBO 的模型层思考修复。完整决策：\[data/tturbo-adoption.md\](data/tturbo-adoption.md)。262K + q4_0 KV 备用配置保留（见 10 秒决策表）。

</details>

<details>

<summary><b>❌ 192K+ 上下文 —— VRAM 溢出 −25%</b></summary>

184K 起掉 12%、192K 起 −25%、224K 一样。显存 98% 满后 KV 页被换出到内存。168-176K 刀锋双峰。唯一例外：旧 NVFP4-LOW 配置下 192K 曾可用（权重更小），TWIN-TURBO 的 15.75GB 权重让悬崖前移。

</details>


<details>  
<summary><b>❌ 运行时思考补丁（reasoning-budget + 模板注入）—— 与模型自带模式系统冲突</b></summary>  
TWIN-TURBO 在权重层把过度思考训练掉了（−93%），旧双保险叠加后反而更慢、思考更多 → 退役。历史修复思路（对未微调模型仍有效）：\[docs/xhigh-overthinking-fix.md\](docs/xhigh-overthinking-fix.md)、\[docs/reasoning-guide.md\](docs/reasoning-guide.md)  
</details>

<details>  
<summary><b>❌ 53 → 1 量化筛选中被排除的（IQ3_S / UD-Q4_K_S / SSMFIX / iMatrix 等）</b></summary>  
筛选漏斗与排除理由：<a href="#-筛选过程-53--1">原第 8 轮前记录</a> · iMatrix 混合量化（−27% 速度）：\[data/round2-new-results.md\](data/round2-new-results.md) · YaRN 1M（4-5 tok/s）与 262K 硬上限：\[docs/context-limits-and-yarn.md\](docs/context-limits-and-yarn.md)  
</details>

## 📜 十轮调优历程

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
| 9  | **引擎刷新（09-28）**  | **官方 b11146/b11223 CUDA 13.4**：MTP 草稿启用 CUDA 图（PR #28790 后又一白捡）——峰值持平、**下限抬升**（不再有 58-68 的谜之低谷）      |
| 10 | **终局微调（09-28）**  | MTP 深度复验（3 仍最优）· **DFlash2 否决**（接受率 4%）· 双流 +50% · **上下文悬崖测绘**：160K 定稿                               |

---

## ❓ FAQ

**Q：为什么不直接开 256K（模型原生最大）？**  
A：这台卡上 24GB 装不下 256K 的 KV 还保持速度——192K 就开始溢出（−25%）。160K 是"稳定跑"能换到的最大值。要灌 26 万 token 大材料用备用配置（q4_0 KV 的 NVFP4-MTP-LOW，见 10 秒决策）。

**Q：q8_0 KV 损失质量吗？**  
A：近无损。长文召回测试（12K/70% 与 150K/80% 深度）全部通过。

**Q：为什么不用 vLLM / SGLang？**  
A：Blackwell Laptop 上它们的显存管理与 GGUF 生态不如 llama.cpp 灵活，NVFP4 权重主要以 GGUF 分发。SGLang/vLLM 是 DFlash2 等"官方模型 + 服务端栈"组合的主场。

**Q：桌面版 5090 会快多少？**  
A：prefill 快 2–3 倍、decode 快 1.5–2 倍（575W vs 145W）。**容量结论（KV 量化、悬崖位置随权重体积平移）可参考方法自行复测。**

**Q：16GB 卡怎么办？**  
A：小档模型 + q8_0 KV + ~96K 上下文；或 IQ3_S（11.3GB）换容量。

**Q：可以同时跑多个实例吗？**  
A：装不下两个 27B。同实例内 `-np 2` 是正解（总吞吐 +50%）。

**Q：模型支持图像吗？**  
A：原生 VLM。`--mmproj` 加载（建议自量化 Q8_0 = 600 MB），额外 ~1GB 显存。**注意：视觉组件也占显存，是 ctx 悬崖的一部分。**

---

## 🔧 故障排查

| 症状                                       | 原因与解法                                                  |
| ---------------------------------------- | ------------------------------------------------------ |
| 启动即退出、日志无内容                              | 参数不兼容。新版引擎已移除 `--no-mmap`，用 `--load-mode none`         |
| `failed to allocate buffer for kv cache` | 上下文超出显存。降 `-c`                                         |
| 启动成功但推理卡死                                | 显存贴边（余量 <200 MiB）。降 8–16K 上下文                          |
| 同配置忽快忽慢（差 20%+）                          | 显存 98% 满的刀锋边缘。降 ctx 到有余量的档位                            |
| 生成全是思考、没有正文                              | 未传 `reasoning_effort`；默认 xhigh 会烧光 token               |
| 输出乱码                                     | 请求体未按 UTF-8 编码（写 JSON 文件 + `curl --data-binary @file`） |

---

## 📚 完整数据与文档索引（归档区）

### 历史记录（`data/`）

| 文件                                                                                                                                              | 内容                                                |
| ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| [2026-09-28-final-stack-tuning.md](data/2026-09-28-final-stack-tuning.md)                                                                       | **第 9-10 轮**：引擎刷新 / MTP 复验 / DFlash2 / 双流 / 上下文悬崖 |
| [tturbo-adoption.md](data/tturbo-adoption.md)                                                                                                   | **第 8 轮**：换模决策（NInfer / Bonsai 为什么落选）             |
| [nmax-3-vs-4-comparison.md](data/nmax-3-vs-4-comparison.md)                                                                                     | MTP 深度严格对比（交叉设计）                                  |
| [context-scaling-history.md](data/context-scaling-history.md)                                                                                   | 上下文探索全史：88K → 256K                                |
| [final-benchmark.md](data/final-benchmark.md)                                                                                                   | 最终配置基准（8 轮稳定性 / TTFT / 视觉）                        |
| [speed-results.md](data/speed-results.md) ｜ [round2-new-results.md](data/round2-new-results.md) ｜ [round3-6-latest.md](data/round3-6-latest.md) | 第 1–6 轮原始数据                                       |
| [thermal-stress-12min-100rounds.txt](data/thermal-stress-12min-100rounds.txt)                                                                   | 12 分钟满载散热原始日志                                     |

### 技术文档（`docs/`）

| 文件                                                                                                            | 内容                         |
| ------------------------------------------------------------------------------------------------------------- | -------------------------- |
| [context-limits-and-yarn.md](docs/context-limits-and-yarn.md)                                                 | 262K 硬上限 / q4_0 / YaRN 真相  |
| [windows-self-build-recipe.md](docs/windows-self-build-recipe.md)（[EN](docs/windows-self-build-recipe.en.md)） | 自编译配方（现用官方预编译，此配方保留备用）     |
| [custom-build-and-mtp-bug.md](docs/custom-build-and-mtp-bug.md)                                               | 自编译四坑 + MTP prefill bug 定位 |
| [reasoning-guide.md](docs/reasoning-guide.md) ｜ [xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md)   | 思考控制（对未微调模型仍有效）            |
| [vision-setup.md](docs/vision-setup.md)                                                                       | 视觉配置与 mmproj 自量化           |
| [ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md)                                                                 | 致谢与引用来源                    |

### 历史图表（`assets/`）

chart1-chart11（速度对决 / 上下文容量 / 散热 / 筛选漏斗 / 构建对比 / 参数红黑榜等）保留在 [assets/](./assets)，生成脚本在 [tools/](./tools)。

---

## 许可与法律

| 内容                               | 许可              |
| -------------------------------- | --------------- |
| 脚本代码（`scripts/`、`tools/`）        | **MIT License** |
| 文档与数据（README、`docs/`、`data/`、图表） | **CC BY 4.0**   |

第三方：Qwen3.8-27B 权重 **Apache 2.0**（[Qwen 官方](https://huggingface.co/Qwen/Qwen3.8-27B)）· TWIN-TURBO GGUF 见其模型卡（[esatapedico](https://huggingface.co/esatapedico)）· llama.cpp **MIT** · CUDA 按 NVIDIA 许可。**本仓库不含任何模型权重**，使用者自行从原始来源获取。免责与商标声明见 [LICENSE](LICENSE) 与 [docs/ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md)。

## 致谢

**Alibaba / Qwen 团队**（基座）· **DavidAU**（TWIN-TURBO 思考修复调教）· **esatapedico**（NVFP4 GGUF 家族）· **unsloth / DASLab**（量化方法）· **llama.cpp 社区**（引擎、MTP、CUDA graphs）· **z-lab / NVIDIA**（DFlash2 —— 虽然在本项目被否，但方法本身值得尊敬）
