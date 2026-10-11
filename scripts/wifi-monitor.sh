#!/bin/bash
# wifi-monitor.sh — 抓"网络崩掉"那一刻的证据
# 用法: ./wifi-monitor.sh [监控秒数]   不带参数则一直跑，Ctrl-C 停止
# 输出: 本目录下 wifi-monitor-<时间>.log
# 网关连续丢包 2 次时自动附上链路状态 + 内核/NM/supplicant 最近 30 条相关日志，
# 这样事后能看出断线瞬间是 rfkill/切换/驱动错误/链路丢失 中的哪一种。

LOG="$(cd "$(dirname "$0")" && pwd)/wifi-monitor-$(date +%m%d-%H%M%S).log"
GW=$(ip route | awk '/^default/{print $3; exit}')
DEV=${DEV:-wlp1s0}
FAIL=0
DURATION=${1:-0}; START=$SECONDS

echo "# $(date '+%F %T') 开始监控 dev=$DEV gw=$GW 日志=$LOG"
echo "# time gw_ms ext_ms" > "$LOG"
trap 'echo "已停止，日志: $LOG"; exit 0' INT TERM

while :; do
  T=$(date '+%T')
  gw=$(ping -c1 -W1 "$GW" 2>/dev/null | awk -F'time=' '/time=/{print $2+0}')
  ext=$(ping -c1 -W1 223.5.5.5 2>/dev/null | awk -F'time=' '/time=/{print $2+0}')

  if [ -z "$gw" ]; then
    FAIL=$((FAIL+1))
    echo "$T FAIL#$FAIL" | tee -a "$LOG"
    if [ "$FAIL" -eq 2 ]; then
      {
        echo "===== $T 断线证据快照 ====="
        echo "--- iw link ---"; iw dev "$DEV" link 2>&1
        echo "--- rfkill ---"; rfkill list 2>&1
        echo "--- 内核/NM/wpa_supplicant 最近日志 ---"
        journalctl -n 40 --no-pager -g 'wlp1s0|iwlwifi 0000|iwlwifi:|rfkill|CTRL-EVENT|deauth|Microcode' 2>&1
        echo "===== 快照结束 ====="
      } >> "$LOG"
    fi
  else
    if [ "$FAIL" -ge 2 ]; then
      echo "$T 恢复 (此前连续丢 $FAIL 次)" | tee -a "$LOG"
    fi
    FAIL=0
    echo "$T $gw ${ext:--}" >> "$LOG"
  fi

  [ "$DURATION" -gt 0 ] && [ $((SECONDS-START)) -ge "$DURATION" ] && break
  sleep 1
done
echo "完成，日志: $LOG"
