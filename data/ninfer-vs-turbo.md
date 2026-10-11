# TWIN-TURBO vs Coder390 NInfer —— 两条路线的正面对决（2026-10-11）

> 同一块 RTX 5090 Laptop 24GB，两代主力方案，全部数字为服务端计时口径（无客户端秒表）。
> 原始部署步骤与全部踩坑见 [docs/ninfer-wsl2-deployment.md](../docs/ninfer-wsl2-deployment.md)。

**TL;DR (EN)**: New route (Coder390 Q3 LynnStyle `.ninfer` + NInfer-all engine in WSL2/Docker) beats the previous champion (TWIN-TURBO NVFP4 + native-Windows llama.cpp) on speed (+11-15%), context (262K vs 160K) and concurrency (C4 aggregate 228 vs ~115 tok/s), at the cost of a heavier deployment (Docker/WSL2 vs a single exe). Full numbers below.

## 一、两个方案是什么

| | 方案 T（旧主力） | 方案 N（新路线） |
|---|---|---|
| 模型 | Qwen3.8-27B **TWIN-TURBO** NVFP4 MID-HIGH（DavidAU 融合魔改，15.75GB） | Qwen3.8-27B **Coder390** Q3 LynnStyle Q4MTP（EfficientThink + 多轮 SFT/RLOO，16.1GiB `.ninfer`，视觉内置） |
| 训练卖点 | 思考 −93%（模型层）、去审查 | 治「94K 停不下来」（LCB 截断 13→3）、编码强化、GPQA/MMLU/LCB 全量实测 |
| 引擎 | **llama.cpp** b11223（Windows 原生 exe） | **NInfer-all** 0.12.0（C++/CUDA 自研，Docker 容器） |
| 运行环境 | **Windows 直接跑**（双击脚本，零沙箱） | **WSL2 + Docker Desktop**（官方镜像内置 sm_120a + CUDA 13.4） |
| 权重格式 | NVFP4 GGUF | `.ninfer` V3（NInfer 专有容器，GGUF 块免转换导入） |
| 投机解码 | MTP d3（74-78 tok/s，接受率 ~53%） | MTP d3（**86 tok/s**，接受率 **67-74%**） |
| KV | q8_0（26KB/token） | rk4v4（~19KB/token，9 种格式可选） |
| 上下文 | 160K（~180K 显存悬崖） | **262,144 原生满窗口** |
| 量化血统 | esatapedico NVFP4 六档阶梯 | LynnStyle 混合精度（最低 Q3，全家族 LCB 最高 92） |
| 许可 | 继承 Qwen（Apache-2.0 系） | Apache-2.0 |

## 二、本机实测对比（RTX 5090 Laptop 24GB）

| 指标 | TWIN-TURBO + llama.cpp | Coder390 + NInfer | 差距 |
|---|---:|---:|---:|
| 单请求 decode（空载） | 74-78 tok/s | **84-86 tok/s** | N +11~15% |
| 满载 decode（65K 上下文） | 满载惩罚重 | 70.5-75.4（仅降 12-18%） | N 强 |
| prefill | ~1,675 tok/s（自编译峰值口径） | 1,395 tok/s | T 略快，同量级 |
| 单请求上下文 | 160K | **262K** | N +64% |
| 并发聚合（4 路 512 tok 输出） | np2 ~110-120 tok/s | **227.7 tok/s** | N ~2× |
| MTP 接受率 | ~53% | 67-74% | N |
| 部署复杂度 | ★ 一个 exe + 两个下载件 | ★★★ WSL2 + Docker + 镜像 | T 完胜 |
| 质量三联（GPQA/MMLU/LCB） | 无公开全量 | **173 / 449 / 92**（官方全量，100K 协议） | N 有据可查 |
| 长文召回（65K 深处捞针） | 未测 | ✅ 一字不差，思考仅 255 tok 收尾 | — |
| 视觉 | ✅ 3.9s/张（q8_0 mmproj） | ✅ 内置（`--vision`，未在本机烟测） | 平 |

## 三、上下文 × 并发的真实交换率（24GB 显存预算）

KV 池必须 ≥ 单请求上限，每多一路并发约需 0.5-1GB 工作区——鱼与熊掌的明码价目：

| Profile | 上下文 | 并发 | 实测 | 适合 |
|---|---:|---:|---|---|
| **A 单王** | 262,144 | 1 | 86 tok/s | 单人重度使用、超长文档 |
| **B 并发** | 131,072 | 4 | 聚合 227.7（单路 64-69） | agent 并行、多人共用 |
| mc8（131K / 96K 池） | — | 8 | ❌ 起不来 | 24G + MTP 装不下 8 路工作区 |

## 四、draft-tokens 扫描（NInfer 路线，同题 512-token 输出）

| 草稿长度 | decode | 接受率 |
|---|---:|---:|
| d2 | 76.0 | 75.0% |
| **d3** | **84.1 / 86.4** | 66.9-73.6% |
| d4 | 71.3 / 80.3 | 52.8-56.3% |

与 TWIN-TURBO 时代的结论一致：**d3 就是甜点**。

## 五、怎么选

- **只想双击就能用、要视觉、要最简运维** → 方案 T（llama.cpp 原生），今天依然能打。
- **要最快速度、最长上下文、真并发，且不介意 Docker** → 方案 N（NInfer），数字全面领先。
- 两者**不互斥**：GPU 互斥但配置互不干扰（llama.cpp 8082 / NInfer 8083），随时切换。
- NInfer 路线的完整部署步骤、故障档案（`finalizing target` 三连炸的根因链）、KV 格式实测单价，见 [docs/ninfer-wsl2-deployment.md](../docs/ninfer-wsl2-deployment.md)。

## 六、口径说明（诚实条款）

- NInfer 侧全部数字取自服务端 `timings` 字段与引擎日志；llama.cpp 侧沿用本项目历史实测口径。
- 官方质量三联在 RTX PRO 6000 96GB / 100K 上下文协议测得，本机未复测三联；本机速度为 896GB/s 带宽笔记本卡，约为桌面 5090 的一半。
- 65K 针测试的 prompt 为重复段落 + 单针，非官方多针协议。
- 两模型训练目标不同（速度/去审查 vs 质量/编码），「更快」不等于「更合口味」，长期质量以日常使用为准。
