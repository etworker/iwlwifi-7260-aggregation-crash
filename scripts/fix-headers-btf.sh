#!/bin/bash
# fix-headers-btf.sh — 修复 HWE 头文件缺失 BTF 配置导致 struct module 尺寸不一致 (root)
set -e
H=/usr/src/linux-headers-$(uname -r)
[ "$(id -u)" = 0 ] || { echo "请以 root 运行"; exit 1; }
echo "== 安装 dwarves(pahole) =="
apt-get install -y dwarves >/dev/null 2>&1 || apt-get install -y dwarves
pahole --version

echo "== 用 /boot 的真实配置覆盖头文件 .config =="
cp "/boot/config-$(uname -r)" "$H/.config"

echo "== 补齐 include/config/auto.conf 缺失符号 =="
for sym in CONFIG_DEBUG_INFO_BTF=y CONFIG_DEBUG_INFO_BTF_MODULES=y \
           CONFIG_PROBE_EVENTS_BTF_ARGS=y CONFIG_PAHOLE_HAS_SPLIT_BTF=y \
           CONFIG_PAHOLE_HAS_LANG_EXCLUDE=y; do
  grep -q "^$sym\$" "$H/include/config/auto.conf" || echo "$sym" >> "$H/include/config/auto.conf"
done
sed -i 's/^CONFIG_PAHOLE_VERSION=.*/CONFIG_PAHOLE_VERSION=125/' "$H/include/config/auto.conf"
touch "$H/include/config/auto.conf"
echo "auto.conf 现含 BTF 相关项:"
grep -E 'BTF|PAHOLE' "$H/include/config/auto.conf"
echo "== 完成 =="
