#!/bin/bash
# Build DOOM2D XEX from ASM sources
# Usage: ./build_doom2d.sh

MADS="./mads.exe"
SRCDIR="source"
OUTDIR="bin"
MAIN="main.asm"
OUTPUT="doom2d.xex"

mkdir -p "$OUTDIR"

echo "Building DOOM2D..."
cd "$SRCDIR"
../$MADS "$MAIN" -o:"../$OUTDIR/$OUTPUT" -l:"../$OUTDIR/doom2d.lst" -t:"../$OUTDIR/doom2d.lab" 2>&1
result=$?
cd ..

if [ $result -eq 0 ]; then
    size=$(wc -c < "$OUTDIR/$OUTPUT")
    echo "OK: $OUTDIR/$OUTPUT ($size bytes)"
else
    echo "BUILD FAILED!"
    exit 1
fi
