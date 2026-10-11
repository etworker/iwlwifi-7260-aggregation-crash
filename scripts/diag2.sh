#!/bin/bash
# diag2.sh — struct module 尺寸不一致的根因定位 (root)
LOG=/home/etworker/driver/iwlwifi/logs/diag2.log
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date '+%F %T') diag2 开始 ==="

echo "--- 1. 今日内核包变更检查 ---"
grep -iE 'linux-(image|headers|modules)' /var/log/dpkg.log 2>/dev/null | grep "$(date +%Y-%m-%d)" | head -5
grep -B1 -A3 'linux-image' /var/log/apt/history.log 2>/dev/null | grep -A3 "$(date +%Y-%m-%d)" | head -8 || echo "(apt 无今日内核变更)"

echo "--- 2. 安装 zstd 并解压 stock iwlwifi 模块 ---"
apt-get install -y zstd >/dev/null 2>&1
STOCK_KO=/lib/modules/$(uname -r)/kernel/drivers/net/wireless/intel/iwlwifi/iwlwifi.ko.zst
if [ -f "$STOCK_KO" ]; then
  zstd -d -q -f "$STOCK_KO" -o /tmp/stock-iwlwifi.ko && echo "解压完成"
elif [ -f "${STOCK_KO%.zst}" ]; then
  cp "${STOCK_KO%.zst}" /tmp/stock-iwlwifi.ko && echo "(本身未压缩)"
else
  echo "未找到 stock iwlwifi 模块文件:"; ls /lib/modules/$(uname -r)/kernel/drivers/net/wireless/intel/iwlwifi/ 2>/dev/null | head
fi

echo "--- 3. this_module 段大小对比(运行内核的期望值 vs 我们的构建) ---"
for f in /tmp/stock-iwlwifi.ko /home/etworker/driver/iwlwifi/logs/dkms-src/iwlwifi-ampdu-tune-6.8/iwlwifi.ko /home/etworker/driver/iwlwifi/logs/minmod-test/minmod.ko; do
  [ -f "$f" ] && printf '%-70s %s\n' "$(basename $f)" "$(readelf -SW "$f" 2>/dev/null | awk '/this_module /{print "this_module大小=" $6 " (" strtonum("0x"$6) " 字节)"}')"
done

echo "--- 4. 引导配置 vs 头文件配置 差异 ---"
BC=/boot/config-$(uname -r)
AC=/usr/src/linux-headers-$(uname -r)/.config
[ -f "$AC" ] || AC=/usr/src/linux-headers-$(uname -r)/include/config/auto.conf
if [ -f "$BC" ] && [ -f "$AC" ]; then
  if diff -q "$BC" "$AC" >/dev/null 2>&1; then echo "完全一致"; else
    echo "存在差异, 差异条目:"; diff "$BC" "$AC" | head -30
  fi
else echo "config 文件缺失: BC=$BC AC=$AC"; fi

echo "--- 5. /proc/config.gz 对照(如内核支持) ---"
if [ -f /proc/config.gz ]; then
  zcat /proc/config.gz > /tmp/running-config
  diff /tmp/running-config "$AC" 2>/dev/null | head -20 || echo "(无差异)"
else echo "内核未启用 /proc/config.gz"; fi

echo "=== $(date '+%F %T') diag2 结束 ==="
