#!/bin/bash
# exp-small.sh — 测 16K/8K 小档 + 密度维度, 完毕自动回到已知稳定配置 (root)
LOG=/home/etworker/driver/iwlwifi/logs/exp-small.log
exec > >(tee -a "$LOG") 2>&1
[ "$(id -u)" = 0 ] || { echo "需要 root"; exit 1; }
DEV=wlp1s0
ISO=https://mirrors.ustc.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso

probe(){
  local LABEL="$1"; shift
  echo "===== $LABEL ====="
  rmmod iwlmvm 2>/dev/null; rmmod iwlwifi 2>/dev/null
  modprobe iwlwifi "$@"
  sleep 5
  ip link set "$DEV" up; nmcli device connect "$DEV" 2>&1 | tail -1
  sleep 6
  echo "参数: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable) exp=$(cat /sys/module/iwlwifi/parameters/ampdu_len_exp_max) density=$(cat /sys/module/iwlwifi/parameters/ampdu_density_min)"
  echo "-- 大包 x3 --"
  ping -I "$DEV" -c3 -W3 -s 8000 192.168.100.1 | tail -2 | head -1
  echo "-- 15秒吞吐 --"
  timeout 20 curl -s --interface "$DEV" -o /dev/null -w '%{speed_download} B/s http=%{http_code}\n' -r 0-800000000 "$ISO"
  echo "-- 20秒崩溃观察 --"
  sleep 20
  C=$(journalctl --since '-40 sec' -g 'Microcode SW error' 2>/dev/null | grep -vc '^--')
  echo "近40秒崩溃数: $C"
}

probe "E3: 16K档 (agg开 exp=1)"        swcrypto=1 11n_disable=0 ampdu_len_exp_max=1
probe "E4: 8K档 (agg开 exp=0)"         swcrypto=1 11n_disable=0 ampdu_len_exp_max=0
probe "E5: 密度维度 (agg开 exp=-1 density=7)" swcrypto=1 11n_disable=0 ampdu_len_exp_max=-1 ampdu_density_min=7

echo "===== 收尾: 回到已知稳定配置 ====="
printf 'options iwlwifi swcrypto=1 11n_disable=6\n' > /etc/modprobe.d/iwlwifi-stability.conf
rmmod iwlmvm 2>/dev/null; rmmod iwlwifi 2>/dev/null
modprobe iwlwifi
sleep 5
ip link set "$DEV" up; nmcli device connect "$DEV" 2>&1 | tail -1
sleep 6
echo "最终: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable) exp=$(cat /sys/module/iwlwifi/parameters/ampdu_len_exp_max)"
ping -c3 -I "$DEV" -W2 192.168.100.1 | tail -2
