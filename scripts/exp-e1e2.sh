#!/bin/bash
# exp-e1e2.sh — 补丁模块两种模式的传输能力鉴别 (root, 断网两次各约7秒)
LOG=/home/etworker/driver/iwlwifi/logs/exp-e1e2.log
exec > >(tee -a "$LOG") 2>&1
[ "$(id -u)" = 0 ] || { echo "需要 root"; exit 1; }
ISO=https://mirrors.aliyun.com/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso

load_and_test(){
  local MODE="$1"; local PARAMS="$2"
  echo "===== 模式: $MODE (params: $PARAMS) ====="
  rmmod iwlmvm 2>/dev/null; rmmod iwlwifi 2>/dev/null
  modprobe iwlwifi $PARAMS
  sleep 5
  DEV=$(ls /sys/class/net | grep -E '^wl' | head -1)
  ip link set "$DEV" up
  nmcli device connect "$DEV" 2>&1 | tail -1
  sleep 6
  echo "实际参数: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable) ampdu_len_exp_max=$(cat /sys/module/iwlwifi/parameters/ampdu_len_exp_max)"
  echo "-- 大包测试(8000B x3) --"
  ping -I "$DEV" -c3 -W3 -s 8000 192.168.100.1 | tail -1
  echo "-- 强制 wlp1s0 单流 20 秒 --"
  timeout 25 curl -s --interface "$DEV" -o /dev/null -w '%{speed_download} B/s http=%{http_code}\n' -r 0-800000000 "$ISO"
}

echo "########## E1: stock等效模式 (11n_disable=6, 无钳制) ##########"
load_and_test "E1" "swcrypto=1 11n_disable=6 ampdu_len_exp_max=-1"

echo "########## E2: 64K档 (11n_disable=0, exp=3) ##########"
load_and_test "E2" "swcrypto=1 11n_disable=0 ampdu_len_exp_max=3"

echo "########## 最终状态: 留在 E2(若其异常请执行恢复指南第1节) ##########"
