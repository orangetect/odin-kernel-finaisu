#!/bin/bash
# power-tune.sh - 把内核默认 governor 设为 schedutil(EAS/WALT 平台按负载调频)
#
# 用法: bash scripts/power-tune.sh <kernel_dir> [verify]
#
# 只改 out/.config(内核配置层),不改源码。odin_defconfig 显式把默认
# governor 设成 performance(8 核满频,功耗高),这里在构建时显式改为
# schedutil;WALT util 路径的卡 logo 问题由 sched-patches/pelt-force 处理。

set -u

KERNEL_DIR="${1:?usage: power-tune.sh <kernel_dir> [verify]}"
MODE="${2:-apply}"
CONFIG_BIN="$KERNEL_DIR/scripts/config"
CFG="$KERNEL_DIR/out/.config"

[ -x "$CONFIG_BIN" ] || { echo "::error::scripts/config not found under $KERNEL_DIR"; exit 1; }
[ -f "$CFG" ] || { echo "::error::$CFG missing (run make odin_defconfig first)"; exit 1; }

if [ "$MODE" = "verify" ]; then
    grep -qx 'CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y' "$CFG" \
        || { echo "::error::CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y missing"; exit 1; }
    grep -qx 'CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y' "$CFG" \
        && { echo "::error::CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y still set"; exit 1; }
    echo "power-tune gate: PASS"
    exit 0
fi

"$CONFIG_BIN" --file "$CFG" \
    --enable CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
    --disable CPU_FREQ_DEFAULT_GOV_PERFORMANCE
echo "power-tune: default governor -> schedutil"