#!/bin/bash
# Build DOOM2D - bootable ATR with XEX + level data
# Usage: ./build_doom2d.sh

MADS="./mads.exe"
SRCDIR="source"
OUTDIR="bin"

mkdir -p "$OUTDIR"

# --- Build boot loader (XEX then strip header to raw binary) ---
echo "Building boot loader..."
cd "$SRCDIR"
../$MADS bootloader.asm -o:"../$OUTDIR/boot.xex" 2>&1
result=$?
cd ..
if [ $result -ne 0 ]; then
    echo "BOOT LOADER BUILD FAILED!"
    exit 1
fi
python -c "d=open('$OUTDIR/boot.xex','rb').read()[6:]; open('$OUTDIR/boot.bin','wb').write(d)"
echo "  boot.bin OK ($(wc -c < "$OUTDIR/boot.bin") bytes)"

# --- Pass 1: Build XEX with placeholder LVL_SEC1 ---
echo "Building XEX (pass 1)..."
echo "LVL_SEC1 = 9999" > data/atr_layout.asm
cd "$SRCDIR"
../$MADS main.asm -o:"../$OUTDIR/doom2d.xex" 2>&1
result=$?
cd ..
if [ $result -ne 0 ]; then
    echo "XEX BUILD FAILED!"
    exit 1
fi
size=$(wc -c < "$OUTDIR/doom2d.xex")
echo "  doom2d.xex OK ($size bytes)"

# --- Create ATR (calculates LVL_SEC1, writes atr_layout.asm) ---
echo "Creating ATR..."
python tools/make_atr.py "$OUTDIR/doom2d.atr" "$OUTDIR/boot.bin" "$OUTDIR/doom2d.xex" data/test_map.lvl

# --- Pass 2: Rebuild XEX with correct LVL_SEC1 ---
echo "Rebuilding XEX (pass 2, correct LVL_SEC1)..."
cd "$SRCDIR"
../$MADS main.asm -o:"../$OUTDIR/doom2d.xex" -l:"../$OUTDIR/doom2d.lst" -t:"../$OUTDIR/doom2d.lab" 2>&1
result=$?
cd ..
if [ $result -ne 0 ]; then
    echo "XEX REBUILD FAILED!"
    exit 1
fi
size=$(wc -c < "$OUTDIR/doom2d.xex")
echo "  doom2d.xex OK ($size bytes)"

# --- Recreate ATR with final XEX ---
echo "Final ATR..."
python tools/make_atr.py "$OUTDIR/doom2d.atr" "$OUTDIR/boot.bin" "$OUTDIR/doom2d.xex" data/test_map.lvl

echo ""
echo "=== DONE ==="
echo "Boot from: $OUTDIR/doom2d.atr"
