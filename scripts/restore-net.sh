#!/bin/bash
# restore-net.sh — 网络兜底恢复(root)。被 apply-swcrypto.sh 以 systemd-run 定时器武装,
# 也可手动执行。逻辑: 网络正常→直接退出; 不通→恢复连接; 仍不通→回滚 swcrypto 配置再恢复。
LOG=/home/etworker/driver/iwlwifi/logs/restore-net.log
GW=192.168.100.1
CONF=/etc/modprobe.d/iwlwifi-stability.conf
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

# 已通则无事可做(apply 成功但没来得及取消定时器的情况)
for i in 1 2 3; do
  ping -c1 -W2 "$GW" >/dev/null 2>&1 && { log "网络正常, 无需兜底"; exit 0; }
  sleep 1
done

log "==== 兜底恢复开始 ===="
modprobe iwlwifi 2>>"$LOG"

DEV=""
for i in $(seq 1 15); do
  DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
  [ -n "$DEV" ] && break
  sleep 1
done
log "无线接口: ${DEV:-未找到}"
[ -z "$DEV" ] && { log "致命: 无线接口未出现"; exit 1; }

ip link set "$DEV" up 2>>"$LOG"
nmcli device connect "$DEV" >>"$LOG" 2>&1

OK=0
for i in $(seq 1 15); do
  ping -c1 -W2 "$GW" >/dev/null 2>&1 && { OK=1; break; }
  sleep 2
done
if [ "$OK" = 1 ]; then log "网关已通, 兜底完成"; exit 0; fi

log "重连无效 → 回滚 $CONF 并重载驱动"
rm -f "$CONF"
timeout 40 modprobe -r iwlmvm iwlwifi 2>>"$LOG"
modprobe iwlwifi 2>>"$LOG"
sleep 5
DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
[ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" >>"$LOG" 2>&1; }
for i in $(seq 1 15); do
  ping -c1 -W2 "$GW" >/dev/null 2>&1 && { log "回滚后网关已通"; exit 0; }
  sleep 2
done
log "回滚后仍不通! 最后手段: 重启 NetworkManager"
systemctl restart NetworkManager >>"$LOG" 2>&1
sleep 10
ping -c1 -W2 "$GW" >/dev/null 2>&1 && log "最终: 网关已通" || log "最终: 仍不通, 需人工介入"
