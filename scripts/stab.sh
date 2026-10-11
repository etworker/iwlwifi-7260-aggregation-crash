#!/bin/bash
# stab.sh — 禁聚合配置下的吞吐稳定性测试: 3路下载x6分钟, 每0.5秒采样
DIR=/home/etworker/driver/iwlwifi
S=/home/etworker/driver/iwlwifi/logs/stab.log; E=/home/etworker/driver/iwlwifi/logs/stab-events.log
IFACE=wlp1s0
: > "$S"; : > "$E"
journalctl -f -n0 -o cat --no-pager -g 'Microcode SW error|can not stop rx aggregation|CTRL-EVENT-DISCONNECTED|deauthenticating' > "$E" 2>&1 &
JPID=$!
UA=https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso
UB=https://mirrors.ustc.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso
UC=https://mirror.nju.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso
curl -s -o /dev/null --limit-rate 8M --max-time 350 -r 0-1400000000 "$UA" &
curl -s -o /dev/null --limit-rate 8M --max-time 350 -r 0-1400000000 "$UB" &
curl -s -o /dev/null --limit-rate 8M --max-time 350 -r 0-1400000000 "$UC" &
END=$((SECONDS+360))
while [ $SECONDS -lt $END ]; do
  t=$(date '+%T'); gw=$(ping -c1 -W1 192.168.100.1 2>/dev/null | awk -F'time=' '/time=/{print $2+0}')
  rx=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null)
  echo "$t gw=${gw:-FAIL} rx=$rx" >> "$S"
  sleep 0.5
done
kill $JPID 2>/dev/null
echo "STAB_DONE" >> "$S"
