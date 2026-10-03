#!/usr/bin/env bash
set -euo pipefail

mode=${1:?usage: build_plugin.sh loose|tight}
case "$mode" in loose|tight) ;; *) exit 2 ;; esac
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/build/gem5/$mode"
obj="$out/obj"
mkdir -p "$obj"
cd "$root/ext/cva6"
export CVA6_REPO_DIR="$PWD"
export HPDCACHE_DIR="$PWD/core/cache_subsystem/hpdcache"
export TARGET_CFG=../../../../dut/common/cva6
verilator --cc --timing -j 4 \
    -f "$root/build/system_$mode.f" "$root/dut/$mode/gem5_top.sv" \
    --top-module gem5_top -Wno-fatal -Wno-PINMISSING \
    -Mdir "$obj" -CFLAGS '-fPIC -std=c++17' \
    > "$out/verilator.log" 2>&1 || { cat "$out/verilator.log"; exit 1; }
make -C "$obj" -f Vgem5_top.mk -j 4 > "$out/build.log" 2>&1 || {
    cat "$out/build.log"; exit 1;
}
vroot=/usr/local/share/verilator
g++ -shared -fPIC -std=c++17 -fcoroutines -pthread \
    -DAXION_TOP_CLASS=Vgem5_top -DAXION_PLUGIN_HAS_SLAVE=1 \
    -DAXION_PLUGIN_HAS_MASTER=1 -include Vgem5_top.h \
    -I"$vroot/include" -I"$vroot/include/vltstd" -I"$obj" \
    -I"$root/ext/axiom/src" \
    "$root/gem5/rtl_plugin_shim.cc" \
    "$root/dut/common/dpi_stubs.cpp" \
    "$vroot/include/verilated.cpp" \
    "$vroot/include/verilated_threads.cpp" \
    "$vroot/include/verilated_timing.cpp" \
    "$obj/Vgem5_top__ALL.a" \
    -o "$out/libnvdla_$mode.so"
