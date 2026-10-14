#!/usr/bin/env python3
# gen-charts.py — 从真实日志数据生成知乎文章配图
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime, timedelta
import re

plt.rcParams['font.sans-serif'] = ['Noto Sans CJK JP', 'Droid Sans Fallback', 'AR PL UMing CN', 'DejaVu Sans']
plt.rcParams['axes.unicode_minus'] = False
OUT = "./article-figs"
import os; os.makedirs(OUT, exist_ok=True)
BLUE, RED, GREEN, ORANGE = '#2b6cb0', '#c53030', '#2f855a', '#dd6b20'

# ---- 图1: 每日崩溃次数(真实journalctl计数) ----
days = ['10/3','10/4','10/5','10/6','10/7','10/8','10/9','10/10','10/11']
counts = [259, 2023, 447, 161, 515, 80, 117, 25, 9]
colors = ['#c0392b' if c > 500 else '#e67e22' if c > 100 else '#27ae60' for c in counts]

fig, ax = plt.subplots(figsize=(11, 6))
bars = ax.bar(days, counts, color=colors, alpha=0.88, width=0.62)
ax.set_yscale('log'); ax.set_ylim(5, 9000)
ax.set_ylabel('固件崩溃日志行数（log 刻度）', fontsize=12)
ax.set_title('iwlwifi 固件崩溃（Microcode SW error）按日统计——10-03 机器复用当天开始，当晚进入风暴', fontsize=13)
for b, c in zip(bars, counts):
    ax.text(b.get_x()+b.get_width()/2, c*1.12, str(c), ha='center', fontsize=11, fontweight='bold')

bbox = dict(boxstyle='round,pad=0.35', facecolor='white', edgecolor='#95a5a6', alpha=0.92)
arrow = dict(arrowstyle='->', color='#555555', linewidth=1.2)

ax.annotate('10/3 晚：机器复用\n当天开始崩溃', xy=(-0.12, 300), xytext=(-0.05, 4200),
            fontsize=10.5, bbox=bbox, arrowprops=arrow, ha='center')
ax.annotate('10/4 峰值 ~2000 行/天\n≈ 每小时崩溃数十次', xy=(1.3, 2100), xytext=(3.0, 4200),
            fontsize=10.5, bbox=bbox, arrowprops=arrow, ha='center')
ax.annotate('10/10 17:19\nswcrypto=1（无效）', xy=(7.12, 18), xytext=(5.0, 1300),
            fontsize=10.5, bbox=bbox, arrowprops=arrow, ha='center')
ax.annotate('10/10 17:49 禁聚合\n此后仅剩实验自致崩溃', xy=(8.22, 9), xytext=(8.15, 2200),
            fontsize=10.5, bbox=bbox, arrowprops=arrow, ha='center')

ax.grid(axis='y', alpha=0.3, which='both')
ax.set_axisbelow(True)
plt.tight_layout(); plt.savefig(f'{OUT}/fig1-daily-crashes.png', dpi=150); plt.close()

# ---- 图2: 死亡循环(第1轮压测, 17次崩溃精确时刻) ----
t0 = datetime(2026,10,10,17,27,35)
secs = [0]
gaps = [2,1,2,1,1,1,1,1,2,1,2,2,3,1,3,3]
for g in gaps: secs.append(secs[-1]+g)
fig, ax = plt.subplots(figsize=(10, 4.5))
ax.vlines(secs, 0, 1, colors=RED, linewidth=3)
ax.scatter(secs, [1]*len(secs), color=RED, s=60, zorder=5)
ax.axvspan(0, 87, color=RED, alpha=0.07)
for i in range(1, len(secs)):
    ax.annotate(f'{gaps[i-1]}s', xy=((secs[i-1]+secs[i])/2, 0.5), ha='center', fontsize=9, color=RED)
ax.set_ylim(0, 1.3); ax.set_xlim(-4, 92)
ax.set_yticks([]); ax.set_xlabel('压测开始后的秒数', fontsize=12)
ax.set_title('图2  "死亡循环"实测——聚合开启+满载: 90秒内17次固件崩溃, 相邻间隔中位数2秒\n(每次崩溃后fw_restart恢复~1-2秒, 立即再崩; 下载流量全部被掐断)', fontsize=12.5)
ax.text(44, 1.12, '恢复→崩→恢复→崩 …', ha='center', fontsize=13, color=RED, fontweight='bold')
ax.grid(axis='x', alpha=0.3)
plt.tight_layout(); plt.savefig(f'{OUT}/fig2-death-loop.png', dpi=150); plt.close()

# ---- 图3: 实验矩阵对比 ----
configs = ['原生聚合\n(1MB)', 'swcrypto=1\n(聚合开)', '11n_disable=8\n(误设=强开TX聚合)', '禁聚合\n11n_disable=6', '钳制32K', '钳制64K', '钳制16K', '钳制8K', '密度=7\n(全尺寸)']
crashes = [992, 17, 2, 0, 0, 2, 0, 1, 3]
throughput = [0.2, 0.2, 0.4, 6.5, 0.0, 0.0, 0.0, 0.0, 0.0]  # MB/s 实测(钳制档=停滞)
states = ['风暴', '风暴', '秒崩', '✓ 稳定', '停滞', '崩溃', '停滞', '崩溃+停滞', '崩溃+停滞']
colors = [RED, RED, RED, GREEN, ORANGE, RED, ORANGE, RED, RED]
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 7.5), sharex=True,
                               gridspec_kw={'height_ratios': [1.4, 1]})
b1 = ax1.bar(range(len(configs)), crashes, color=colors, alpha=0.85)
for i, (c, s) in enumerate(zip(crashes, states)):
    ax1.text(i, max(c,0.15)+15, s, ha='center', fontsize=10, fontweight='bold',
             color=GREEN if s=='✓ 稳定' else RED)
ax1.set_ylabel('压测窗口内崩溃次数', fontsize=11)
ax1.set_title('图3  实验矩阵: 五档A-MPDU尺寸×密度维度×聚合开关——没有任何聚合配置可用\n(第1列"原生聚合992次"为历史累计(950:ca+42:c9); 其余为同款8分钟压测/探针窗口实测)', fontsize=12.5)
ax1.grid(axis='y', alpha=0.3); ax1.set_ylim(0, 1050)
b2 = ax2.bar(range(len(configs)), throughput, color=colors, alpha=0.85)
for i, v in enumerate(throughput):
    ax2.text(i, v+0.12, f'{v}' if v else '0(停滞)', ha='center', fontsize=10)
ax2.set_ylabel('实测吞吐 (MB/s)', fontsize=11)
ax2.set_xticks(range(len(configs))); ax2.set_xticklabels(configs, fontsize=9.5)
ax2.grid(axis='y', alpha=0.3); ax2.set_ylim(0, 7.6)
plt.tight_layout(); plt.savefig(f'{OUT}/fig3-matrix.png', dpi=150); plt.close()

# ---- 图4: 稳态吞吐曲线(stab.log 真实0.5秒采样) ----
lines=[l for l in open("ref/logs/stab.log") if ' rx=' in l]
samples=[(re.search(r'rx=(\d+)',l).group(1)) for l in lines]
rx=[int(x) for x in samples]
mbps=[(rx[i+1]-rx[i])*2/131072 for i in range(len(rx)-1)]
xs=[i*0.5 for i in range(len(mbps))]
# 5秒滑动平均
win=[]
for i in range(0,len(mbps)-10,10):
    chunk=mbps[i:i+10]; win.append((i*0.5+2.5, sum(chunk)/len(chunk)))
fig, ax = plt.subplots(figsize=(10, 4.5))
ax.plot(xs, mbps, color=BLUE, alpha=0.25, linewidth=0.8, label='0.5秒原始采样')
wx=[w[0] for w in win]; wy=[w[1] for w in win]
ax.plot(wx, wy, color=BLUE, linewidth=2.2, label='5秒滑动平均')
ax.axhline(sum(wy)/len(wy), color=GREEN, linestyle='--', linewidth=1.5,
           label=f'均值 {sum(wy)/len(wy):.0f} Mbps')
ax.set_xlabel('禁聚合稳定性测速进行秒数 (3路并行下载)', fontsize=12)
ax.set_ylabel('吞吐 (Mbps)', fontsize=12)
ax.set_title('图4  定版配置(禁聚合)下的吞吐曲线——6分钟 0 崩溃、0 丢包: 一条平线\n(对比聚合开启时的图2死亡循环; 上限≈72Mbps, 无过山车)', fontsize=12.5)
ax.legend(fontsize=10, loc='center right')
ax.grid(alpha=0.3)
plt.tight_layout(); plt.savefig(f'{OUT}/fig4-stable-curve.png', dpi=150); plt.close()
print('4张图已生成:', os.listdir(OUT))
