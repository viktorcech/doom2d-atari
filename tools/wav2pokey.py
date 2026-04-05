#!/usr/bin/env python3
"""
wav2pokey.py - Convert WAV files to 4-bit packed nibble format for Atari POKEY
             volume-only playback (Dynakillers-style)

Usage: python wav2pokey.py input.wav output.bin [sample_rate]

Input:  Any WAV file (mono/stereo, any sample rate, 8/16 bit)
Output: Binary file with 4-bit packed nibbles (2 samples per byte)
        Hi nibble = first sample, Lo nibble = second sample

Default target sample rate: 3959 Hz (PAL POKEY Timer 1 with AUDF=15)
"""

import sys
import struct
import os

def read_wav(path):
    """Read WAV file, return (sample_rate, samples as float array -1..+1)"""
    with open(path, 'rb') as f:
        data = f.read()

    # Parse RIFF header
    assert data[:4] == b'RIFF', "Not a RIFF file"
    assert data[8:12] == b'WAVE', "Not a WAVE file"

    fmt_data = None
    audio_data = None
    i = 12
    while i < len(data) - 8:
        chunk_id = data[i:i+4]
        chunk_size = struct.unpack('<I', data[i+4:i+8])[0]
        if chunk_id == b'fmt ':
            fmt_data = data[i+8:i+8+chunk_size]
        elif chunk_id == b'data':
            audio_data = data[i+8:i+8+chunk_size]
        i += 8 + chunk_size
        # Align to even boundary
        if chunk_size % 2:
            i += 1

    assert fmt_data is not None, "No fmt chunk"
    assert audio_data is not None, "No data chunk"

    audio_fmt = struct.unpack('<H', fmt_data[0:2])[0]
    channels = struct.unpack('<H', fmt_data[2:4])[0]
    sample_rate = struct.unpack('<I', fmt_data[4:8])[0]
    bits = struct.unpack('<H', fmt_data[14:16])[0]

    assert audio_fmt == 1, f"Not PCM (format={audio_fmt})"

    # Convert to float samples
    samples = []
    if bits == 8:
        # 8-bit unsigned (0-255, center at 128)
        for b in audio_data:
            samples.append((b - 128) / 128.0)
    elif bits == 16:
        # 16-bit signed
        for j in range(0, len(audio_data), 2):
            s = struct.unpack('<h', audio_data[j:j+2])[0]
            samples.append(s / 32768.0)
    else:
        raise ValueError(f"Unsupported bit depth: {bits}")

    # Mix to mono if stereo
    if channels == 2:
        mono = []
        for j in range(0, len(samples), 2):
            mono.append((samples[j] + samples[j+1]) / 2.0)
        samples = mono

    return sample_rate, samples


def resample(samples, src_rate, dst_rate):
    """Simple linear interpolation resampling"""
    ratio = src_rate / dst_rate
    out_len = int(len(samples) / ratio)
    out = []
    for i in range(out_len):
        src_pos = i * ratio
        idx = int(src_pos)
        frac = src_pos - idx
        if idx + 1 < len(samples):
            val = samples[idx] * (1 - frac) + samples[idx + 1] * frac
        else:
            val = samples[idx] if idx < len(samples) else 0
        out.append(val)
    return out


def normalize(samples):
    """Normalize to full -1..+1 range"""
    peak = max(abs(s) for s in samples)
    if peak > 0:
        return [s / peak for s in samples]
    return samples


def trim_silence(samples, threshold=0.02):
    """Trim leading and trailing silence"""
    # Find first non-silent sample
    start = 0
    for i, s in enumerate(samples):
        if abs(s) > threshold:
            start = max(0, i - 4)  # keep 4 samples before
            break

    # Find last non-silent sample
    end = len(samples)
    for i in range(len(samples) - 1, -1, -1):
        if abs(samples[i]) > threshold:
            end = min(len(samples), i + 4)  # keep 4 samples after
            break

    return samples[start:end]


def to_4bit_packed(samples):
    """Convert float samples to 4-bit packed nibbles.
    Hi nibble = first sample, Lo nibble = second sample.
    Returns bytes."""
    # Convert to 0-15 range
    nibbles = []
    for s in samples:
        val = int((s + 1.0) * 7.5)  # -1..+1 -> 0..15
        val = max(0, min(15, val))
        nibbles.append(val)

    # Pad to even count
    if len(nibbles) % 2:
        nibbles.append(8)  # midpoint (silence)

    # Pack: hi nibble first, lo nibble second
    packed = []
    for i in range(0, len(nibbles), 2):
        packed.append((nibbles[i] << 4) | nibbles[i + 1])

    return bytes(packed)


def generate_lookup_table():
    """Generate 256-byte lookup tables for POKEY volume-only mode.
    Index = packed byte, output = AUDC value ($10 | nibble).
    Table 1: hi nibble, Table 2: lo nibble."""
    tab_hi = []
    tab_lo = []
    for b in range(256):
        hi = (b >> 4) & 0x0F
        lo = b & 0x0F
        tab_hi.append(0x10 | hi)  # volume-only mode + volume
        tab_lo.append(0x10 | lo)
    return bytes(tab_hi), bytes(tab_lo)


def main():
    if len(sys.argv) < 3:
        print("Usage: python wav2pokey.py input.wav output.bin [sample_rate] [max_ms]")
        print("Default sample rate: 3959 Hz (PAL POKEY Timer 1, AUDF=15)")
        print("Optional max_ms: maximum duration in milliseconds")
        sys.exit(1)

    wav_path = sys.argv[1]
    out_path = sys.argv[2]
    target_rate = int(sys.argv[3]) if len(sys.argv) > 3 else 3959
    max_ms = int(sys.argv[4]) if len(sys.argv) > 4 else 0

    print(f"Input:  {wav_path}")
    print(f"Output: {out_path}")
    print(f"Target: {target_rate} Hz")

    # Read WAV
    src_rate, samples = read_wav(wav_path)
    print(f"Source: {src_rate} Hz, {len(samples)} samples, {len(samples)/src_rate:.3f}s")

    # Trim silence
    samples = trim_silence(samples)
    print(f"After trim: {len(samples)} samples")

    # Normalize
    samples = normalize(samples)

    # Resample
    samples = resample(samples, src_rate, target_rate)

    # Truncate to max duration if specified
    if max_ms > 0:
        max_samples = int(target_rate * max_ms / 1000)
        if len(samples) > max_samples:
            samples = samples[:max_samples]
            print(f"Truncated to {max_ms}ms: {len(samples)} samples")

    print(f"Resampled: {len(samples)} samples at {target_rate} Hz, {len(samples)/target_rate:.3f}s")

    # Convert to 4-bit packed
    packed = to_4bit_packed(samples)

    # Fade out last ~10ms to silence then append silent bytes
    # Prevents pop when IRQ handler stops (AUDC4 jumps from mid-level to 0)
    fade_bytes = max(int(target_rate * 0.010 / 2), 8)
    if len(packed) > fade_bytes:
        buf = bytearray(packed)
        for i in range(fade_bytes):
            pos = len(buf) - fade_bytes + i
            progress = i / fade_bytes
            hi = (buf[pos] >> 4) & 0xF
            lo = buf[pos] & 0xF
            hi = int(hi * (1.0 - progress))
            lo = int(lo * (1.0 - progress))
            buf[pos] = (hi << 4) | lo
        packed = bytes(buf)
    packed += b'\x00' * 4

    print(f"Packed: {len(packed)} bytes ({len(packed)*2} nibbles)")

    # Write binary
    with open(out_path, 'wb') as f:
        f.write(packed)
    print(f"Written: {out_path} ({len(packed)} bytes)")

    # Also generate lookup tables
    tab_dir = os.path.dirname(out_path)
    tab_hi, tab_lo = generate_lookup_table()

    tab_hi_path = os.path.join(tab_dir, 'snd_tab_hi.bin')
    tab_lo_path = os.path.join(tab_dir, 'snd_tab_lo.bin')
    with open(tab_hi_path, 'wb') as f:
        f.write(tab_hi)
    with open(tab_lo_path, 'wb') as f:
        f.write(tab_lo)
    print(f"Lookup tables: {tab_hi_path}, {tab_lo_path} (256B each)")

    # Stats
    print(f"\nFor ASM:")
    print(f"  Sample length: {len(packed)} bytes (${len(packed):04X})")
    print(f"  Duration: {len(packed)*2/target_rate*1000:.0f} ms")
    print(f"  WSYNC scanlines per sample pair: 2")
    print(f"  Scanlines for full sound: {len(packed)*2}")


if __name__ == '__main__':
    main()
