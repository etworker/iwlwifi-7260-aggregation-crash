#!/bin/bash
# install-ampdu-experiment.sh — 一键部署 A-MPDU 调优实验环境 (sudo 运行)
# 做 4 件事:
#   1. 安装 dkms + gcc-12 (Ubuntu 6.8 头文件要求 gcc-12)
#   2. 编译并安装带 ampdu_len_exp_max / ampdu_density_min 参数的 iwlwifi 实验模块
#      (装到 updates/ 优先于内核自带; stock 模块原样保留, 随时可回退)
#   3. 安装 root 级兜底定时任务 wifi-safeguard (每3分钟, 断网逐级自愈)
#   4. 输出验证信息
# 注意: 实验模块加载后默认参数 -1(不钳制)=聚合全开, 存在崩溃风暴风险,
#       因此安装脚本最后会把已知稳定配置写回并重载, 实验由单独脚本逐轮进行。
set -e
SRC=/home/etworker/driver/iwlwifi/scripts
KREL=$(uname -r)
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行"; exit 1; }

echo "== 1/4 安装 dkms + gcc-12"
apt-get install -y dkms gcc-12 >/tmp/ampdu-apt.log 2>&1 || { echo "apt 失败, 见 /tmp/ampdu-apt.log"; tail -5 /tmp/ampdu-apt.log; exit 1; }

echo "== 2/4 部署 DKMS 源码并编译安装"
install -d /usr/src/iwlwifi-ampdu-tune-6.8
cp -a "$SRC/dkms-src/iwlwifi-ampdu-tune-6.8/." /usr/src/iwlwifi-ampdu-tune-6.8/
cp "$SRC/dkms.conf" /usr/src/iwlwifi-ampdu-tune-6.8/dkms.conf
dkms remove -m iwlwifi-ampdu-tune -v 6.8 --all >/dev/null 2>&1 || true
dkms add -m iwlwifi-ampdu-tune -v 6.8
dkms build -m iwlwifi-ampdu-tune -v 6.8
dkms install -m iwlwifi-ampdu-tune -v 6.8
depmod -a "$KREL"
echo "   新参数验证(应显示两行参数说明):"
modinfo "$(modinfo -n iwlwifi)" | grep -A1 'ampdu_len_exp_max\|ampdu_density_min' | head -4

echo "== 3/4 安装 root 兜底定时任务 wifi-safeguard"
install -m 755 "$SRC/wifi-safeguard.sh" /usr/local/bin/wifi-safeguard.sh
cat > /etc/systemd/system/wifi-safeguard.service <<'UNIT'
[Unit]
Description=WiFi last-resort safeguard (reload driver / restore stock modules)
[Service]
Type=oneshot
ExecStart=/usr/local/bin/wifi-safeguard.sh
UNIT
cat > /etc/systemd/system/wifi-safeguard.timer <<'UNIT'
[Unit]
Description=Run wifi-safeguard every 3 minutes
[Timer]
OnBootSec=180
OnUnitActiveSec=180
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now wifi-safeguard.timer
echo "   已启用: $(systemctl is-active wifi-safeguard.timer)"

echo "== 4/4 写回已知稳定配置并重载(带实验参数但默认钳制=关, 行为与现在一致)"
printf 'options iwlwifi swcrypto=1 11n_disable=6\n' > /etc/modprobe.d/iwlwifi-stability.conf
timeout 40 modprobe -r iwlmvm iwlwifi || true
modprobe iwlwifi
sleep 5
DEV=$(ls /sys/class/net | grep -E '^wl' | head -1)
[ -n "$DEV" ] && nmcli device connect "$DEV" >/dev/null 2>&1 || true
sleep 8
echo "验证: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable) swcrypto=$(cat /sys/module/iwlwifi/parameters/swcrypto) ampdu_len_exp_max=$(cat /sys/module/iwlwifi/parameters/ampdu_len_exp_max 2>/dev/null)"
ping -c3 -W2 192.168.100.1 >/dev/null 2>&1 && echo "网络: 正常" || echo "网络: 异常(兜底定时器会处理)"
echo "== 全部完成 =="
