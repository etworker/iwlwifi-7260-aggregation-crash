#!/bin/bash
DIR=/home/etworker/driver/iwlwifi
S=/home/etworker/driver/iwlwifi/logs/stress.log; E=/home/etworker/driver/iwlwifi/logs/stress-events.log
IFACE=wlp1s0
: > "$S"; : > "$E"
journalctl -f -n0 -o cat --no-pager -g 'Microcode SW error|can not stop rx aggregation|CTRL-EVENT-DISCONNECTED|deauthenticating|HW problem' > "$E" 2>&1 &
JPID=$!
R0=$(cat /sys/class/net/$IFACE/statistics/rx_bytes)
echo "START rx0=$R0 t=$(date +%s)" >> "$S"
UA=https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso
UB=https://mirrors.ustc.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso
UC=https://mirror.nju.edu.cn/ubuntu-releases/22.04/ubuntu-22.04.5-desktop-amd64.iso
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M --max-time 445 -r 0-1400000000 "$UA" &
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M --max-time 445 -r 1400000000-2800000000 "$UA" &
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M --max-time 445 -r 2800000000-4200000000 "$UA" &
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M --max-time 445 -r 0-1400000000 "$UB" &
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M --max-time 445 -r 1400000000-2800000000 "$UB" &
curl -s --interface wlp1s0 -o /dev/null --limit-rate 7M --max-time 445 -r 0-1400000000 "$UC" &
( for i in $(seq 1 1600); do curl -s --interface wlp1s0 -o /dev/null -m 3 -H 'Connection: close' https://mirrors.tuna.tsinghua.edu.cn/ 2>/dev/null; sleep 0.25; done ) &
END=$((SECONDS+460))
while [ $SECONDS -lt $END ]; do
  t=$(date '+%T'); gw=$(ping -I wlp1s0 -c1 -W1 192.168.100.1 2>/dev/null | awk -F'time=' '/time=/{print $2+0}')
  rx=$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null)
  echo "$t gw=${gw:-FAIL} rx=$rx" >> "$S"
  sleep 0.5
done
kill $JPID 2>/dev/null
echo "DONE rx_end=$rx" >> "$S"
