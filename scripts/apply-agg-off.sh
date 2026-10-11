#!/bin/bash
# apply-agg-off.sh — 缓解阶梯第2步: 在 swcrypto=1 基础上加 11n_disable=6(禁用AMPDU聚合)。
# 依据: 压测证实崩溃签名全部位于 RX 聚合路径且与负载强相关, 聚合是最可疑触发器。代价: 峰值速率下降。
# 安全设计与 apply-swcrypto.sh 相同: 先武装4分钟兜底定时器(restore-net.sh, 含回滚), 全程 timeout, 成功才撤销。
LOG=/home/etworker/driver/iwlwifi/logs/apply-fix2.log
GW=192.168.100.1
CONF=/etc/modprobe.d/iwlwifi-stability.conf
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行"; exit 1; }

TS=$(date +%s)
systemd-run --on-active=240 --unit="net-safetynet-$TS" \
  /bin/bash /home/etworker/driver/iwlwifi/logs/restore-net.sh >>"$LOG" 2>&1 \
  && log "兜底定时器已武装: net-safetynet-$TS (240s)" \
  || log "警告: 兜底定时器武装失败!"
echo "net-safetynet-$TS" > /run/net-safetynet-unit

printf 'options iwlwifi swcrypto=1 11n_disable=6\n' > "$CONF"
log "已写入 $CONF: $(cat "$CONF")"

log "开始重载 iwlwifi (断网开始)"
timeout 40 modprobe -r iwlmvm iwlwifi 2>>"$LOG"
RC=$?
modprobe iwlwifi 2>>"$LOG"
log "modprobe -r 返回 $RC, 模块已重载 (断网结束, 等待重连)"

DEV=""
for i in $(seq 1 20); do
  DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
  [ -n "$DEV" ] && break
  sleep 1
done
log "无线接口: ${DEV:-未找到}"
sleep 3
[ -n "$DEV" ] && { ip link set "$DEV" up; nmcli device connect "$DEV" >>"$LOG" 2>&1; }

AGG=$(cat /sys/module/iwlwifi/parameters/11n_disable 2>/dev/null)
GWOK=0
for i in $(seq 1 15); do
  ping -c1 -W2 "$GW" >/dev/null 2>&1 && { GWOK=1; break; }
  sleep 2
done
UNIT=$(cat /run/net-safetynet-unit 2>/dev/null)
if { [ "$AGG" = "6" ] || [ "$AGG" = "Y" ]; } && [ "$GWOK" = 1 ]; then
  log "成功: 11n_disable=$AGG 且网关已通 — 取消兜底定时器"
  [ -n "$UNIT" ] && systemctl stop "$UNIT.timer" "$UNIT.service" 2>>"$LOG"
  log "==== apply 完成(禁聚合(6)已生效) ===="
else
  log "结果: 11n_disable=${AGG:-?} 网关连通=$GWOK — 保留兜底定时器, 它将自动恢复/回滚"
  log "==== apply 异常结束, 等待兜底 ===="
fi
