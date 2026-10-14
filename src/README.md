# src/ — A-MPDU 可调参数补丁（iwlwifi 6.8）

给 iwlwifi 增加两个模块参数的补丁，用于实验聚合调优（详见仓库 README 第十、十一节）：

- `ampdu_len_exp_max`：向 AP 广告的 A-MPDU 长度上限（0=8K, 1=16K, 2=32K, 3=64K；-1=不钳制）
- `ampdu_density_min`：HT 聚合密度下限（0..7，越大间隔越大；-1=不改）

## 文件

| 文件 | 说明 |
|---|---|
| `iwlwifi-ampdu-tune.patch` | 标准 unified diff（84 行，5 个文件），可直接 `patch -p1` 应用，便于审查 |
| `apply-ampdu-patch.py` | 幂等补丁器（等价于上面的 patch，带锚点校验），用法：`python3 apply-ampdu-patch.py <iwlwifi源码目录>` |
| `dkms-src/`（不入库） | 补丁后的 iwlwifi 6.8 源码树，按下面步骤重建 |

## 重建源码树（vanilla v6.8 + 补丁）

```bash
cd <仓库根目录>
mkdir -p src/dkms-src/iwlwifi-ampdu-tune-6.8 archive
curl -L -o archive/linux-6.8.tar.xz \
  https://mirrors.tuna.tsinghua.edu.cn/kernel/v6.x/linux-6.8.tar.xz   # 原树: https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.8.tar.xz
tar -xf archive/linux-6.8.tar.xz -C src/dkms-src/iwlwifi-ampdu-tune-6.8 \
  --strip-components=6 linux-6.8/drivers/net/wireless/intel/iwlwifi
python3 src/apply-ampdu-patch.py        # 或: cd src/dkms-src/iwlwifi-ampdu-tune-6.8 && patch -s -p1 < ../iwlwifi-ampdu-tune.patch
```

补丁内容（对照 vanilla v6.8）：

1. `iwl-nvm-parse.c`：新增两个模块参数定义；`iwl_init_vht_hw_capab()` 中 VHT A-MPDU 指数钳制（原值广告 1MB，exp=7）
2. `iwl-eeprom-parse.c`：`iwl_init_ht_hw_capab()` 中 HT ampdu_factor/density 钳制（原值 64K/密度 4）
3. `mvm/dvm/mei` 三个 Makefile：`-I $(srctree)/$(src)/../` 改为 `-I$(src)/../`（外置 M= 编译必需）

## 编译与安装

```bash
sudo bash scripts/install-ampdu-experiment.sh   # 缺源码树会自动下载+打补丁；需 gcc-12 与 dkms
```

注意：此补丁用于实验，结论（见 README 第十一节）是本机环境下聚合各档位均不可用，定版方案为 `11n_disable=6`。模块参数默认 `-1` 时补丁完全惰性，行为与 stock 一致。
