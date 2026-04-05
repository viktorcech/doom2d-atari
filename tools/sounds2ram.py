#!/usr/bin/env python3
"""
Convert all game sounds to contiguous RAM binary + ASM address tables.

Sounds loaded at $6000-$BFFF (24KB, requires BASIC ROM disabled).
Generates one binary file + ASM include with address labels.

Usage:
    python sounds2ram.py
"""

import sys
import os
import wave
import numpy as np

TARGET_RATE = 3995
RAM_BASE = 0x6000
RAM_MAX = 0xC000  # MEMAC starts here

SOUNDS = [
    ('pistol',   'DSPISTOL',  'SFX_PISTOL'),
    ('itemup',   'DSITEMUP',  'SFX_ITEMUP'),
    ('rocket',   'DSRLAUNC',  'SFX_ROCKET'),
    ('podeath',  'DSPODTH1',  'SFX_PODEATH'),
    ('posit',    'DSPOSIT1',  'SFX_POSIGHT'),
    ('impsit',   'DSBGSIT1',  'SFX_IMPSIGHT'),
    ('impdeath', 'DSBGDTH1',  'SFX_IMPDEATH'),
    ('shotgun',  'DSSHOTGN',  'SFX_SHOTGUN'),
    ('wpnup',    'DSWPNUP',   'SFX_WPNUP'),
    ('punch',    'DSPUNCH',   'SFX_PUNCH'),
    ('barexp',   'DSBAREXP',  'SFX_BAREXP'),
    ('slop',     'DSSLOP',    'SFX_SLOP'),
    ('brssit',   'DSBRSSIT',  'SFX_BRSSIT'),
    ('brsdth',   'DSBRSDTH',  'SFX_BRSDTH'),
]


def wav_to_4bit(wav_path, max_ms=0):
    """Convert WAV to 4-bit packed POKEY samples."""
    w = wave.open(wav_path, 'rb')
    channels = w.getnchannels()
    sampwidth = w.getsampwidth()
    rate = w.getframerate()
    frames = w.readframes(w.getnframes())
    w.close()

    if sampwidth == 1:
        samples = np.frombuffer(frames, dtype=np.uint8).astype(np.float32) - 128
        samples /= 128.0
    elif sampwidth == 2:
        samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32)
        samples /= 32768.0

    if channels > 1:
        samples = samples.reshape(-1, channels)[:, 0]

    # Resample
    n_out = int(len(samples) * TARGET_RATE / rate)
    if max_ms > 0:
        max_samples = int(TARGET_RATE * max_ms / 1000)
        n_out = min(n_out, max_samples)
    indices = np.linspace(0, len(samples) - 1, n_out).astype(int)
    resampled = samples[indices]

    # Normalize to 0-15
    resampled = (resampled + 1.0) * 7.5
    resampled = np.clip(resampled, 0, 15).astype(np.uint8)

    # Fade-out last 20%
    fade_len = max(1, n_out // 5)
    fade = np.linspace(1.0, 0.0, fade_len)
    resampled[-fade_len:] = (resampled[-fade_len:].astype(np.float32) * fade).astype(np.uint8)

    # Pack 4-bit pairs
    if len(resampled) % 2:
        resampled = np.append(resampled, np.uint8(0))
    packed = (resampled[0::2] << 4) | resampled[1::2]
    return packed.tobytes()


def main():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    wav_dir = os.path.join(base_dir, 'extracted', 'sounds', 'wav')
    data_dir = os.path.join(base_dir, 'data')

    all_data = b''
    entries = []

    for game_name, wav_name, sfx_const in SOUNDS:
        wav_path = os.path.join(wav_dir, wav_name + '.wav')
        if not os.path.exists(wav_path):
            print(f"WARNING: {wav_path} not found!")
            continue

        packed = wav_to_4bit(wav_path)
        start_addr = RAM_BASE + len(all_data)
        end_addr = start_addr + len(packed)

        if end_addr > RAM_MAX:
            print(f"ERROR: {game_name} exceeds RAM limit! "
                  f"${end_addr:04X} > ${RAM_MAX:04X}")
            print(f"  Total so far: {len(all_data)+len(packed)} bytes, "
                  f"limit: {RAM_MAX-RAM_BASE} bytes")
            print(f"  Truncate some sounds with max_ms parameter")
            sys.exit(1)

        all_data += packed
        w = wave.open(wav_path)
        dur_ms = w.getnframes() / w.getframerate() * 1000
        w.close()

        entries.append((game_name, sfx_const, start_addr, end_addr, len(packed), dur_ms))
        print(f"  {game_name:12s}: {dur_ms:6.0f}ms -> {len(packed):5d} bytes  "
              f"${start_addr:04X}-${end_addr:04X}")

    print(f"\nTotal: {len(all_data)} bytes ({len(all_data)/1024:.1f} KB)")
    print(f"RAM: ${RAM_BASE:04X}-${RAM_BASE+len(all_data)-1:04X}")
    print(f"Free: {RAM_MAX-RAM_BASE-len(all_data)} bytes")

    # Write binary
    bin_path = os.path.join(data_dir, 'sounds.bin')
    with open(bin_path, 'wb') as f:
        f.write(all_data)
    print(f"\nBinary: {bin_path}")

    # Generate ASM
    asm_path = os.path.join(data_dir, 'sound_ram.asm')
    with open(asm_path, 'w') as f:
        f.write("; Auto-generated sound RAM address tables\n")
        f.write(f"; {len(entries)} sounds, {len(all_data)} bytes\n")
        f.write(f"; RAM ${RAM_BASE:04X}-${RAM_BASE+len(all_data)-1:04X}\n\n")

        f.write("sfx_addr\n")
        for name, const, start, end, size, dur in entries:
            f.write(f"        dta a(${start:04X})  ; {const} ({name}, {dur:.0f}ms)\n")

        f.write("\nsfx_end\n")
        for name, const, start, end, size, dur in entries:
            f.write(f"        dta a(${end:04X})  ; {const}\n")

    print(f"ASM tables: {asm_path}")


if __name__ == '__main__':
    main()
