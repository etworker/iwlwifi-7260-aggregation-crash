#!/bin/bash
# exp-nousb.sh — 无USB干扰下: 聚合原生配置(1MB)与历史第1轮(有流量伴崩溃)可比性复测, 测毕自动回稳定配置
LOG=/home/etworker/driver/iwlwifi/logs/exp-nousb.log
exec > >(tee -a "$LOG") 2>&1
[ "$(id -u)" = 0 ] || { echo "需要 root"; exit 1; }
DEV=wlp1s0
ISO=https://mirrors.ustc.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso

echo "===== 聚合原生(1MB, exp=-1, 11n_disable=0) — 与历史第1轮完全可比 ====="
rmmod iwlmvm 2>/dev/null; rmmod iwlwifi 2>/dev/null
modprobe iwlwifi swcrypto=1 11n_disable=0 ampdu_len_exp_max=-1
sleep 5
ip link set "$DEV" up; nmcli device connect "$DEV" 2>&1 | tail -1
sleep 6
echo "参数: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable) exp=$(cat /sys/module/iwlwifi/parameters/ampdu_len_exp_max)"
echo "-- 15秒吞吐(无USB干扰) --"
timeout 20 curl -s --interface "$DEV" -o /dev/null -w '%{speed_download} B/s http=%{http_code}\n' -r 0-800000000 "$ISO"
echo "-- 40秒崩溃观察 --"
sleep 40
echo "近1分钟崩溃数: $(journalctl --since '-60 sec' -g 'Microcode SW error' 2>/dev/null | grep -vc '^--')"

echo "===== 收尾: 回稳定配置 ====="
printf 'options iwlwifi swcrypto=1 11n_disable=6\n' > /etc/modprobe.d/iwlwifi-stability.conf
rmmod iwlmvm 2>/dev/null; rmmod iwlwifi 2>/dev/null
modprobe iwlwifi
sleep 5
ip link set "$DEV" up; nmcli device connect "$DEV" 2>&1 | tail -1
sleep 6
echo "最终: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable)"
ping -c3 -I "$DEV" -W2 192.168.100.1 | tail -2
