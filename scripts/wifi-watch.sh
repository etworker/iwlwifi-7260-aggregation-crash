#!/bin/bash
# wifi-watch.sh — 秒级检测 + 事件驱动自愈 + 全程取证
# 常驻方式: systemd user 服务 wifi-watch.service (见同目录安装说明)
#
# 三层机制:
#   1) 内核指纹监听(即时): "can't safely do that"(PTK重钥降级) / 固件崩溃等 → 立即重连
#   2) 网关探测(每3秒):    连丢3次 → 取证+重连; 重连无效 → 无线电开关
#   3) 外网探测(网关正常时): 连丢5次 → 刷DNS; 仍不通 → 取证+重连
# 所有动作记 ACT 行并附证据快照; 每小时最多 MAX_ACTIONS_HR 次治疗, 防止风暴。

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="/home/etworker/driver/iwlwifi/logs/wifi-watch.log"
DEV="${DEV:-wlp1s0}"
GW="$(ip route | awk '/^default/{print $3; exit}')"
TICK=3
GW_FAILS=3
EXT_FAILS=5
MAX_ACTIONS_HR=6
COOLDOWN=60
FP='can.t safely do that|Microcode SW error|no suitable firmware found|iwlwifi 0000.*Timeout'

log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

snapshot(){
  echo "===== $(date '+%F %T') 快照[$1] =====" >> "$LOG"
  iw dev "$DEV" link >> "$LOG" 2>&1
  iw dev "$DEV" station dump 2>/dev/null | grep -E 'signal|retries|failed|beacon' >> "$LOG"
  rfkill list >> "$LOG" 2>&1
  journalctl -n 25 --no-pager -g 'wlp1s0|iwlwifi 0000|iwlwifi:|rfkill|CTRL-EVENT|deauth|Microcode|can.t safely' >> "$LOG" 2>&1
  echo "===== 快照结束 =====" >> "$LOG"
}

ACTS=(); LAST_ACT=0
can_act(){
  local now=$(date +%s) i keep=()
  for i in "${ACTS[@]}"; do (( now - i < 3600 )) && keep+=("$i"); done
  ACTS=("${keep[@]}")
  (( ${#ACTS[@]} < MAX_ACTIONS_HR ))
}
# 返回: 0=动作成功 1=动作执行了但失败 2=被限流跳过
do_act(){
  local now=$(date +%s) rc
  if ! can_act; then log "SKIP 限流(本小时已${#ACTS[@]}次): $1"; return 2; fi
  (( now - LAST_ACT < COOLDOWN )) && { log "SKIP 冷却期: $1"; return 2; }
  ACTS+=("$now"); LAST_ACT=$now
  log "ACT $1"
  "$2" >> "$LOG" 2>&1; rc=$?
  (( rc == 0 )) && log "OK  $1" || log "ERR $1 (rc=$rc)"
  return $rc
}
reconnect(){ do_act "重连 $DEV" nmcli device connect "$DEV"; }
radio_cycle(){ do_act "无线电开关" bash -c "nmcli radio wifi off; sleep 2; nmcli radio wifi on"; }
# 重连失败(返回1)才升级无线电开关; 限流(2)则不再升级
heal(){ reconnect; local r=$?; (( r == 1 )) && radio_cycle; return 0; }

coproc JW { journalctl -f -n0 -o cat --no-pager -g "$FP" 2>/dev/null; }

gw_ok(){ ping -c1 -W2 "$GW" &>/dev/null; }
ext_ok(){ ping -c1 -W2 223.5.5.5 &>/dev/null; }

fails_gw=0; fails_ext=0
log "===== watch 启动 pid=$$ dev=$DEV gw=${GW:-未知} ====="
while :; do
  # 网关路由没了也算断
  [[ -z "$GW" ]] && GW=$(ip route | awk '/^default/{print $3; exit}')

  if read -t "$TICK" -u "${JW[0]}" line; then
    log "指纹: ${line:0:140}"
    snapshot "内核指纹"
    heal
    fails_gw=0; fails_ext=0
    sleep 5
    continue
  fi

  if gw_ok; then
    fails_gw=0
    if ext_ok; then
      fails_ext=0
    else
      fails_ext=$((fails_ext+1))
      if (( fails_ext == EXT_FAILS )); then
        log "外网连丢${fails_ext}次(网关正常) → 刷DNS缓存"
        resolvectl flush-caches 2>>"$LOG"
      elif (( fails_ext >= EXT_FAILS + 4 )); then
        snapshot "外网持续不通 x$fails_ext"
        heal
        fails_ext=0
      fi
    fi
  else
    fails_gw=$((fails_gw+1))
    if (( fails_gw >= GW_FAILS )); then
      snapshot "网关连续失败 x$fails_gw"
      heal
      fails_gw=0; fails_ext=0
      sleep 5
    fi
  fi
done
