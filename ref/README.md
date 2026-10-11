# 引用与证据索引（ref/ 目录）

本文所有外部说法以下列已存档文件为据；所有本机说法以下列日志导出为据。
存档日期：2026-10-11。原始 URL 在每个条目中注明。

## 外部引用

| # | 文件 | 原始 URL | 证明内容 | 关键摘录位置 |
|---|---|---|---|---|
| [1] | intel-ark-ac7260-spec.html（页面标题：Intel® Dual Band Wireless-AC 7260 — Specifications） | https://www.intel.com/content/www/us/en/products/sku/75439/intel-dual-band-wirelessac-7260/specifications.html | AC 7260 为双频(2.4/5GHz) 802.11ac 网卡，规格页无 6GHz，最高速率 867 Mbps | 页内 "802.11ac"、"2.4 GHz/5 GHz"、"867 Mbps"；全文无 "6GHz" |
| [2] | intel-ark-ax210-spec.html（页面标题：Intel® Wi-Fi 6E AX210 (Gig+) — Specifications） | https://www.intel.com/content/www/us/en/products/sku/204836/intel-wifi-6e-ax210-gig/specifications.html | AX210 为 Wi-Fi 6E 三频(含 6GHz)网卡 | 页内 "Wi-Fi 6E"×24、"6 GHz"×3 |
| [3] | kernel-mac80211-agg-rx.c（Linux kernel v6.8, net/mac80211/agg-rx.c） | https://raw.githubusercontent.com/torvalds/linux/v6.8/net/mac80211/agg-rx.c | "HW problem - can not stop rx aggregation" 的源码出处：mac80211 在驱动 ampdu_action 回调失败时打印 | 第 91 行 |
| [4] | kernel-mac80211-key.c（Linux kernel v6.8, net/mac80211/key.c） | https://raw.githubusercontent.com/torvalds/linux/v6.8/net/mac80211/key.c | "Rekeying PTK ... can't safely do that" 的源码出处与机制（无 CAN_REPLACE_PTK0 能力时污染旧钥+拆 BA） | 第 337 行，函数 ieee80211_pairwise_rekey() |
| [5] | linux-firmware-gitlog-iwlwifi-7260-17.ucode.html | https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/log/iwlwifi-7260-17.ucode | 7260 固件的全部上游更新史：2016-07-10 引入 -17 版本线；最后一次内容更新 2018-10-03；2025-08-28 仅移动目录 | cgit log 列表 |
| [6] | journalctl-man.txt（本机 man 页 JOURNALCTL(1)）+ journalctl-manpage-freedesktop.html（官方在线版 https://www.freedesktop.org/software/systemd/man/journalctl.html ） | 本机 man journalctl | journalctl 无 -i 选项（`-g` 的说明中不含 -i；-i 仅属于 grep） | 全文检索 "-i" |

## 本机证据（ref/logs/）

| 文件 | 内容 | 关键数字 |
|---|---|---|
| microcode-sw-error-all.txt | 全部固件崩溃日志原文 | 3636 行 |
| daily-crash-counts.txt | 崩溃按日统计 | 10/3=259 … 10/4=2023 … 10/11=9 |
| can-not-stop-rx-agg-all.txt | 全部聚合拆除失败日志原文 | 992 行 |
| bssid-attribution.txt | 崩溃按 AP(BSSID) 归因 | :ca(小米5G)=950，:c9(小米2.4G)=42，其他=0 |
| death-loop-17-crashes.txt | 死亡循环 17 次崩溃精确时刻 | 2026-10-10 17:27:35 起，间隔 1~3s |
| ptk-rekey-warnings.txt | 办公室 AP 的 PTK 重钥告警 | 13 条，全部 STA=00:be:75:73:7b:e3 |
| rfkill-user-toggles.txt | Wi-Fi 开关事件（含 uid/pid） | 20 条 off/on 成对 |
| sudo-audit-debug-actions.txt | 手动调试动作（modprobe/固件 mv）的 sudo 审计 | 8 条 |
| nm-activation-counts.txt | 各 Wi-Fi 连接激活记录 | HomeNet_5G 62 / HomeNet 16 / OfficeNet 9 |
| boot-history.txt | 全部 38 次启动时间 | 2023-02-01 → 2026-10-03 之间无启动记录 |
| lspci.txt / iw-phy.txt / modinfo-params.txt / uname.txt | 硬件/驱动能力事实 | PCI 8086:08b1；Band 1/2 无 6GHz；11n_disable 位定义 |
| headers-config-diff-btf.txt | 头文件与运行内核配置差异（BTF/PAHOLE） | CONFIG_DEBUG_INFO_BTF=y 仅在运行内核侧 |

## 说明

- community.intel.com / kb.netgear.com 的社区帖因检索环境无法取得稳定直链，未作为引用；本文不依赖任何"网上流传"类不可存档的说法。
- 图 1~4（article-figs/）由 daily-crash-counts.txt、death-loop-17-crashes.txt、stab.log、stress.log 的实测数据绘制，绘图脚本 gen-charts.py 同目录可查。

### 2026-10-11 补充：被文章直接引用的实测日志副本

正文〔证据: …〕标注涉及以下 5 个文件，已从 logs/ 复制副本入 ref/logs/（与源文件同内容）：
wifi-watch.log、stab.log、exp-e1e2.log、exp-small.log、exp-nousb.log。
至此 ref/logs/ 共 21 个文件，文章全部〔证据〕与〔[1]~[6]〕标注均有实体文件。
