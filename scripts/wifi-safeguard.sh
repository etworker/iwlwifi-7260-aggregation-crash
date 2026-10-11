#!/bin/bash
# wifi-safeguard.sh — root 级兜底定时任务(每3分钟): 网络持续不可达时逐级恢复
#   A: 重载驱动并重连
#   B: 若安装过 DKMS 实验模块且仍不通 → 隔离实验模块, 恢复 stock 内核模块
#   C: 强制写回"已知稳定配置"(swcrypto=1 11n_disable=6)再重载
# 全程写日志 /var/log/wifi-safeguard.log; 12 秒连续不可达才判死, 不与 wifi-watch 抢活
GW=192.168.100.1
LOG=/var/log/wifi-safeguard.log
KREL=$(uname -r)
UPD=$(find "/lib/modules/$KREL/updates" -name 'iwlwifi.ko' 2>/dev/null | head -1)
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

ok=0
for i in 1 2 3 4 5 6; do
  ping -c1 -W2 "$GW" >/dev/null 2>&1 && { ok=1; break; }
  sleep 2
done
[ "$ok" = 1 ] && exit 0

log "判死: 网关持续不可达 — 启动恢复阶梯"
timeout 40 modprobe -r iwlmvm iwlwifi 2>>"$LOG"
modprobe iwlwifi 2>>"$LOG"; sleep 4
DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
[ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" >>"$LOG" 2>&1; }
sleep 10
ping -c1 -W2 "$GW" >/dev/null 2>&1 && { log "A(重载): 已恢复"; exit 0; }

if [ -n "$UPD" ]; then
  log "B: 仍不通 — 隔离 DKMS 实验模块, 恢复 stock 模块"
  mkdir -p /var/backups/ampdu-tune
  mv "$UPD" /var/backups/ampdu-tune/iwlwifi.ko 2>>"$LOG"
  DDIR=$(dirname "$UPD")
  [ -f "$DDIR/iwlmvm.ko" ] && mv "$DDIR/iwlmvm.ko" /var/backups/ampdu-tune/ 2>>"$LOG"
  depmod -a "$KREL"
  timeout 40 modprobe -r iwlmvm iwlwifi 2>>"$LOG"
  modprobe iwlwifi 2>>"$LOG"; sleep 4
  DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
  [ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" >>"$LOG" 2>&1; }
  sleep 10
  ping -c1 -W2 "$GW" >/dev/null 2>&1 && { log "B(恢复stock): 已恢复"; exit 0; }
  log "B: 仍不通"
fi

printf 'options iwlwifi swcrypto=1 11n_disable=6\n' > /etc/modprobe.d/iwlwifi-stability.conf
timeout 40 modprobe -r iwlmvm iwlwifi 2>>"$LOG"
modprobe iwlwifi 2>>"$LOG"; sleep 4
DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
[ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" >>"$LOG" 2>&1; }
sleep 8
ping -c1 -W2 "$GW" >/dev/null 2>&1 && log "C(稳定配置): 已恢复" \
  || log "CRITICAL: A/B/C 全部失败 — 请按 ~/driver/iwlwifi/恢复指南.md 人工处理"
