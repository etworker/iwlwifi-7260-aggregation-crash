#!/usr/bin/env python3
"""apply-ampdu-patch.py — 给 iwlwifi 6.8 源码打 A-MPDU 可调参数补丁(幂等, 锚点校验, 失败即中止)
新增模块参数:
  ampdu_len_exp_max  : 广告的 A-MPDU 长度上限 (0=8K,1=16K,2=32K,3=64K; -1=不钳制)
  ampdu_density_min  : HT 聚合密度下限 (0..7, 越大间隔越大; -1=不改)
"""
import sys, os, shutil

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'dkms-src/iwlwifi-ampdu-tune-6.8')

def guard(path, old, new, label):
    p = os.path.join(ROOT, path)
    src = open(p).read()
    if new in src:
        print(f"[跳过] {label}: 已应用")
        return
    if old not in src:
        print(f"[中止] {label}: 锚点在 {path} 中未找到!"); sys.exit(1)
    open(p, 'w').write(src.replace(old, new, 1))
    print(f"[完成] {label}")

# 1) iwl-nvm-parse.c: 定义两个模块参数(插在 iwl_init_vht_hw_capab 前)
anchor_vht = 'static void iwl_init_vht_hw_capab(struct iwl_trans *trans,'
params_block = '''/* --- ampdu-tune begin --- */
#include <linux/module.h>
int ampdu_len_exp_max = -1;
module_param(ampdu_len_exp_max, int, 0444);
MODULE_PARM_DESC(ampdu_len_exp_max,
		 "clamp max A-MPDU length exponent (0=8K,1=16K,2=32K,3=64K; -1=no clamp)");
int ampdu_density_min = -1;
module_param(ampdu_density_min, int, 0444);
MODULE_PARM_DESC(ampdu_density_min,
		 "raise HT A-MPDU density (0..7, higher = more spacing; -1 = no change)");
/* --- ampdu-tune end --- */
static void iwl_init_vht_hw_capab(struct iwl_trans *trans,'''
guard('iwl-nvm-parse.c', 'static void iwl_init_vht_hw_capab(struct iwl_trans *trans,',
      params_block, 'nvm-parse: 模块参数定义')

# 2) iwl-nvm-parse.c: VHT A-MPDU 指数钳制(原值 1024K=exp7)
vht_old = '''		       IEEE80211_VHT_MAX_AMPDU_1024K <<
		       IEEE80211_VHT_CAP_MAX_A_MPDU_LENGTH_EXPONENT_SHIFT;
'''
vht_new = vht_old + '''
	if (ampdu_len_exp_max >= 0 && ampdu_len_exp_max < 7) {
		vht_cap->cap &= ~IEEE80211_VHT_CAP_MAX_A_MPDU_LENGTH_EXPONENT_MASK;
		vht_cap->cap |= (u32)ampdu_len_exp_max <<
			IEEE80211_VHT_CAP_MAX_A_MPDU_LENGTH_EXPONENT_SHIFT;
	}
'''
guard('iwl-nvm-parse.c', vht_old, vht_new, 'nvm-parse: VHT 指数钳制')

# 3) iwl-eeprom-parse.c: HT factor/density 钳制(原值 64K/密度4)
ht_old = '''	ht_info->ampdu_factor = IEEE80211_HT_MAX_AMPDU_64K;
	ht_info->ampdu_density = IEEE80211_HT_MPDU_DENSITY_4;
'''
ht_new = '''	{
		extern int ampdu_len_exp_max;
		extern int ampdu_density_min;
		ht_info->ampdu_factor = IEEE80211_HT_MAX_AMPDU_64K;
		if (ampdu_len_exp_max >= 0 && ampdu_len_exp_max < 3)
			ht_info->ampdu_factor = ampdu_len_exp_max;
		ht_info->ampdu_density = IEEE80211_HT_MPDU_DENSITY_4;
		if (ampdu_density_min >= 0 && ampdu_density_min <= 7 &&
		    ampdu_density_min > ht_info->ampdu_density)
			ht_info->ampdu_density = ampdu_density_min;
	}
'''
guard('iwl-eeprom-parse.c', ht_old, ht_new, 'eeprom-parse: HT factor/density 钳制')

print("补丁全部应用完毕")
