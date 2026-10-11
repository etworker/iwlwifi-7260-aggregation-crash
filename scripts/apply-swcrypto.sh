#!/bin/bash
# apply-swcrypto.sh — 应用 swcrypto=1 缓解固件崩溃(root 执行)。
# 安全设计(远程会话专用):
#   1. 开跑前先武装 4 分钟后自动执行的"兜底恢复定时器"(restore-net.sh)。
#      无论本脚本死在哪一步、乃至整个会话失联, 定时器都会把网络救回来(必要时回滚本配置)。
#   2. 模块重载全程带 timeout, 不会挂死。
#   3. 结束时验证 swcrypto=Y 且网关通 → 才取消兜底定时器; 否则留着让它救。
LOG=/home/etworker/driver/iwlwifi/logs/apply-fix.log
GW=192.168.100.1
CONF=/etc/modprobe.d/iwlwifi-stability.conf
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行"; exit 1; }

# 1) 武装兜底定时器(4分钟后触发, 若网络已恢复本脚本会主动取消它)
TS=$(date +%s)
systemd-run --on-active=240 --unit="net-safetynet-$TS" \
  /bin/bash /home/etworker/driver/iwlwifi/logs/restore-net.sh >>"$LOG" 2>&1 \
  && log "兜底定时器已武装: net-safetynet-$TS (240s)" \
  || log "警告: 兜底定时器武装失败!"
echo "net-safetynet-$TS" > /run/net-safetynet-unit

# 2) 写入参数
printf 'options iwlwifi swcrypto=1\n' > "$CONF"
log "已写入 $CONF: $(cat "$CONF")"

# 3) 重载模块(网络将断开约5-15秒)
log "开始重载 iwlwifi (断网开始)"
timeout 40 modprobe -r iwlmvm iwlwifi 2>>"$LOG"
RC=$?
modprobe iwlwifi 2>>"$LOG"
log "modprobe -r 返回 $RC, 模块已重载 (断网结束, 等待重连)"

# 4) 等接口并连接
DEV=""
for i in $(seq 1 20); do
  DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
  [ -n "$DEV" ] && break
  sleep 1
done
log "无线接口: ${DEV:-未找到}"
sleep 3   # 等 NM 在新接口上就绪, 避免竞态(实测自动连接通常已抢先完成)
[ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" >>"$LOG" 2>&1; }

# 5) 验证
SCRYPTO=$(cat /sys/module/iwlwifi/parameters/swcrypto 2>/dev/null)
GWOK=0
for i in $(seq 1 15); do
  ping -c1 -W2 "$GW" >/dev/null 2>&1 && { GWOK=1; break; }
  sleep 2
done
UNIT=$(cat /run/net-safetynet-unit 2>/dev/null)
if { [ "$SCRYPTO" = "Y" ] || [ "$SCRYPTO" = "1" ]; } && [ "$GWOK" = 1 ]; then
  log "成功: swcrypto=$SCRYPTO 且网关已通 — 取消兜底定时器"
  [ -n "$UNIT" ] && systemctl stop "$UNIT.timer" "$UNIT.service" 2>>"$LOG"
  log "==== apply 完成(swcrypto 已生效) ===="
else
  log "结果: swcrypto=${SCRYPTO:-?} 网关连通=$GWOK — 保留兜底定时器, 它将自动恢复/回滚"
  log "==== apply 异常结束, 等待兜底 ===="
fi
