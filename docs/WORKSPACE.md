# ~/driver/iwlwifi 目录导览

AC 7260 固件崩溃问题（2026-10-10/11）的完整工作区：诊断 → 实验 → 修复 → 文章。

## 目录结构

```
├── README.md                     ← 本文件
├── XPS13-WiFi频繁断网排查全记录.md   ← 发布稿（引用编号 [1]~[6]）
├── 诊断报告与解决方案.md              ← 技术报告（面向本机）
├── 恢复指南.md                    ← 一键回稳定配置/卸载/复原
├── article-figs/                 ← 文章配图 4 张（gen-charts.py 生成）
├── ref/                          ← 引用存档：外部文档 [1]~[6] + 本机日志证据 logs/15件
│   └── README.md                 ← 引用索引（每条引用 ↔ 证据文件对照）
├── logs/                         ← 全部运行日志（watch/safeguard/压测/实验）
├── scripts/                      ← 运维与实验脚本（见下表）
├── src/                          ← A-MPDU 补丁: iwlwifi-ampdu-tune.patch + 幂等补丁器（源码树不入库，见 src/README.md）
│   ├── dkms.conf                 ← DKMS 配置（包名 iwlwifi-ampdu-tune/6.8）
│   ├── apply-ampdu-patch.py      ← 幂等补丁器
│   └── minmod-test/              ← 最小模块对照实验（BTF 定位用）
└── archive/                      ← 一次性大文件（内核源码包 142MB / .deb 165MB / 解压树）
```

## scripts/ 速查

| 脚本 | 用途 |
|---|---|
| wifi-watch.sh | 【常驻】指纹监听+秒级自愈（systemd user 服务 wifi-watch.service 调用） |
| wifi-safeguard.sh | 【常驻】root 级每 3 分钟兜底（系统 timer wifi-safeguard.timer 调用；/usr/local/bin 有副本） |
| wifi-monitor.sh | 手动取证：逐秒采样，断线自动附证据快照 |
| stress.sh / stab.sh | 压测（崩溃触发）/ 稳定性测速（均强制绑定 wlp1s0） |
| install-ampdu-experiment.sh | DKMS 实验环境一键部署（gcc-12+dkms+补丁模块+safeguard） |
| install-exp-ko.sh | 安装 src/ 下已编译的实验模块并以指定参数加载 |
| apply-swcrypto.sh / apply-agg-off.sh | 参数止血脚本（历史，已被 install-exp-ko 流程取代） |
| install-agg-policy.sh + 90-wifi-agg-policy + wifi-agg-do-reload.sh + wifi-agg-blacklist.conf | 按 AP 黑名单自动切换聚合策略（NM dispatcher） |
| restore-net.sh | 网络兜底恢复（safeguard 内部也调用） |
| restore-and-bisect.sh / diag2.sh / exp-*.sh / fix-headers-btf.sh | 一次性诊断/实验脚本（留档） |
| gen-charts.py | 从 logs/ 真实数据生成文章配图 |

## 系统当前部署状态（改本目录文件前必读）

以下组件已安装到系统，用的是 **本目录文件的副本**——改源文件后需重新部署：

| 系统位置 | 来源 |
|---|---|
| `~/.config/systemd/user/wifi-watch.service` | ExecStart 指向 `scripts/wifi-watch.sh`（活服务） |
| `/usr/local/bin/wifi-safeguard.sh` | 复制自 `scripts/wifi-safeguard.sh`（systemd timer 每分钟级调用） |
| `/etc/systemd/system/wifi-safeguard.{service,timer}` | timer 已 enable |
| `/usr/local/bin/wifi-agg-do-reload.sh` + `/etc/NetworkManager/dispatcher.d/90-wifi-agg-policy` + `/etc/wifi-agg-blacklist` | 复制自 scripts/ 三件套 |
| `/usr/src/iwlwifi-ampdu-tune-6.8/` + DKMS 注册 | 复制自 `src/dkms-src/`（当前参数默认 -1 = 与 stock 等效） |
| `/etc/modprobe.d/iwlwifi-stability.conf` | `options iwlwifi swcrypto=1 11n_disable=6` ← 定版配置 |
| `/var/log/wifi-watch.log` 等 | 日志统一在 logs/ 与 /var/log |

## 快速命令

```bash
tail -20 logs/wifi-watch.log                                   # watch 战报
journalctl -g 'Microcode SW error' --since today | wc -l       # 今日崩溃数
sudo bash scripts/install-exp-ko.sh                            # 加载实验模块(agg开+32K钳制)
bash 恢复指南.md 第1节                                          # 回稳定配置(见该文件)
```
