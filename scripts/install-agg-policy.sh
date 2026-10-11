#!/bin/bash
# install-agg-policy.sh — 安装"按AP黑名单自动切换聚合策略"(sudo 运行)
# 组件: NM dispatcher 钩子 + 重载工作器 + 黑名单配置
set -e
SRC=/home/etworker/driver/iwlwifi/scripts
[ "$(id -u)" = 0 ] || { echo "请用 sudo 运行"; exit 1; }

install -m 755 "$SRC/90-wifi-agg-policy"      /etc/NetworkManager/dispatcher.d/90-wifi-agg-policy
install -m 755 "$SRC/wifi-agg-do-reload.sh"   /usr/local/bin/wifi-agg-do-reload.sh
install -m 644 "$SRC/wifi-agg-blacklist.conf" /etc/wifi-agg-blacklist
touch /var/log/wifi-agg-policy.log && chmod 644 /var/log/wifi-agg-policy.log
echo "已安装: dispatcher钩子 + 工作器 + 黑名单(/etc/wifi-agg-blacklist)"

# 立即按当前连接评估一次(只读判断, 参数已符合则零动作)
DEV=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -1)
[ -n "$DEV" ] && bash /etc/NetworkManager/dispatcher.d/90-wifi-agg-policy "$DEV" up || true
echo "安装完成。策略日志: /var/log/wifi-agg-policy.log (tail -5 如下)"
tail -5 /var/log/wifi-agg-policy.log
