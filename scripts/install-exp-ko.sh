#!/bin/bash
# install-exp-ko.sh — 安装修正后的实验模块并加载实验参数(断网约7秒)
set -e
KREL=$(uname -r)
D=/lib/modules/$KREL/updates/dkms
SRC=/home/etworker/driver/iwlwifi/src/dkms-src/iwlwifi-ampdu-tune-6.8
[ "$(id -u)" = 0 ] || { echo "需要 root"; exit 1; }
install -d "$D"
install -m 644 "$SRC/iwlwifi.ko"   "$D/iwlwifi.ko"
install -m 644 "$SRC/mvm/iwlmvm.ko" "$D/iwlmvm.ko"
depmod -a "$KREL"

echo "== 卸载当前模块并加载实验参数(agg开, 钳制32K) =="
rmmod iwlmvm 2>/dev/null || true
rmmod iwlwifi 2>/dev/null || true
modprobe iwlwifi swcrypto=1 11n_disable=0 ampdu_len_exp_max=2
sleep 5
DEV=$(ls /sys/class/net | grep -E '^wl' | head -1)
[ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" 2>&1 | tail -1; }
sleep 6
echo "验证: 加载模块srcversion=$(cat /sys/module/iwlwifi/srcversion 2>/dev/null)(应为E7972B99E464917461D3076)"
echo "参数: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable) ampdu_len_exp_max=$(cat /sys/module/iwlwifi/parameters/ampdu_len_exp_max 2>/dev/null) swcrypto=$(cat /sys/module/iwlwifi/parameters/swcrypto)"
ping -c3 -W2 192.168.100.1 | tail -2
