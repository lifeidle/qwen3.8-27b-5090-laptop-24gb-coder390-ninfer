# NInfer 路线部署实录：WSL2 + Docker 跑 Coder390（Windows 11 笔记本）

> 目标：在 RTX 5090 Laptop 24GB / Win11 上用官方 NInfer-all 引擎跑
> `Qwen3.8-27B-Coder390-EfficientThink-Q3LynnStyle-Q4MTP.ninfer`（16.1 GiB，视觉内置）。
> 实测结果与两模型对比见 [data/ninfer-vs-turbo.md](../data/ninfer-vs-turbo.md)。
> 2026-10-11 全程实录，含三次启动失败的完整根因链。

## 0. 为什么走 Docker 而不是 Windows 原生编译

| | A：WSL2 + Docker（推荐） | B：Windows 原生编译 |
|---|---|---|
| 并发/上下文 | 8 路引擎上限 / 262K | 相同（同一引擎同一显存） |
| 速度 | =官方数据口径 | 理论 +1~3%，无实测背书 |
| 坑 | 无 | **WDDM 把 pinned host memory 计入显存账**（官方文档原文） |
| 首次成本 | ~1 小时 | 1.5-2.5h+（VS 2026 + CUDA 13.1 + vcpkg/FFmpeg） |
| 升级 | `docker pull` 分钟级 | 重编 30-60 分钟/次 |
| 上游测试状态 | CI 逐 commit 构建 | 「无 Windows 测试主机、CI 不构建、未实测」 |

**结论：A 在全部硬指标上 ≥ B，可靠性完胜。**（NInfer-all 曾有 0 个 GitHub release，无预编译 Windows 包；ghcr.io 镜像每 commit 都构建。）

## 1. 部署步骤（用户侧需要提权/GUI 的部分）

1. WSL2：管理员 PowerShell `wsl --install` → 重启（Docker Desktop 自带 `docker-desktop` 发行版，**不需要**单独装 Ubuntu）。
2. Docker Desktop：装完在 Settings → Resources → WSL Integration 确认；个人使用免费。
3. 镜像：`docker pull ghcr.io/iamwavecut/ninfer-all:latest`（1.6GB 压缩，内含 sm_86/sm_120a 双构建，自动匹配 RTX 50 系；实测国内网络可直连 ghcr.io）。
4. 模型：`GGUF-NInfer/Qwen3.8-27B-Coder390-EfficientThink-Q3LynnStyle-Q4MTP.ninfer`（17,596,369,920 字节，SHA256 `f1d4e45f…322e`）。**选 Q4MTP 不选 Q8MTP**：主体权重逐字节相同（质量零差异），Q8 不更快（官方实测 66.0% vs 66.1%），只是引擎读不了 Q4 头时的备胎。视觉已内置，无需 mmproj。
5. 启动：`scripts/start-ninfer.sh a|b`（见 §3）。

## 2. 启动故障档案：`finalizing target` 三连炸的根因链

症状：`weights ready` 后 8-21ms 即 `ERROR startup failed | finalizing target`。二分定位过程（利用 OS 文件缓存，热重载仅 ~50s/轮）：

| # | 配置 | 结果 | 教训 |
|---|---|---|---|
| 1 | 262K + `--kv-capacity auto` + 默认 KV(bf16) + `--gdn-state-fp16` | ❌ | **默认 KV 是 bf16：52.7KB/token，262K 要 13.3GB**，必炸 |
| 2 | 262K + auto + rk4v4 | ❌ | auto 在大 max-context 下分配失败 |
| 3 | 102K + 池 819200 + rk8v4（照抄官方 96G 卡配方） | ❌ | **819,200 token 的池是 96GB 卡的量级**，24GB 照抄必炸 |
| 4 | 32K + 显式池 + bf16 | ✅ | 最小配置定位成功 |
| 5 | 32K + bf16 + MTP d3 | ✅ | MTP 无罪 |
| 6 | 262K + rk8v4 + auto | ❌ | 收窄到 auto |
| 7 | **262K + rk4v4 + 显式 `--kv-capacity 262144`** | ✅ | **正解** |

**三条铁律**：
1. `--kv-capacity` 必须显式指定，别用 auto（大上下文下不可靠）；
2. 池必须 ≥ `--max-context`，且为并发数留工作区（每路 ~0.5-1GB）；
3. 别照抄官方 96GB 卡的配方——KV 格式先换算单价（bf16 52.7 → rk8v4 ~26 → rk4v4 ~19 KB/token，均为本机实测）。

并发实测边界（本卡 + MTP）：mc4@262K ❌ → mc4@192K ❌ → **mc4@131K ✅（聚合 227.7 tok/s）** → mc8@131K/96K ❌。

## 3. 启动脚本（两个 Profile）

```bash
# Profile A 单王：262K × 1 路 × 86 tok/s
./start-ninfer.sh a
# Profile B 并发：131K × 4 路 × 聚合 227.7 tok/s
./start-ninfer.sh b
```

核心命令（Profile A）：

```bash
docker run -d --gpus all -p 8083:8080 --ulimit memlock=-1 \
  --name ninfer-coder390 \
  -v /path/to/models:/models -v ninfer-cache:/cache \
  ghcr.io/iamwavecut/ninfer-all:latest \
  serve /models/Qwen3.8-27B-Coder390-EfficientThink-Q3LynnStyle-Q4MTP.ninfer \
  --model-id qwen3.8-27b-coder390-q3-q4mtp \
  --max-context 262144 --kv-capacity 262144 --kv-dtype rk4v4 \
  --spec mtp --draft-tokens 3
```

- 端口 8083 避开 llama.cpp 路线的 8082（两套可共存，GPU 互斥而已）。
- 首启 51s 自动测卡建 device profile（67 路由键，存 /cache 卷；删卷会重校准）。
- 权重加载：Windows bind mount 冷 3m9s（~87-150MiB/s）/ 热 ~50s（328MiB/s）；进 WSL ext4 可更快。
- 加分项：`--model-suspend`（空闲还显存）、`--adaptive-mtp`、`--vision`（再占 ~0.9GiB）。
- 免重装 gh 的坑：Docker Desktop 装在 `%LOCALAPPDATA%\Programs\DockerDesktop`，docker CLI 不在旧会话 PATH；`docker pull` 报 `docker-credential-desktop not found` 时把其 bin 目录加进 PATH。

## 4. 基准方法与复现

- 单请求：`scripts/bench-one.py`（服务端 `timings` 字段口径，禁止客户端秒表——历史教训：API 往返差值会算出假速度）。
- 并发：`scripts/bench-par.py`（N 线程同时发，聚合 = 总输出 token / 墙钟）。
- 长文召回：重复段落 + 单针，65K token 灌入 46.8s（1,395 tok/s），针一字不差捞出，思考仅 255 token。
- 满载惩罚：65K 上下文 decode 70.5-75.4 tok/s（比空载仅降 12-18%）。

## 5. 与 llama.cpp 路线的关系

两条路线并存不互斥：llama.cpp（TWIN-TURBO，8082）一个 exe 双击即用；NInfer（Coder390，8083）要 Docker。性能数字 NInfer 全面领先（见对比文档），部署简单度 llama.cpp 胜。选型看你要省事还是要极限。
