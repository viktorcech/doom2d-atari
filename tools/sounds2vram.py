#!/usr/bin/env python3
"""
Convert all game sounds to VRAM-ready binary + ASM address tables.

Reads WAV files, converts to 4-bit packed POKEY format,
concatenates into chunked binaries for VRAM upload,
generates ASM include with bank/offset tables.

Usage:
    python sounds2vram.py
"""

import sys
import os
import wave
import struct
import numpy as np

# Base VRAM address for sound data
VRAM_BASE = 0x044000
MEMAC_BASE = 0x9000
BANK_EN = 0x80
CHUNK_SIZE = 12288  # 3 banks, max for $6000 upload area
TARGET_RATE = 3995  # POKEY timer rate (AUDF1=15)

# Sound definitions: (game_name, wav_name, sfx_constant, trimmed_name or None)
SOUNDS = [
    ('pistol',   'DSPISTOL',  'SFX_PISTOL',   '00_pistol_513msb.wav'),
    ('itemup',   'DSITEMUP',  'SFX_ITEMUP',    None),
    ('rocket',   'DSRLAUNC',  'SFX_ROCKET',    '02_rocket_1404ms.wav'),
    ('podeath',  'DSPODTH1',  'SFX_PODEATH',   '03_podeath_1176ms.wav'),
    ('posit',    'DSPOSIT1',  'SFX_POSIGHT',   '04_posit_484ms.wav'),
    ('impsit',   'DSBGSIT1',  'SFX_IMPSIGHT',  '05_impsit_1236ms.wav'),
    ('impdeath', 'DSBGDTH1',  'SFX_IMPDEATH',  '06_impdeath_646ms.wav'),
    ('shotgun',  'DSSHOTGN',  'SFX_SHOTGUN',   '07_shotgun_857ms.wav'),
    ('wpnup',    'DSWPNUP',   'SFX_WPNUP',     '08_wpnup_533ms.wav'),
    ('punch',    'DSPUNCH',   'SFX_PUNCH',      '09_punch_226ms.wav'),
    ('barexp',   'DSBAREXP',  'SFX_BAREXP',     '10_barexp_1686ms.wav'),
    ('slop',     'DSSLOP',    'SFX_SLOP',       '11_slop_1008ms.wav'),
    ('brssit',   'DSBRSSIT',  'SFX_BRSSIT',     '12_brssit_1248ms.wav'),
    ('brsdth',   'DSBRSDTH',  'SFX_BRSDTH',     '13_brsdth_1001ms.wav'),
    ('sgtsit',   'DSSGTSIT',  'SFX_SGTSIT',     None),
    ('sgtdth',   'DSSGTDTH',  'SFX_SGTDTH',     'DSSGTDTH.wav'),
    ('cacsit',   'DSCACSIT',  'SFX_CACSIT',     None),
    ('cacdth',   'DSCACDTH',  'SFX_CACDTH',     None),
    ('plasma',   'DSPLASMA',  'SFX_PLASMA',     None),
    ('bfg',      'DSBFG',     'SFX_BFG',        None),
    ('bfgxpl',   'DSRXPLOD',  'SFX_BFGXPL',     None),
    ('pldeath',  'DSPLDETH',  'SFX_PLDEATH',    None),
    ('dooropn',  'DSBDOPN',   'SFX_DOOROPN',    'DSBDOPNa.wav'),
    ('doorcls',  'DSBDCLS',   'SFX_DOORCLS',    None),
    ('oof',      'DSSKLDTH',  'SFX_OOF',        None),
    ('posit2',   'DSPOSIT2',  'SFX_POSIGHT2',   None),
    ('posit3',   'DSPOSIT3',  'SFX_POSIGHT3',   None),
    ('firsht',   'DSFIRSHT',  'SFX_FIRSHT',     None),
    ('swtchn',   'DSSWTCHN',  'SFX_SWTCHN',     None),
    ('swtchx',   'DSSWTCHX',  'SFX_SWTCHX',     None),
    ('claw',     'DSCLAW',    'SFX_CLAW',       None),
    ('sgtatk',   'DSSGTATK',  'SFX_SGTATK',     None),
]


def wav_to_4bit(wav_path, target_rate=TARGET_RATE):
    """Convert WAV to 4-bit packed POKEY samples."""
    w = wave.open(wav_path, 'rb')
    channels = w.getnchannels()
    sampwidth = w.getsampwidth()
    rate = w.getframerate()
    frames = w.readframes(w.getnframes())
    w.close()

    # Convert to numpy
    if sampwidth == 1:
        samples = np.frombuffer(frames, dtype=np.uint8).astype(np.float32) - 128
        samples /= 128.0
    elif sampwidth == 2:
        samples = np.frombuffer(frames, dtype=np.int16).astype(np.float32)
        samples /= 32768.0
    else:
        raise ValueError(f"Unsupported sample width: {sampwidth}")

    # Mono
    if channels > 1:
        samples = samples.reshape(-1, channels)[:, 0]

    # Resample to target rate
    n_out = int(len(samples) * target_rate / rate)
    indices = np.linspace(0, len(samples) - 1, n_out).astype(int)
    resampled = samples[indices]

    # Normalize to 0-15 (4-bit)
    resampled = (resampled + 1.0) * 7.5
    resampled = np.clip(resampled, 0, 15).astype(np.uint8)

    # Apply fade-out (last 20%)
    fade_len = max(1, n_out // 5)
    fade = np.linspace(1.0, 0.0, fade_len)
    resampled[-fade_len:] = (resampled[-fade_len:].astype(np.float32) * fade).astype(np.uint8)

    # Pack into 4-bit pairs (hi nibble first)
    if len(resampled) % 2:
        resampled = np.append(resampled, np.uint8(0))
    packed = (resampled[0::2] << 4) | resampled[1::2]

    return packed.tobytes()


def vram_to_bank_ptr(vram_addr):
    """Convert 24-bit VRAM address to MEMAC-B format (bank_ctrl, ptr_lo, ptr_hi).
    MEMAC-B: 16KB window at $4000-$7FFF, bank = vram_addr / $4000, enable = $C0."""
    MEMB_EN = 0xC0
    MEMB_WINDOW = 0x4000
    MEMB_BANK_SIZE = 0x4000  # 16KB per bank
    bank = vram_addr // MEMB_BANK_SIZE
    offset = vram_addr % MEMB_BANK_SIZE
    ptr = MEMB_WINDOW + offset
    return MEMB_EN | bank, ptr & 0xFF, (ptr >> 8) & 0xFF


def main():
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    wav_dir = os.path.join(base_dir, 'extracted', 'sounds', 'wav')
    trimmed_dir = os.path.join(base_dir, 'data', 'sfx_used')
    data_dir = os.path.join(base_dir, 'data')

    # Convert all sounds
    all_data = b''
    entries = []

    for game_name, wav_name, sfx_const, trimmed_name in SOUNDS:
        # Prefer trimmed version from sfx_used/
        wav_path = None
        if trimmed_name and os.path.exists(os.path.join(trimmed_dir, trimmed_name)):
            wav_path = os.path.join(trimmed_dir, trimmed_name)
            src_tag = 'trimmed'
        else:
            wav_path = os.path.join(wav_dir, wav_name + '.wav')
            src_tag = 'original'
        if not os.path.exists(wav_path):
            print(f"WARNING: {wav_path} not found, skipping")
            continue

        packed = wav_to_4bit(wav_path)
        start_addr = VRAM_BASE + len(all_data)
        end_addr = start_addr + len(packed)
        all_data += packed

        w = wave.open(wav_path)
        dur_ms = w.getnframes() / w.getframerate() * 1000
        w.close()

        entries.append((game_name, sfx_const, start_addr, end_addr, len(packed), dur_ms))
        print(f"  {game_name:12s}: {dur_ms:6.0f}ms -> {len(packed):5d} bytes  "
              f"VRAM ${start_addr:06X}-${end_addr:06X}  [{src_tag}]")

    print(f"\nTotal: {len(all_data)} bytes ({len(all_data)/1024:.1f} KB)")
    print(f"VRAM: ${VRAM_BASE:06X}-${VRAM_BASE+len(all_data)-1:06X}")

    # Split into chunks for upload
    chunk_num = 1
    offset = 0
    chunk_files = []
    while offset < len(all_data):
        chunk = all_data[offset:offset + CHUNK_SIZE]
        chunk_path = os.path.join(data_dir, f'snd_c{chunk_num}.bin')
        with open(chunk_path, 'wb') as f:
            f.write(chunk)
        chunk_files.append((chunk_path, len(chunk), chunk_num))
        print(f"  Chunk {chunk_num}: {os.path.basename(chunk_path)} "
              f"({len(chunk)} bytes, {(len(chunk)+255)//256} pages)")
        chunk_num += 1
        offset += CHUNK_SIZE

    # Generate ASM include
    asm_path = os.path.join(data_dir, 'sound_tables.asm')
    with open(asm_path, 'w') as f:
        f.write("; Auto-generated sound VRAM address tables\n")
        f.write(f"; {len(entries)} sounds, {len(all_data)} bytes total\n")
        f.write(f"; VRAM ${VRAM_BASE:06X}-${VRAM_BASE+len(all_data)-1:06X}\n\n")

        # Start addresses
        f.write("; Start bank (with BANK_EN)\n")
        f.write("sfx_vbank\n")
        for name, const, start, end, size, dur in entries:
            bank, lo, hi = vram_to_bank_ptr(start)
            f.write(f"        dta ${bank:02X}  ; {const} ({name})\n")

        f.write("\n; Start pointer lo (within MEMAC $9000 window)\n")
        f.write("sfx_vptr_lo\n")
        for name, const, start, end, size, dur in entries:
            bank, lo, hi = vram_to_bank_ptr(start)
            f.write(f"        dta ${lo:02X}  ; {const}\n")

        f.write("\n; Start pointer hi\n")
        f.write("sfx_vptr_hi\n")
        for name, const, start, end, size, dur in entries:
            bank, lo, hi = vram_to_bank_ptr(start)
            f.write(f"        dta ${hi:02X}  ; {const}\n")

        # End addresses
        f.write("\n; End bank (with BANK_EN)\n")
        f.write("sfx_vbank_end\n")
        for name, const, start, end, size, dur in entries:
            bank, lo, hi = vram_to_bank_ptr(end)
            f.write(f"        dta ${bank:02X}  ; {const}\n")

        f.write("\n; End pointer lo\n")
        f.write("sfx_vend_lo\n")
        for name, const, start, end, size, dur in entries:
            bank, lo, hi = vram_to_bank_ptr(end)
            f.write(f"        dta ${lo:02X}  ; {const}\n")

        f.write("\n; End pointer hi\n")
        f.write("sfx_vend_hi\n")
        for name, const, start, end, size, dur in entries:
            bank, lo, hi = vram_to_bank_ptr(end)
            f.write(f"        dta ${hi:02X}  ; {const}\n")

        f.write(f"\nSND_NUM_CHUNKS = {len(chunk_files)}\n")
        f.write(f"SND_VRAM_BASE_BANK = ${(VRAM_BASE >> 12) | BANK_EN:02X}\n")

    print(f"\nASM tables: {asm_path}")
    print(f"Upload chunks: {len(chunk_files)}")


if __name__ == '__main__':
    main()
