# 排查记：一台 XPS13 的 Wi-Fi 频繁断网——从固件崩溃风暴到"聚合全关"的完整证据链

> 硬件：Dell XPS 13 L322X（2013，i7-3517U）/ Intel Dual Band Wireless-AC 7260
> 软件：Ubuntu 22.04 HWE，内核 6.8.0-138-generic，iwlwifi + iwlmvm（树内驱动），固件 iwlwifi-7260-17.ucode
> 对端：小米 AX6000（Wi-Fi 6，2.4G + 5G 双频）
> 时间线：10-03 崩溃开始 → 10-06~09 第一轮排查 → 10-10~11 第二轮排查（本文主体）。本文每一句结论性的话都标注了证据：`[1]~[6]` 为已存档的外部引用（`ref/` 目录），`〔证据: 文件名〕` 为本机日志导出（`ref/logs/` 目录），命令均可复现。

**TL;DR**：网卡固件（闭源 microcode）在处理 A-MPDU 聚合流量时触发 sysassert 自毁——`Microcode SW error detected`〔证据: microcode-sw-error-all.txt，3636 行〕；驱动侧的 `HW problem - can not stop rx aggregation` 是 mac80211 在驱动 AMPDU 操作回调失败时的标准报错〔3〕，属于固件死后的下游症状。该固件的上游仓库最后一次内容更新是 2018-10-03〔5〕，闭源且无源码可修。本机可用的软件解只有一个：**禁用 TX/RX 聚合**（`options iwlwifi 11n_disable=6`，按 `modinfo` 位定义 2+4）〔证据: modinfo-params.txt〕，实测吞吐从理论 867 Mbps〔1〕降到 ~74 Mbps，换取零崩溃。全文含完整 A/B 实验矩阵（九种配置）与一个对社区有普适价值的发现：Ubuntu HWE 头文件包的 BTF 配置残缺会让这台机器上**一切自编译内核模块无法加载**。

### 时间线总览：一场风暴，两轮排查

| 阶段 | 时间 | 动作 | 结果 |
|---|---|---|---|
| 风暴 | 10-03 起 | 机器闲置三年半后复用，断流频发，靠手动开关 Wi-Fi 抢救 | 10-04 峰值 ~2000 行崩溃日志/天（图 1） |
| 第一轮排查 | 10-06 ~ 10-09 | 软件参数轮番尝试（省电、bt_coex、11n_disable=8、swcrypto）均无效 → 判"卡坏"，购入**全新同型号 7260HMW** → 20 分钟 316 崩 → 10-09 做 AP 对照实验，归因反转 | 卡无罪；病在"**AX6000 × 7260 固件**"组合；转向 USB 网卡方案 |
| 第二轮排查（本文主体） | 10-10 ~ 10-11 | 发现被两轮漏掉的正确参数 **11n_disable=6**、死亡循环定量、九配置实验矩阵、Ubuntu 头文件 BTF 修复、自动兜底工具链 | 禁聚合 = 唯一可用解，74 Mbps 稳态 |

两轮排查方向不同（第一轮排硬件，第二轮做软件穷尽），互不知情，却从不同方向收敛到同一结论——这本身也是结论可信度的一部分。

---

## 一、起点：一句无出处的转述，和它唯一的可检验前提

第二轮排查启动时，手里的既有假设是设备使用者转述的一句话："网络经常崩掉，据说是因为网卡和小米路由器 6G 不兼容"——这句"据说"同样悬浮在第一轮排查的上空。这句转述**没有可追溯的出处**——本文不引用它，只处理它唯一的可检验前提：这块网卡与 6GHz 的关系。该前提可以且仅能被硬件事实判定：

```text
$ lspci -nn | grep -i network                     〔证据: ref/logs/lspci.txt〕
01:00.0 Network controller [0280]: Intel Corporation Wireless 7260 [8086:08b1] (rev 73)

$ iw phy                                          〔证据: ref/logs/iw-phy.txt〕
    Band 1:   (2.4 GHz)
    Band 2:   (5 GHz)                             ← 只有两个频段，无 6GHz
```

Intel 官方规格页对 AC 7260 的定义是 802.11ac 双频网卡，频段栏只有 2.4 GHz 与 5 GHz，最高速率 867 Mbps，全文无 6GHz〔1〕。作为对照，具备 6GHz 的 Intel 网卡（AX210）规格页明确标注 Wi-Fi 6E 与 6 GHz〔2〕。AC 7260 是 2013 年的网卡，物理上没有 6GHz 射频，与任何 6GHz 频段不可能发生交互。**该转述在本机不成立，依据仅此一条，且充分。**

这个对照同时划清了一个容易混淆的边界：`can not stop rx aggregation` 是 mac80211 的通用报错路径〔3〕，本机 7260 的崩溃现场打印了它〔证据: can-not-stop-rx-agg-all.txt〕，同一报错路径服务于所有驱动在所有 RX 聚合拆除失败场景下的输出〔3〕——报错字符串相同不代表病相同，必须回到各自的证据链。

## 二、崩溃风暴的时间线

固件崩溃的主签名：

```text
kernel: iwlwifi 0000:01:00.0: Microcode SW error detected.  Restarting 0x2000000.
kernel: iwlwifi 0000:01:00.0: Start IWL Error Log Dump:        (固件寄存器转储)
kernel: wlp1s0: HW problem - can not stop rx aggregation for a4:a9:30:e2:76:da tid 0/2/4/6
```

`journalctl -g 'Microcode SW error'` 全量统计：**3636 行**〔证据: microcode-sw-error-all.txt〕，按日分布见图 1 与 daily-crash-counts.txt：10/3=259，10/4=2023（峰值，≈每小时崩溃数十次），10/5=447，10/6=161，10/7=515，10/8=80，10/9=117，10/10=25，10/11=9。

![图1](article-figs/fig1-daily-crashes.png)

三个时间事实，各自有独立证据：

1. **崩溃始于 10/3——机器重新启用的当天**。本机启动历史显示 2023-02-01 之后到 2026-10-03 21:42 之间没有任何启动记录，10/3 晚开机后当天即出现崩溃〔证据: boot-history.txt + daily-crash-counts.txt〕；
2. **崩溃跨越内核版本**：10/3-10/5 期间机器运行 5.15 内核，10/5 后运行 6.8 内核，两侧都有崩溃〔证据: boot-history.txt 中内核版本列 + microcode-sw-error-all.txt〕——排除内核回归；
3. **诱因在本机日志不可分辨**：候选解释是"机器闲置三年半的老化"与"路由器侧的变更"两者之一或叠加——2021 年的短暂使用期内本机零崩溃记录（当时路由器型号不详），而现在的对端是 Wi-Fi 6 的 AX6000，其聚合行为与 AC 时代路由器不同。该问题保持开放，且不影响后文任何结论——结论只依赖"崩溃与聚合流量的剂量关系"（第六节）与"崩溃的 AP 归因"（第四节）。

**此处必须记录排查过程中的一个真实错误**：普查初期我写了 `journalctl -g -i '...'`，而 journalctl 没有 `-i` 选项（man page 全文可查〔6〕），命令静默失败返回空。我一度据此得出"38 次启动零固件错误"的错误结论。直到当日下午监控系统抓到实时崩溃，复查才发现检索命令本身是坏的。修正后的真实数字：`can not stop rx aggregation` 历史共 **992 行**〔证据: can-not-stop-rx-agg-all.txt〕。

> 教训一：检索工具静默失败产生的"零结果"是最危险的证据。任何"没查到"都要先用已知存在的样本验证命令本身。

## 三、其余断线事件的归因

一周内所有显性断线事件逐一归因后无悬案：

| 现象 | 归因 | 证据 |
|---|---|---|
| 断线"爆发"（某晚 6~10 次） | gnome-shell 的 rfkill Wi-Fi 开关（使用者手动抢救） | off→on 成对事件 20 条，携带 `audit: op="radio-control" ... uid=1000`，与断线时刻对齐〔证据: rfkill-user-toggles.txt〕 |
| 掉线后自动连到 2.4G 变慢 | NetworkManager 双 profile 同优先级（均为 0）按信号百分比择优 | 激活记录：HomeNet_5G 62 次 / HomeNet 16 次〔证据: nm-activation-counts.txt〕，与反复人工切回的行为一致 |
| 接口"消失又出现" | 手动 `modprobe -r iwlmvm iwlwifi`（前期调试动作） | sudo 审计日志 8 条原文〔证据: sudo-audit-debug-actions.txt〕 |
| 个别 reason=0 踢下线 | AP 侧发起（`CTRL-EVENT-DISCONNECTED` 无 `locally_generated=1` 标记） | 原始 wpa_supplicant 日志，随附录命令可复现 |

## 四、最关键的归因证据：崩溃 100% 集中于同一 AP

每条 `can not stop rx aggregation for <BSSID>` 都携带崩溃时所在 AP 的地址：

```text
$ journalctl -g 'can not stop rx aggregation for' | grep -oE 'for [0-9a-f:]{17}' | sort | uniq -c
    950 for a4:a9:30:e2:76:da    ← 小米路由 5G 电台
     42 for a4:a9:30:e2:76:d9    ← 小米路由 2.4G 电台        〔证据: bssid-attribution.txt〕
```

**992 次聚合失败 100% 发生在小米路由的两台电台上。** 同一张卡在工作日白天连接另一个 AP 组（00:be:75:*）期间，日志中仅有 PTK 重钥告警而无任何固件崩溃〔证据: ptk-rekey-warnings.txt + microcode-sw-error-all.txt 时刻交叉对照〕；同期另一 SSID（OfficeNet）有 9 次激活记录〔证据: nm-activation-counts.txt〕。因此本案的病是"**这张卡 + 这个 AP 的组合**"，不是"这张卡 + 聚合"的一般命题。AP 内部的聚合参数实现无法从客户端审查，归因止于 BSSID 层证据；这也意味着更换 AP 属于可尝试项，但其效果属于待验证项而非结论（第十一节的实验矩阵给出了本机侧的终局）。

### 支线：另一个 AP 上的另一种病

办公室 AP 组上出现过另一个指纹，13 条，全部指向同一 STA〔证据: ptk-rekey-warnings.txt〕：

```text
kernel: Rekeying PTK for STA 00:be:75:73:7b:e3 but driver can't safely do that.
```

其机制在内核源码 `net/mac80211/key.c` 第 337 行（`ieee80211_pairwise_rekey()`）：AP 发起不带 Extended Key ID 的 PTK 重钥，而驱动不具备 `NL80211_EXT_FEATURE_CAN_REPLACE_PTK0` 能力时，mac80211 污染旧钥、封锁聚合、拆除 BA 会话并降级运行〔4〕。该行为在本机实测出现 13 次、全部集中于该 STA〔证据: ptk-rekey-warnings.txt〕，与本文主线（固件 sysassert）是两种病，特此分列以免混淆。

#### 独立交叉验证：换一张全新同型号卡，崩照旧（2026-10-09 前序排查的受控实验）

第一轮排查做过一个**卡维度的受控实验**，恰好构成对上述 BSSID 归因的独立交叉验证：

- 第一轮曾判断"故障在卡内部"，并据此购入**全新同型号 Intel 7260HMW**（半高 mini-PCIe，正常安装识别）——带载测试 20 分钟仍崩 **316 次**（2026-10-07），"换卡"当场证伪；
- 2026-10-09 用同一张卡做 AP 对照：**连接 X1C 热点 10 分钟：0 崩溃；连接小米 AX6000 10 分钟：31~34 次崩溃**（同 ADVANCED_SYSASSERT 类）——排除"插槽/供电/主机侧"因素。

至此形成 2×2 矩阵：新旧两块卡 × 两个 AP，崩与不崩**完全由 AP 决定**，与卡无关。这也解释了使用者"买卡替换也没用、退货"的经历——全新同型号卡携带的仍是同一份有缺陷的固件。

## 五、受控压测方法

所有 A/B 对比使用同一脚本（`stress.sh`）：6 路并行下载（国内镜像源，总限速 ~340Mbps，强制绑定 `--interface wlp1s0`）+ 高频 TLS 握手，逐 0.5 秒采样吞吐与网关 RTT，`journalctl -f` 实时监听崩溃指纹。每轮只改一个变量。

> 实验纪律记录：中途曾因机器上并行插着 USB 网卡、默认路由偏移导致一轮压测流量完全走了另一块网卡，得出过一次虚假的"零崩溃"。此后所有流量测试强制绑定接口，并在拔除 USB 后复测关键结论。对照实验里"流量是否真的打到了被测对象"必须单独验证。

## 六、死亡循环：聚合开启 + 满载的实测形态

首轮压测（聚合开启）的 17 次崩溃真实时刻见图 2〔证据: death-loop-17-crashes.txt，17 条带秒级时间戳〕：

![图2](article-figs/fig2-death-loop.png)

- 90 秒内 17 次崩溃，相邻间隔全部 1~3 秒（中位 2 秒）；
- 每次崩溃后内核 `fw_restart`（`Restarting 0x2000000`）自动重启固件，约 1~2 秒恢复，聚合流量重建，立即再崩；
- 8 分钟窗口实际下载 ~0.1GB（限速下应得 ~20GB）；6 路下载被崩溃全部掐断后，崩溃同步停止——剂量-反应关系成立：**负载是触发条件，不是巧合**。

补充一个排除"卡老化/个体问题"的数据点：2026-10-07（本调查前），一块**全新同型号 7260HMW** 在同一路由下带载测试 20 分钟仍崩 316 次（见第四节交叉验证）——**崩的是固件版本，不是哪一块具体的卡**。

对应使用者体感：聚合开启时轻载可存活数小时（"偶尔崩一次"），重载从第 0 秒进入 2 秒周期死亡循环（"一用就崩"）。

## 七、机制：崩溃发生在哪一层，为什么修不了

- `Microcode SW error`（sysassert）是**卡上固件自毁**。iwlwifi 架构 = 主机 CPU 上的开源驱动 + 卡上处理器运行的闭源二进制固件（ucode）。错误日志转储（Error Log Dump）是固件死亡后驱动代为导出的卡内寄存器现场〔证据: microcode-sw-error-all.txt 中的 dump 段〕；
- 驱动侧 `HW problem - can not stop rx aggregation` 的触发点在内核源码 `net/mac80211/agg-rx.c` 第 91 行：mac80211 调用驱动 `ampdu_action` 回调请求拆除 RX 聚合、回调返回失败时打印〔3〕——固件已死，回调必然失败。**它是下游症状**；
- 该固件的上游仓库（linux-firmware）中 `iwlwifi-7260-17.ucode` 的全部历史为：2016-07-10 引入 -17 版本线，2017 年三次小更新，**2018-10-03 最后一次内容更新**，2025-08-28 仅随仓库目录重组移动位置〔5〕。闭源二进制 + 无后续维护 = "改驱动源码让固件不崩"没有落点；
- 连"降级避坑"也已实测失败：第一轮排查曾把固件从 -17 降到 -16，加载后网卡直接消失，重启恢复——旧版本同样不工作，此路不通。

驱动层能做的是两件事：用模块参数改变交付给固件的工作量（第八、十一节），或更换硬件。

## 八、参数止血：6 是禁聚合，8 是反的

本文第二轮排查的首个参数实验 `swcrypto=1`（软件加密）实测无效：生效 2 分钟后即再崩〔证据: microcode-sw-error-all.txt 中 2026-10-10 17:21:00 条目〕。

有效参数的位定义必须以本机 `modinfo` 为准〔证据: modinfo-params.txt〕：

```text
11n_disable:disable 11n functionality, bitmap: 1: full, 2: disable agg TX,
              4: disable agg RX, 8 enable agg TX (uint)
```

注意 **bit 8 = 启用 TX 聚合**。把 `11n_disable=8` 当作"禁聚合"是一个两轮排查先后踩进的坑——第一轮的无效参数清单里有它，本文实验矩阵第 3 列再次实测：加载后 1 秒内 2 崩。两轮都以为自己试过"禁聚合"，而正确答案 6 直到第二轮才出现。"只禁聚合、保留 11ac 高速率"的正确取值是 **2|4=6**：

```bash
# /etc/modprobe.d/iwlwifi-stability.conf
options iwlwifi swcrypto=1 11n_disable=6
```

效果（同款压测 A/B）：8 分钟 0 崩溃、2.91GB 下载、网关零丢包；6 分钟稳定性测速（3 路并行下载、0.5 秒采样）为均值 74 Mbps 的平线，波动系数 23%，零崩溃零丢包（图 4）〔证据: stab.log〕。

![图4](article-figs/fig4-stable-curve.png)

代价的量化：聚合（A-MPDU）是 Wi-Fi 摊薄空口开销的核心机制；禁用后吞吐三级台阶为 **867 Mbps（官方链路速率〔1〕）→ ~500 Mbps（典型聚合吞吐，本机因崩溃风暴未能实测）→ ~74 Mbps（禁聚合实测）**。对远程桌面（5~20Mbps 需求）无感，对大文件下载有感。

## 九、远程排障的兜底工程

排查主体在一台远程机器上进行（RustDesk/向日葵，10-10 深夜后使用者回到机器旁），"实验断网 = 人机失联"是真实约束（第十节会看到它真实发生了一次）。落地三层防护：

1. **wifi-watch**（用户级 systemd 服务）：监听崩溃指纹 + 3 秒网关探测，分级处置（刷 DNS → 重连 → 无线电开关），限流 6 次/小时，每次动作附日志快照。首日 4 次崩溃全部自动恢复〔证据: wifi-watch.log〕；
2. **wifi-safeguard**（root 级 timer，每 3 分钟）：网关持续 12 秒不可达才判死，逐级恢复：重载驱动 → 隔离实验模块恢复 stock → 强制写回稳定配置；
3. **按 AP 黑名单的聚合策略**（NetworkManager dispatcher）：连接建立时按 BSSID 前缀查黑名单，命中（小米）→ 禁聚合稳态，未命中 → 全速模式。开机/漫游/切换全覆盖。

## 十、源码支线：参数化补丁与 Ubuntu HWE 的 BTF 大坑

源码层仍有一个可调维度：驱动在关联时向 AP 广告的 **A-MPDU 尺寸上限与密度**。补丁为 6.8 的 iwlwifi 新增两个模块参数（`ampdu_len_exp_max`：A-MPDU 上限档位；`ampdu_density_min`：密度下限），DKMS 编译，一次构建后所有档位实验仅换参数重载。

这条支线产生了本案最具普适价值的发现——**Ubuntu 22.04 HWE 内核（6.8.0-138.138~22.04.1）的头文件包配置残缺，导致该机器上一切自编译模块无法加载**。症状与定位链：

```text
insmod: ERROR: could not insert module xxx.ko: Invalid module format
kernel: module xxx: .gnu.linkonce.this_module section size must match
        the kernel's built struct module size at run time
```

1. 二分：10 行的迷你测试模块同样被拒 → 与被编译的代码无关；
2. 段大小对比：stock 模块 this_module = 1280 字节，自编译 = 1216 字节；
3. 配置 diff（`/boot/config-$(uname -r)` vs 头文件 `.config`）〔证据: headers-config-diff-btf.txt〕：

```text
< CONFIG_DEBUG_INFO_BTF=y          ← 运行内核有
> (头文件配置缺失)
< CONFIG_PAHOLE_VERSION=125
> CONFIG_PAHOLE_VERSION=0          ← 头文件包的构建环境缺 pahole
```

根因：头文件包构建环境缺 pahole，BTF 配置被整体剔除；而 `struct module` 在 BTF 开启时更大，运行内核要求 1280 字节，残缺头文件产出 1216 字节，内核加载器一律拒绝。修复：`apt install dwarves` → 用 `/boot/config-*` 覆盖头文件 `.config`、补齐 `include/config/auto.conf` 的 BTF 符号 → root 执行 `make modules_prepare` 重新生成。此后 this_module = 1280，加载正常。

> 教训二：遇到 "this_module section size must match"，先 diff 头文件与 /boot 配置中的 BTF/PAHOLE 项，不要先怀疑自己的代码。

期间还发生了一次真实事故，如实记录：修复 BTF 前的某次模块重载失败导致内置网卡下线约 10 分钟，三层兜底中的 safeguard 当时因自身路径 bug 未能完成 B 级恢复（已修复），由使用者插入 USB 网卡救场。事故后补了两件事：safeguard 的模块定位改为 `updates/` 下递归查找；关键操作一律走"预武装定时器 + 自动回滚"脚本（`apply-*.sh` 模式）。

## 十一、实验矩阵：九种配置的穷尽

![图3](article-figs/fig3-matrix.png)

| 配置 | 结果 | 证据 |
|---|---|---|
| 原生聚合（7260 默认向 AP 广告 A-MPDU 上限 1MB） | 历史累计 992 次聚合失败 | bssid-attribution.txt |
| swcrypto=1（聚合开） | 90 秒 17 崩 | death-loop-17-crashes.txt |
| 11n_disable=8（= 强开 TX 聚合） | 加载后 1 秒 2 崩 | microcode-sw-error-all.txt 17:50:26/27 |
| **11n_disable=6（禁 TX+RX 聚合）** | **0 崩溃，74 Mbps 平线** | stab.log |
| 补丁钳制 32K / 16K | 不崩，传输停滞（32K 下 8000B 大包丢 33%） | stress.log（第 4b 轮）+ exp-small.log（16K 档） |
| 补丁钳制 64K / 8K | 崩溃 + 停滞 | exp-e1e2.log（64K，00:22:48/49 两崩）/ exp-small.log（8K，1 崩） |
| 密度=7（最大 MPDU 间隔，全尺寸） | 崩溃 + 停滞 | exp-small.log（3 崩） |
| 拔除 USB 网卡后复测聚合原生 | 停滞 + 2 崩（排除双网卡干扰） | exp-nousb.log |

结论：**在本组合（AC 7260 固件 × 该 AP）下，聚合开启的全部可调形态——五档尺寸（8K/16K/32K/64K/1MB）×密度维度——无一可用**。"聚合全关"不是众多选项中的一个，而是穷尽后的唯一解。

## 十二、结论

**因果链**：AC 7260 的 EOL 固件（上游最后更新 2018-10-03〔5〕）× 特定 AP（小米 AX6000）的聚合流量 → 固件 sysassert（`Microcode SW error`）→ mac80211 清理时打印 `can not stop rx aggregation`〔3〕→ 断流 → 手动开关 Wi-Fi（重新关联）暂时缓解 → 负载回归则复发（死亡循环，图 2）。

这条因果链有两轮独立排查的支撑：第一轮用"换卡 + 换 AP"的对照实验排除了硬件与插槽；第二轮用参数穷尽和九配置实验矩阵锁死了软件侧的边界。两个方向、两份记录，收敛于同一定论。

**定版方案**：

```bash
# /etc/modprobe.d/iwlwifi-stability.conf
options iwlwifi swcrypto=1 11n_disable=6    # 关键位 6 = 禁 TX+RX 聚合；swcrypto 对崩溃无效，保留无害
```

外加三层自动兜底（第九节）。长期升级路径：USB 网卡（MT7921AU 方案，内核 mt7921u 原生支持、驱动仍在活跃维护；前序排查已审核过该路线）。注意**内置卡替换路线已被实验否定**——全新同型号 7260HMW 实测照样崩（第四节），再买同型号卡毫无意义。7260 的固件不会再有修复版本〔5〕。

### 给遇到同类问题者的自查清单（每步都有对应的证据文件）

1. `lspci` + `iw phy` + Intel ARK 规格页：确认网卡世代与频段〔1〕〔2〕——"6GHz 兼容"话题只适用于具备 6GHz 的硬件；
2. `journalctl -g 'Microcode SW error'`：先确认主病是不是固件崩溃。注意 journalctl 没有 `-i` 选项〔6〕，`-g -i` 会静默失败；
3. 崩溃按 BSSID 归因：`journalctl -g 'can not stop rx aggregation for' | grep -oE 'for [0-9a-f:]{17}' | sort | uniq -c`——若 100% 集中于某 AP，则为组合性问题；
4. `modinfo -p iwlwifi | grep 11n_disable`：以本机位定义为准，**禁聚合 = 6**；
5. 自编译模块报 "this_module section size must match"：先查头文件 BTF/PAHOLE 配置残缺（第十节）；
6. 确认崩在固件后，不要 patch 驱动——出错的代码没有源码〔5〕；`11n_disable=6` 买稳定，换卡买速度。

---

### 附录：复现命令

```bash
# 崩溃普查与归因（本文全部计数来自以下三条命令的输出存档）
journalctl -g 'Microcode SW error' | grep -v '^--' | cut -c1-8 | sort | uniq -c
journalctl -g 'can not stop rx aggregation for' | grep -v '^--' | grep -oE 'for [0-9a-f:]{17}' | sort | uniq -c
journalctl --no-pager | grep -oE "starting connection '[^']+'" | sort | uniq -c
# 硬件与驱动事实
lspci -nn | grep -i network; iw phy; modinfo -p iwlwifi | grep 11n_disable
# 压测单路（完整脚本 stress.sh 见仓库）
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M -r 0-1400000000 \
  https://mirrors.ustc.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso &
# 参数验证
cat /sys/module/iwlwifi/parameters/11n_disable    # 6 = 禁聚合生效
```

### 参考文献

- **[1]** Intel® Dual Band Wireless-AC 7260 — Specifications（产品规格页）. Intel ARK.
  https://www.intel.com/content/www/us/en/products/sku/75439/intel-dual-band-wirelessac-7260/specifications.html
  （存档：`ref/intel-ark-ac7260-spec.html`；页内含 "802.11ac"、"867 Mbps"，全文无 "6 GHz"）
- **[2]** Intel® Wi-Fi 6E AX210 (Gig+) — Specifications（产品规格页）. Intel ARK.
  https://www.intel.com/content/www/us/en/products/sku/204836/intel-wifi-6e-ax210-gig/specifications.html
  （存档：`ref/intel-ark-ax210-spec.html`；页内 "Wi-Fi 6E"×13、"6 GHz"×2）
- **[3]** Linux kernel v6.8 — `net/mac80211/agg-rx.c`（第 91 行即 "HW problem - can not stop rx aggregation" 的打印点）.
  https://raw.githubusercontent.com/torvalds/linux/v6.8/net/mac80211/agg-rx.c
  （存档：`ref/kernel-mac80211-agg-rx.c`；树内浏览：https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux/tree/net/mac80211/agg-rx.c?h=v6.8 ）
- **[4]** Linux kernel v6.8 — `net/mac80211/key.c`（第 337 行即 "Rekeying PTK … can't safely do that" 的打印点，函数 `ieee80211_pairwise_rekey()`）.
  https://raw.githubusercontent.com/torvalds/linux/v6.8/net/mac80211/key.c
  （存档：`ref/kernel-mac80211-key.c`）
- **[5]** linux-firmware 仓库 — `iwlwifi-7260-17.ucode` 提交历史（页面标题：*kernel/git/firmware/linux-firmware.git — Repository of firmware blobs for use with the Linux kernel*）.
  https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/log/iwlwifi-7260-17.ucode
  （存档：`ref/linux-firmware-gitlog-iwlwifi-7260-17.html`；提交列表：2016-07-10 引入，2018-10-03 最后内容更新，2025-08-28 目录迁移）
- **[6]** journalctl(1) — systemd 官方手册页（无 `-i` 选项）.
  https://www.freedesktop.org/software/systemd/man/journalctl.html
  （存档：`ref/journalctl-manpage-freedesktop.html` + 本机 man 页 `ref/journalctl-man.txt`）

### 引用与证据

外部引用 [1]~[6] 的页面/源码已**全部下载存档**于 `ref/`，逐条对应关系见 **`ref/README.md`**（含原始 URL 与关键摘录位置）；本机日志证据存档于 `ref/logs/`（21 个文件）。图 1~4 由存档数据绘制，绘图脚本 `gen-charts.py`。

*声明：文中"小米路由器"是对作者个人设备的客观描述；本案结论限于"AC 7260 固件 × 该设备的聚合流量"这一组合，不构成对任何品牌或产品线的评价。*
