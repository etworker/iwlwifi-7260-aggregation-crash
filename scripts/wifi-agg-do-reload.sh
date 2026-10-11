#!/bin/bash
# wifi-agg-do-reload.sh — 按目标参数重载 iwlwifi 并重连(由 90-wifi-agg-policy 派生, root)
# 用法: wifi-agg-do-reload.sh <6|0>   6=禁聚合(稳定模式) 0=开聚合(全速模式)
CONF=/etc/modprobe.d/iwlwifi-stability.conf
LOG=/var/log/wifi-agg-policy.log
WANT="$1"
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
[ "$WANT" = "6" ] || [ "$WANT" = "0" ] || exit 1
CUR=$(cat /sys/module/iwlwifi/parameters/11n_disable 2>/dev/null)
[ "$CUR" = "$WANT" ] && exit 0
if [ "$WANT" = "6" ]; then
  printf 'options iwlwifi swcrypto=1 11n_disable=6\n' > "$CONF"
else
  printf 'options iwlwifi swcrypto=1\n' > "$CONF"
fi
log "重载驱动: 11n_disable $CUR → $WANT (断网约7秒)"
timeout 40 modprobe -r iwlmvm iwlwifi 2>>"$LOG"
modprobe iwlwifi 2>>"$LOG"
sleep 3
DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
[ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" >>"$LOG" 2>&1; }
log "完成: 11n_disable=$(cat /sys/module/iwlwifi/parameters/11n_disable 2>/dev/null) 接口=${DEV:-未找到}"
