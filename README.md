# 一台 XPS13 的 Wi-Fi 频繁断网排查记

## 摘要

一台 Dell XPS 13 笔记本跑 Ubuntu 22.04，Wi-Fi 频繁断流：图标显示"已连接"，但所有流量都发不出去，ping 网关也不通；手动关闭再打开 Wi-Fi 能恢复一段时间，然后又断，一晚上要折腾四五次。挂了个 2 分钟一次的自动重连脚本才勉强能用。

本文是完整的排查记录：崩溃日志按日统计（峰值一天 2023 次）→ 按报错里携带的 AP 地址归因（992 次崩溃 100% 集中在小米 AX6000 上）→ 换全新同型号网卡照样崩（排除硬件）→ 定位为"AC 7260 固件 × AX6000 聚合流量"的组合问题 → 把聚合规格从 1MB 一路降到 8K、调整密度，全部失败 → 最终解法：`11n_disable=6` 禁用聚合，74 Mbps 稳定运行，零崩溃。

仓库内容：本文（README）、4 张数据图、全部证据日志（`ref/logs/`）、外部引用存档（`ref/`）、压测与自动兜底脚本（`scripts/`）、A-MPDU 调优补丁（`src/`）。

## 背景：机器与环境

| 项目 | 配置 |
|---|---|
| 机型 | Dell XPS 13 L322X（2013 年款超极本） |
| CPU | Intel Core i7-3517U（Ivy Bridge，2 核 4 线程，1.9 GHz） |
| 内存 | 8 GB（7.3 GiB 可见） |
| 硬盘 | LITEONIT LMT-256M3M 256 GB SATA SSD |
| BIOS | Dell A10（该机型最终版） |
| 系统 | Ubuntu 22.04.5 LTS，HWE 内核 6.8.0-138-generic，GNOME 桌面 |
| 无线网卡 | Intel Dual Band Wireless-AC 7260（2×2 802.11ac + 蓝牙 4.0，半高 mini-PCIe） |
| 网卡固件 | iwlwifi-7260-17.ucode（Intel 为该卡发布的最后一线固件，上游最后内容更新 2018-10-03〔5〕） |
| 路由器 | 小米 AX6000（Wi-Fi 6），双频，SSID：HomeNet / HomeNet_5G |

文中所有 MAC 地址、SSID、IP 均为一致性脱敏占位，规范见 `docs/REDACTION.md`。

## 现象

2026-10-03，这台闲置三年半的机器重新启用。当晚 Wi-Fi 开始频繁断流，且随使用方式不同呈现两种形态：

- **轻度使用**（网页、SSH、聊天）：几小时一次。所有连接突然无响应——Wi-Fi 图标仍显示"已连接"，但任何流量都发不出去，ping 网关也不通；
- **有真实流量时**（下载、视频会议）：几秒到几十秒内必然断。

唯一的恢复办法是手动关闭 Wi-Fi 再打开（有时甚至要重启），之后能正常一段时间，直到下一次发作。断流最密集的晚上，一小时要手动开关四五次。

第一轮排查期间做了一个每 2 分钟检测一次、断了自动重连的后台任务，机器从此"勉强能用"——但根因未除，且这个脚本本身就是后来定位问题的干扰项之一（第九节）。

## 时间线

| 阶段 | 时间 | 做了什么 | 结果 |
|---|---|---|---|
| 风暴 | 10-03 起 | 机器闲置三年半后重新用，断流越来越频繁，靠手动开关 Wi-Fi 续命 | 10-04 峰值约 2000 行崩溃日志/天（图 1） |
| 第一轮排查 | 10-06 ~ 10-09 | 软件参数轮流试（省电、bt_coex、11n_disable=8、swcrypto），均无效；怀疑卡坏，购入全新同型号 7260HMW 换上，20 分钟崩 316 次；10-09 做 AP 对照实验 | 卡没问题，问题在"AX6000 × 7260 固件"组合 |
| 第二轮排查（本文） | 10-10 ~ 10-11 | 找到两轮都漏掉的 11n_disable=6；死亡循环定量；聚合档位穷尽实验；Ubuntu 头文件 BTF 坑定位与修复 | 禁聚合是唯一可用的解，74 Mbps 稳定 |

先说结论：断网是网卡固件崩了。`Microcode SW error detected`，全历史日志里这个错误有 3636 条〔证据: microcode-sw-error-all.txt〕。固件是闭源的，上游最后一次内容更新停在 2018-10-03〔5〕，修不了，只能让它少干活：把聚合关掉，`options iwlwifi 11n_disable=6`。代价是吞吐从纸面 867 Mbps〔1〕降到实测 74 Mbps，换来零崩溃。

下面按"发现问题 → 逐个假设排除 → 定位 → 定量 → 分析 → 解决"的顺序记录。关键结论后面都跟了〔证据: 文件名〕（在 `ref/logs/`），外部资料的原文页面下载在 `ref/`（[1]~[6]，文末有清单）。

## 一、排查从日志开始：崩溃画像

断流发作时的内核日志：

```text
kernel: iwlwifi 0000:01:00.0: Microcode SW error detected.  Restarting 0x2000000.
kernel: iwlwifi 0000:01:00.0: Start IWL Error Log Dump:        (固件寄存器转储)
kernel: wlp1s0: HW problem - can not stop rx aggregation for a4:a9:30:e2:76:da tid 0/2/4/6
```

全历史统计：`Microcode SW error` 共 3636 行〔证据: microcode-sw-error-all.txt〕，按天分布见图 1：10/3=259，10/4=2023，10/5=447，10/6=161，10/7=515，10/8=80，10/9=117，10/10=25，10/11=9。

![图1](article-figs/fig1-daily-crashes.png)

三个特征：

1. 崩溃始于 10/3，机器重新启用的当天。启动历史显示 2023-02-01 之后到 2026-10-03 21:42 之间没有开机记录〔证据: boot-history.txt〕；
2. 崩溃跨内核：10/3~10/5 运行 5.15，之后是 6.8，两边都崩〔证据: boot-history.txt〕——与内核版本无关；
3. 为什么 10/3 才开始，日志给不出答案（机器闲置三年半的老化，或路由器侧的变化）。这个疑问不影响后文：所有结论只建立在剂量关系（第四节）和 AP 归因（第三节）上。

除固件崩溃外，其余断线事件都有更平凡的原因：

| 现象 | 原因 | 证据 |
|---|---|---|
| 断线成串爆发（某晚 6~10 次） | 手动开关 Wi-Fi 抢救（gnome-shell rfkill） | off/on 成对事件 20 条，`audit: op="radio-control" ... uid=1000`〔证据: rfkill-user-toggles.txt〕 |
| 重连后自动挂到 2.4G 变慢 | NetworkManager 两个连接同优先级，按信号百分比挑 | 激活记录：HomeNet_5G 62 次 / HomeNet 16 次〔证据: nm-activation-counts.txt〕 |
| 接口"消失又出现" | 前期调试时手动 `modprobe -r iwlmvm iwlwifi` | sudo 审计日志 8 条〔证据: sudo-audit-debug-actions.txt〕 |
| 偶尔被踢下线（reason=0） | AP 发起 | `CTRL-EVENT-DISCONNECTED` 无 `locally_generated=1` |

## 二、假设一："网卡和小米路由器 6G 不兼容"——不成立

这个说法没有出处，但有一个可以立即检验的前提：这块卡有没有 6GHz。

```text
$ lspci -nn | grep -i network                     〔证据: ref/logs/lspci.txt〕
01:00.0 Network controller [0280]: Intel Corporation Wireless 7260 [8086:08b1] (rev 73)

$ iw phy                                          〔证据: ref/logs/iw-phy.txt〕
    Band 1:   (2.4 GHz)
    Band 2:   (5 GHz)                             ← 没有第三个频段
```

Intel 官方规格页：AC 7260 为 802.11ac 双频，2.4 GHz + 5 GHz，最高 867 Mbps，整页没有 6GHz〔1〕；带 6GHz 的 AX210 规格页则明确标注 Wi-Fi 6E 与 6 GHz〔2〕。

结论：AC 7260 是 2013 年的卡，物理上没有 6GHz 射频，与 6GHz 频段无从发生任何交互。假设排除。

附注：`can not stop rx aggregation` 出自内核 `net/mac80211/agg-rx.c` 第 91 行〔3〕，是 mac80211 的通用报错路径，本机崩溃时就打印了它〔证据: can-not-stop-rx-agg-all.txt〕。在其他硬件的案例里见到同一行字，不代表是同一个病。

## 三、定位：992 次崩溃，100% 指向小米的两个电台

每条聚合失败日志都携带崩溃时所连 AP 的地址，这给出了精确归因：

```text
$ journalctl -g 'can not stop rx aggregation for' | grep -oE 'for [0-9a-f:]{17}' | sort | uniq -c
    950 for a4:a9:30:e2:76:da    ← 小米路由 5G
     42 for a4:a9:30:e2:76:d9    ← 小米路由 2.4G     〔证据: bssid-attribution.txt〕
```

992 次，100% 在小米路由上。同一时期这张卡也连过另一个 AP 组（00:be:75:*），那边只有 PTK 重钥告警，固件崩溃为零〔证据: ptk-rekey-warnings.txt〕。问题从"卡会崩"收窄为"**这块卡 + 这个 AP**"的组合问题。

两个对照实验进一步确认：

1. **换卡**：购入全新同型号 Intel 7260HMW（半高 mini-PCIe，正常安装识别），同一路由下带载测试 20 分钟，崩 316 次（10-07）——排除卡老化与个体损坏，"换卡"方案作废；
2. **换 AP**：同一张卡连 X1C 热点 10 分钟，0 崩溃；连小米 AX6000 10 分钟，崩 31~34 次（10-09）——排除插槽、供电、主机侧因素，锁定 AP 侧。

2×2 矩阵：新旧两块卡 × 两个 AP，崩与不崩完全由 AP 决定。

### 支线：办公室 AP 上的另一种病

办公室 AP 组上有另一指纹，13 条，同一 STA〔证据: ptk-rekey-warnings.txt〕：

```text
kernel: Rekeying PTK for STA 00:be:75:73:7b:e3 but driver can't safely do that.
```

机制在内核 `net/mac80211/key.c` 第 337 行（`ieee80211_pairwise_rekey()`）：AP 发起不带 Extended Key ID 的 PTK 重钥，驱动没有 `NL80211_EXT_FEATURE_CAN_REPLACE_PTK0` 能力，mac80211 只能污染旧钥、停聚合、拆 BA 会话，链路保持但质量下降〔4〕。与主线（固件 sysassert）是两种病，分开记录。

## 四、定量：负载越大，崩得越快

所有 A/B 对比用同一脚本（`stress.sh`）：6 路并行下载（国内镜像，总限速约 340Mbps，强制绑 `--interface wlp1s0`）加高频 TLS 握手，0.5 秒采样吞吐与网关 RTT，`journalctl -f` 盯崩溃指纹。每轮只改一个变量。

> 实验纪律：中途机器插着 USB 网卡，默认路由偏移，有一轮压测流量全走了 USB，7260 没被压到，差点当成"零崩溃"结论。此后所有流量测试强制绑接口，并拔除 USB 复测。对照实验必须单独验证"流量打到了被测对象"。

首轮压测（聚合开启）的 17 次崩溃时刻见图 2〔证据: death-loop-17-crashes.txt〕：

![图2](article-figs/fig2-death-loop.png)

- 90 秒 17 次崩溃，相邻间隔 1~3 秒，中位 2 秒；
- 每次崩完内核 `fw_restart` 自动重启固件，1~2 秒恢复，聚合流量重建，随即再崩；
- 8 分钟窗口实际下载约 0.1GB（限速下应有 20GB）；6 路下载被掐断后，崩溃同步停止。

剂量关系明确：负载是触发条件。对应体感——轻载几小时崩一次，有真实流量就是两秒一次的循环。

## 五、分析：坏在固件层，没有源码可修

- `Microcode SW error`（sysassert）是卡上固件自毁。iwlwifi 架构 = 主机上的开源驱动 + 卡上处理器运行的闭源固件（ucode），出错的代码在固件里，没有源码。Error Log Dump 是固件死后驱动代为导出的卡内寄存器现场〔证据: microcode-sw-error-all.txt〕；
- `HW problem - can not stop rx aggregation` 的打印点在 `net/mac80211/agg-rx.c` 第 91 行〔3〕：mac80211 调驱动的 `ampdu_action` 回调拆 RX 聚合，回调失败即打印。固件已死，回调必然失败——它是善后症状，不是病灶；
- 该固件在 linux-firmware 仓库的全部历史：2016-07-10 引入 -17 版本线，2017 年三次小更新，2018-10-03 最后一次内容更新，2025-08-28 仅目录迁移〔5〕。闭源 + 停更，没有修复可能；
- 降级也已实测：第一轮把固件从 -17 降到 -16，加载后网卡直接消失，重启恢复。旧版本同样不行。

驱动层只剩两条路：用模块参数让固件少干活，或换卡。

## 六、解法：把聚合关掉

第一轮试过 `swcrypto=1`（软件加密）：无效，生效 2 分钟后即再崩〔证据: microcode-sw-error-all.txt，10-10 17:21:00〕。

有效的参数来自 `modinfo` 的位定义〔证据: modinfo-params.txt〕：

```text
11n_disable:disable 11n functionality, bitmap: 1: full, 2: disable agg TX,
              4: disable agg RX, 8 enable agg TX (uint)
```

bit 8 是**启用** TX 聚合——两轮排查先后把它当"禁聚合"用过，实测加载后 1 秒内 2 崩。禁 TX 加禁 RX，2+4=6：

```bash
# /etc/modprobe.d/iwlwifi-stability.conf
options iwlwifi swcrypto=1 11n_disable=6
```

效果（同款压测 A/B）：8 分钟 0 崩溃、下载 2.91GB、网关零丢包；6 分钟稳定性测速（3 路并行下载、0.5 秒采样）为均值 74 Mbps 的平线，波动系数 23%，零崩溃零丢包（图 4）〔证据: stab.log〕。

![图4](article-figs/fig4-stable-curve.png)

代价：聚合是 Wi-Fi 摊薄空口开销的核心手段，禁用后吞吐三级台阶为 867 Mbps（纸面〔1〕）→ ~500 Mbps（典型聚合吞吐，本机未能实测）→ 74 Mbps（实测）。远程桌面（5~20Mbps）无感，大文件下载有感。

## 七、穷尽：聚合的每一档都试过

要验证"是否存在不崩的中间档位"，需要给 iwlwifi 打补丁以支持 A-MPDU 上限和密度的运行时调节（`ampdu_len_exp_max` / `ampdu_density_min`，vanilla v6.8 + 84 行补丁，见 `src/`），DKMS 编译后逐档实验。

编译阶段踩出另一个有普适价值的坑：**Ubuntu 22.04 HWE 内核（6.8.0-138.138~22.04.1）的头文件包配置残缺，该机器上所有自编译模块都无法加载**：

```text
insmod: ERROR: could not insert module xxx.ko: Invalid module format
kernel: module xxx: .gnu.linkonce.this_module section size must match
        the kernel's built struct module size at run time
```

定位：10 行迷你模块同样被拒（排除自身代码）→ stock 模块 this_module 段 1280 字节、自编译 1216 字节 → diff `/boot/config-$(uname -r)` 与头文件 `.config`〔证据: headers-config-diff-btf.txt〕：

```text
< CONFIG_DEBUG_INFO_BTF=y          ← 运行内核有
> (头文件配置缺失)
< CONFIG_PAHOLE_VERSION=125
> CONFIG_PAHOLE_VERSION=0          ← 头文件包构建环境缺 pahole
```

`struct module` 在 BTF 开启时更大；头文件包构建环境缺 pahole 导致 BTF 配置被剔除，按残缺配置编出的模块尺寸必然不符。修复：`apt install dwarves`，用 `/boot/config-*` 覆盖头文件 `.config`、补齐 `include/config/auto.conf` 的 BTF 符号，root 执行 `make modules_prepare`。此后 this_module = 1280，加载正常。

补丁模块就位后的穷尽结果：

| 配置 | 结果 | 证据 |
|---|---|---|
| 钳制 32K / 16K | 不崩，传输停滞（32K 时 8000B 大包丢 33%） | stress.log 第 4b 轮 + exp-small.log |
| 钳制 64K / 8K | 崩溃 + 停滞 | exp-e1e2.log（64K 两崩）/ exp-small.log（8K 一崩） |
| 密度=7（最大间隔，全尺寸） | 崩溃 + 停滞 | exp-small.log（3 崩） |
| 拔除 USB 网卡复测原生聚合 | 停滞 + 2 崩（排除双网卡干扰） | exp-nousb.log |

## 八、结论：聚合开启的每一档都不可用，定版方案为全关

九种配置（含历史原生形态）的完整矩阵：

| 配置 | 结果 | 证据 |
|---|---|---|
| 原生聚合（默认向 AP 广告 1MB 上限） | 历史累计 992 次聚合失败 | bssid-attribution.txt |
| swcrypto=1（聚合开） | 90 秒 17 崩 | death-loop-17-crashes.txt |
| 11n_disable=8（= 强开 TX 聚合） | 加载后 1 秒 2 崩 | microcode-sw-error-all.txt 17:50:26/27 |
| **11n_disable=6（禁 TX+RX 聚合）** | **0 崩溃，74 Mbps 平线** | stab.log |
| 钳制 32K/16K/64K/8K × 密度=7 | 崩溃或停滞，无一可用 | 第七节 |

结论：毒性不是尺寸或密度阈值型的，聚合开启即不可用；聚合全关是穷尽后的唯一解。

定版配置：

```bash
# /etc/modprobe.d/iwlwifi-stability.conf
options iwlwifi swcrypto=1 11n_disable=6    # swcrypto 对崩溃无效，保留无害
```

配套三层兜底：wifi-watch（用户级服务，指纹监听 + 3 秒网关探测 + 分级自愈，上线首日 4 次崩溃全部自动恢复〔证据: wifi-watch.log〕）；wifi-safeguard（root 级 timer，网关持续 12 秒不可达时逐级恢复）；按 AP 黑名单切聚合策略（NetworkManager dispatcher，家用禁聚合稳态、其他网络全速）。

升级路径只剩换卡：USB 方案（如 MT7921AU，内核 mt7921u 原生支持）未验证但机制上绕开了 7260 固件；内置卡替换已被实验否定（全新同型号照崩）。

### 自查清单（每步都有对应的证据文件）

1. `lspci` + `iw phy` + Intel ARK 规格页：确认网卡世代与频段〔1〕〔2〕——没有 6GHz 硬件，"6GHz 兼容"话题即与你无关；
2. `journalctl -g 'Microcode SW error'`：确认主病是不是固件崩溃。journalctl 没有 `-i` 选项〔6〕，写 `-g -i` 会静默失败返回空；
3. 崩溃按 AP 归因：`journalctl -g 'can not stop rx aggregation for' | grep -oE 'for [0-9a-f:]{17}' | sort | uniq -c`——100% 集中于某台设备即组合问题；
4. `modinfo -p iwlwifi | grep 11n_disable`：以本机位定义为准，禁聚合 = 6；
5. 自编译模块报 "this_module section size must match"：先查头文件 BTF/PAHOLE 配置残缺（第七节）；
6. 确认崩在固件即可停止 patch 驱动的尝试——出错的代码没有源码〔5〕。

---

### 附录：复现命令

```bash
# 崩溃普查与归因（本文全部计数来自这三条命令的输出存档）
journalctl -g 'Microcode SW error' | grep -v '^--' | cut -c1-8 | sort | uniq -c
journalctl -g 'can not stop rx aggregation for' | grep -v '^--' | grep -oE 'for [0-9a-f:]{17}' | sort | uniq -c
journalctl --no-pager | grep -oE "starting connection '[^']+'" | sort | uniq -c
# 硬件与驱动事实
lspci -nn | grep -i network; iw phy; modinfo -p iwlwifi | grep 11n_disable
# 压测单路（完整脚本 stress.sh 在仓库 scripts/）
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M -r 0-1400000000 \
  https://mirrors.ustc.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso &
# 参数验证
cat /sys/module/iwlwifi/parameters/11n_disable    # 6 = 禁聚合生效
```

### 参考文献

- **[1]** Intel® Dual Band Wireless-AC 7260 — Specifications（产品规格页）. Intel ARK.
  https://www.intel.com/content/www/us/en/products/sku/75439/intel-dual-band-wirelessac-7260/specifications.html
  （存档：`ref/intel-ark-ac7260-spec.html`；页内有 "802.11ac"、"867 Mbps"，全文无 "6 GHz"）
- **[2]** Intel® Wi-Fi 6E AX210 (Gig+) — Specifications（产品规格页）. Intel ARK.
  https://www.intel.com/content/www/us/en/products/sku/204836/intel-wifi-6e-ax210-gig/specifications.html
  （存档：`ref/intel-ark-ax210-spec.html`；页内 "Wi-Fi 6E"×13、"6 GHz"×2）
- **[3]** Linux kernel v6.8 — `net/mac80211/agg-rx.c`（第 91 行即 "HW problem - can not stop rx aggregation" 的打印点）.
  https://raw.githubusercontent.com/torvalds/linux/v6.8/net/mac80211/agg-rx.c
  （存档：`ref/kernel-mac80211-agg-rx.c`；树内浏览：https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux/tree/net/mac80211/agg-rx.c?h=v6.8 ）
- **[4]** Linux kernel v6.8 — `net/mac80211/key.c`（第 337 行，`ieee80211_pairwise_rekey()` 里的 "Rekeying PTK … can't safely do that"）.
  https://raw.githubusercontent.com/torvalds/linux/v6.8/net/mac80211/key.c
  （存档：`ref/kernel-mac80211-key.c`）
- **[5]** linux-firmware 仓库 — `iwlwifi-7260-17.ucode` 提交历史（页面标题：*kernel/git/firmware/linux-firmware.git — Repository of firmware blobs for use with the Linux kernel*）.
  https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/log/iwlwifi-7260-17.ucode
  （存档：`ref/linux-firmware-gitlog-iwlwifi-7260-17.html`；2016-07-10 引入，2018-10-03 最后一次内容更新，2025-08-28 目录迁移）
- **[6]** journalctl(1) — systemd 官方手册页（没有 `-i` 选项）.
  https://www.freedesktop.org/software/systemd/man/journalctl.html
  （存档：`ref/journalctl-manpage-freedesktop.html` + 本机 man 页 `ref/journalctl-man.txt`）

### 证据文件

正文里的〔证据: 文件名〕都在 `ref/logs/`（21 个），外部引用原文在 `ref/`，对照索引见 `ref/README.md`。图 1~4 由存档数据绘制，脚本 `scripts/gen-charts.py`。

（家用路由器为小米 AX6000，本文只涉及这一台设备，不构成对任何品牌的评价。）

### 仓库内容导航

- `scripts/` — 正文用到的全部脚本：`stress.sh`（压测）、`wifi-watch.sh`/`wifi-safeguard.sh`（自动兜底，部署方式见内）、`install-ampdu-experiment.sh`（DKMS 实验环境一键部署）
- `ref/` — 外部引用存档 [1]~[6] 与本机日志证据（`ref/README.md` 为对照索引）
- `src/` — A-MPDU 可调参数补丁（DKMS 源码树按 `src/README.md` 重建）
- `docs/WORKSPACE.md` — 工作区目录导览；`docs/REDACTION.md` — 脱敏规范
