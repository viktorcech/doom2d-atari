#!/usr/bin/env python3
"""
DOOM WAD Sprite & Sound Extractor for Doom2D Atari Project

Extracts sprites and sounds from DOOM WAD files and converts them
to formats suitable for the Atari VBXE engine:
- Sprites: raw 8bpp indexed bitmap (16x16, 32x32 etc.)
- Sounds: raw 8-bit unsigned PCM
- Palette: RGB triplets for VBXE palette registers

Usage:
    python wad_extract.py <doom.wad> [--sprites] [--sounds] [--palette]
    python wad_extract.py doom2.wad --sprites --output sprites/
    python wad_extract.py doom2.wad --sounds --output sounds/
    python wad_extract.py doom2.wad --palette --output palette/

Requires: PIL/Pillow (for PNG export), struct (stdlib)
"""

import struct
import os
import sys
import argparse
from pathlib import Path

# ============================================
# WAD file parser
# ============================================

class WADLump:
    """Single lump (entry) in a WAD file."""
    def __init__(self, name, offset, size):
        self.name = name
        self.offset = offset
        self.size = size
        self.data = None

class WADFile:
    """Parser for DOOM WAD files (IWAD/PWAD)."""

    def __init__(self, filename):
        self.filename = filename
        self.lumps = []
        self.lump_map = {}
        self._parse()

    def _parse(self):
        with open(self.filename, 'rb') as f:
            # Header: 4 bytes ID, 4 bytes numlumps, 4 bytes directory offset
            header = f.read(12)
            wad_type, num_lumps, dir_offset = struct.unpack('<4sII', header)
            wad_type = wad_type.decode('ascii')

            if wad_type not in ('IWAD', 'PWAD'):
                raise ValueError(f"Not a valid WAD file: {wad_type}")

            print(f"WAD type: {wad_type}, Lumps: {num_lumps}")

            # Read directory
            f.seek(dir_offset)
            for i in range(num_lumps):
                entry = f.read(16)
                offset, size = struct.unpack('<II', entry[:8])
                name = entry[8:16].decode('ascii').rstrip('\x00')
                lump = WADLump(name, offset, size)
                self.lumps.append(lump)
                self.lump_map[name] = lump

    def read_lump(self, name):
        """Read lump data by name."""
        if name not in self.lump_map:
            return None
        lump = self.lump_map[name]
        with open(self.filename, 'rb') as f:
            f.seek(lump.offset)
            return f.read(lump.size)

    def get_lumps_between(self, start_marker, end_marker):
        """Get all lumps between two marker lumps."""
        result = []
        inside = False
        for lump in self.lumps:
            if lump.name == start_marker:
                inside = True
                continue
            if lump.name == end_marker:
                break
            if inside and lump.size > 0:
                result.append(lump)
        return result


# ============================================
# Wall texture extraction (composite patches)
# ============================================

def parse_patch(data):
    """Parse a DOOM patch (column-based sprite format).
    Returns (width, height, pixels) where pixels is a dict of (x,y)->palette_index.
    """
    if len(data) < 8:
        return None
    width, height, left_off, top_off = struct.unpack('<HHhh', data[:8])
    if width > 4096 or height > 4096:
        return None
    pixels = {}
    # Column offsets table
    col_offsets = struct.unpack(f'<{width}I', data[8:8+width*4])
    for col in range(width):
        offset = col_offsets[col]
        if offset >= len(data):
            continue
        while offset < len(data):
            row_start = data[offset]
            if row_start == 0xFF:
                break
            pixel_count = data[offset + 1]
            # skip padding byte
            offset += 3
            for i in range(pixel_count):
                if offset + i < len(data):
                    pixels[(col, row_start + i)] = data[offset + i]
            offset += pixel_count + 1  # skip trailing padding
    return width, height, pixels


def extract_wall_texture(wad, texture_name):
    """Extract a composite wall texture from DOOM WAD.
    Reads TEXTURE1 lump, finds the texture definition, composites patches.
    Returns (width, height, raw_bytes) or None.
    """
    tex_data = wad.read_lump('TEXTURE1')
    if not tex_data:
        return None

    # PNAMES lump - patch name lookup table
    pnames_data = wad.read_lump('PNAMES')
    if not pnames_data:
        return None
    num_pnames = struct.unpack('<I', pnames_data[:4])[0]
    pnames = []
    for i in range(num_pnames):
        off = 4 + i * 8
        name = pnames_data[off:off+8].decode('ascii').rstrip('\x00')
        pnames.append(name)

    # Parse TEXTURE1 directory
    num_textures = struct.unpack('<I', tex_data[:4])[0]
    tex_offsets = struct.unpack(f'<{num_textures}I', tex_data[4:4+num_textures*4])

    for i in range(num_textures):
        off = tex_offsets[i]
        name = tex_data[off:off+8].decode('ascii').rstrip('\x00')
        if name != texture_name:
            continue

        # Found it - parse texture definition
        # Format: name(8) + unused(4) + width(2) + height(2) + unused(4) + patchcount(2)
        width, height = struct.unpack('<HH', tex_data[off+12:off+16])
        num_patches = struct.unpack('<H', tex_data[off+20:off+22])[0]

        # Create pixel buffer (0 = transparent)
        pixels = bytearray(width * height)

        # Composite patches
        for p in range(num_patches):
            poff = off + 22 + p * 10
            origin_x, origin_y, patch_idx = struct.unpack('<hhH', tex_data[poff:poff+6])

            if patch_idx >= len(pnames):
                continue
            patch_name = pnames[patch_idx]
            patch_data = wad.read_lump(patch_name)
            if not patch_data:
                continue

            result = parse_patch(patch_data)
            if not result:
                continue
            pw, ph, ppixels = result

            for (px, py), color in ppixels.items():
                dx = origin_x + px
                dy = origin_y + py
                if 0 <= dx < width and 0 <= dy < height:
                    pixels[dy * width + dx] = color

        return width, height, bytes(pixels)

    return None


# ============================================
# Palette extraction
# ============================================

def extract_palette(wad):
    """Extract PLAYPAL lump - first palette (256 RGB triplets)."""
    data = wad.read_lump('PLAYPAL')
    if not data:
        print("ERROR: PLAYPAL lump not found!")
        return None
    # First 768 bytes = palette 0 (256 * 3 bytes RGB)
    palette = []
    for i in range(256):
        r = data[i * 3]
        g = data[i * 3 + 1]
        b = data[i * 3 + 2]
        palette.append((r, g, b))
    return palette


def brighten_7bit(val8, gamma=1.0):
    """Convert 8-bit color to 7-bit VBXE with optional gamma correction.
    gamma < 1.0 brightens dark tones, 1.0 = linear (no correction).
    """
    normalized = val8 / 255.0
    corrected = normalized ** gamma
    return min(127, int(corrected * 127))


def save_palette_vbxe(palette, output_dir):
    """Save palette as binary file for VBXE (256 R values, 256 G, 256 B)."""
    os.makedirs(output_dir, exist_ok=True)

    # VBXE format: 256 reds, then 256 greens, then 256 blues
    # Each value is 7-bit (0-127) with gamma correction for brightness
    r_vals = bytes([brighten_7bit(c[0]) for c in palette])
    g_vals = bytes([brighten_7bit(c[1]) for c in palette])
    b_vals = bytes([brighten_7bit(c[2]) for c in palette])

    with open(os.path.join(output_dir, 'palette.bin'), 'wb') as f:
        f.write(r_vals + g_vals + b_vals)

    print(f"Palette saved: {output_dir}/palette.bin (768 bytes)")

    # Also save as human-readable text
    with open(os.path.join(output_dir, 'palette.txt'), 'w') as f:
        for i, (r, g, b) in enumerate(palette):
            f.write(f"{i:3d}: R={r:3d} G={g:3d} B={b:3d}  (VBXE: {r>>1:3d},{g>>1:3d},{b>>1:3d})\n")

    print(f"Palette text: {output_dir}/palette.txt")


# ============================================
# Sprite extraction
# ============================================

def decode_doom_picture(data, palette):
    """Decode a DOOM picture/patch format sprite.

    Returns: (width, height, left_offset, top_offset, pixels)
    where pixels is a list of (r, g, b, a) tuples or None for transparent.
    """
    if len(data) < 8:
        return None

    width, height, left_off, top_off = struct.unpack('<HHhh', data[:8])

    if width > 512 or height > 512 or width == 0 or height == 0:
        return None

    # Read column offsets
    col_offsets = []
    for x in range(width):
        offset = struct.unpack('<I', data[8 + x * 4:12 + x * 4])[0]
        col_offsets.append(offset)

    # Create pixel buffer (RGBA)
    pixels = [None] * (width * height)

    # Decode each column
    for x in range(width):
        offset = col_offsets[x]
        if offset >= len(data):
            continue

        while offset < len(data):
            topdelta = data[offset]
            offset += 1

            if topdelta == 0xFF:
                break  # End of column

            length = data[offset]
            offset += 1
            offset += 1  # Skip padding byte

            for y in range(length):
                if offset >= len(data):
                    break
                pixel_y = topdelta + y
                if 0 <= pixel_y < height:
                    color_idx = data[offset]
                    if palette:
                        r, g, b = palette[color_idx]
                        pixels[pixel_y * width + x] = (r, g, b, 255, color_idx)
                    else:
                        pixels[pixel_y * width + x] = (color_idx, color_idx, color_idx, 255, color_idx)
                offset += 1

            offset += 1  # Skip trailing padding

    return (width, height, left_off, top_off, pixels)


def save_sprite_raw(sprite_data, output_path, target_w=None, target_h=None):
    """Save sprite as raw 8bpp indexed data for Atari VBXE.

    If target_w/target_h specified, sprite is centered/padded to that size.
    Transparent pixels = color index 0.
    """
    width, height, loff, toff, pixels = sprite_data

    out_w = target_w or width
    out_h = target_h or height

    raw = bytearray(out_w * out_h)

    # Center sprite in output
    ox = (out_w - width) // 2
    oy = (out_h - height) // 2

    for y in range(height):
        for x in range(width):
            px = pixels[y * width + x]
            if px is not None:
                dx = ox + x
                dy = oy + y
                if 0 <= dx < out_w and 0 <= dy < out_h:
                    raw[dy * out_w + dx] = px[4]  # color index

    with open(output_path, 'wb') as f:
        f.write(raw)


def save_sprite_png(sprite_data, output_path, palette):
    """Save sprite as PNG (for preview)."""
    try:
        from PIL import Image
    except ImportError:
        print("  (Pillow not installed, skipping PNG export)")
        return

    width, height, _, _, pixels = sprite_data

    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    for y in range(height):
        for x in range(width):
            px = pixels[y * width + x]
            if px is not None:
                img.putpixel((x, y), (px[0], px[1], px[2], px[3]))

    img.save(output_path)


def extract_sprites(wad, output_dir, palette, sprite_size=32):
    """Extract all sprites from WAD."""
    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(os.path.join(output_dir, 'raw'), exist_ok=True)
    os.makedirs(os.path.join(output_dir, 'png'), exist_ok=True)

    sprite_lumps = wad.get_lumps_between('S_START', 'S_END')
    if not sprite_lumps:
        # Try SS_START/SS_END
        sprite_lumps = wad.get_lumps_between('SS_START', 'SS_END')

    if not sprite_lumps:
        print("No sprite lumps found!")
        return

    print(f"Found {len(sprite_lumps)} sprite lumps")

    count = 0
    for lump in sprite_lumps:
        data = wad.read_lump(lump.name)
        if not data:
            continue

        sprite = decode_doom_picture(data, palette)
        if sprite is None:
            continue

        width, height, loff, toff, pixels = sprite
        print(f"  {lump.name}: {width}x{height} (offset: {loff},{toff})")

        # Save raw indexed data (padded to sprite_size x sprite_size)
        raw_path = os.path.join(output_dir, 'raw', f'{lump.name}.bin')
        save_sprite_raw(sprite, raw_path, sprite_size, sprite_size)

        # Save PNG preview
        png_path = os.path.join(output_dir, 'png', f'{lump.name}.png')
        save_sprite_png(sprite, png_path, palette)

        count += 1

    print(f"Extracted {count} sprites")

    # Create sprite sheet (multiple sprites packed sequentially)
    # For VBXE: just concatenate raw files in order
    sheet_path = os.path.join(output_dir, 'spritesheet.bin')
    with open(sheet_path, 'wb') as sheet:
        for lump in sprite_lumps:
            raw_path = os.path.join(output_dir, 'raw', f'{lump.name}.bin')
            if os.path.exists(raw_path):
                with open(raw_path, 'rb') as rf:
                    sheet.write(rf.read())

    print(f"Sprite sheet: {sheet_path}")


# ============================================
# Sound extraction
# ============================================

def extract_sounds(wad, output_dir):
    """Extract all DS* sound lumps and convert to WAV."""
    os.makedirs(output_dir, exist_ok=True)
    os.makedirs(os.path.join(output_dir, 'wav'), exist_ok=True)
    os.makedirs(os.path.join(output_dir, 'raw'), exist_ok=True)

    count = 0
    for lump in wad.lumps:
        if not lump.name.startswith('DS'):
            continue
        if lump.size < 8:
            continue

        data = wad.read_lump(lump.name)
        if not data:
            continue

        # Parse DMX sound header
        fmt_type, sample_rate, num_samples = struct.unpack('<HHI', data[:8])

        if fmt_type != 3:
            print(f"  {lump.name}: unknown format {fmt_type}, skipping")
            continue

        # Audio data starts at offset 8
        # Includes 16 padding bytes (8 before, 8 after actual audio)
        pcm_data = data[8:8 + num_samples]

        print(f"  {lump.name}: {sample_rate}Hz, {num_samples} samples, "
              f"{num_samples / sample_rate:.2f}s")

        # Save as WAV
        wav_path = os.path.join(output_dir, 'wav', f'{lump.name}.wav')
        save_wav(pcm_data, sample_rate, wav_path)

        # Save raw PCM (for direct use on Atari)
        raw_path = os.path.join(output_dir, 'raw', f'{lump.name}.raw')
        with open(raw_path, 'wb') as f:
            f.write(pcm_data)

        # Save downsampled version for POKEY (lower sample rate)
        # POKEY typically works at much lower rates
        # We'll save a 4-bit version at ~4kHz for POKEY playback
        pokey_path = os.path.join(output_dir, 'raw', f'{lump.name}_pokey.raw')
        save_pokey_format(pcm_data, sample_rate, pokey_path)

        count += 1

    print(f"Extracted {count} sound effects")


def save_wav(pcm_data, sample_rate, output_path):
    """Save PCM data as WAV file."""
    data_size = len(pcm_data)
    file_size = 36 + data_size

    with open(output_path, 'wb') as f:
        # RIFF header
        f.write(b'RIFF')
        f.write(struct.pack('<I', file_size))
        f.write(b'WAVE')

        # fmt chunk
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))          # chunk size
        f.write(struct.pack('<H', 1))           # PCM format
        f.write(struct.pack('<H', 1))           # mono
        f.write(struct.pack('<I', sample_rate))  # sample rate
        f.write(struct.pack('<I', sample_rate))  # byte rate
        f.write(struct.pack('<H', 1))           # block align
        f.write(struct.pack('<H', 8))           # bits per sample

        # data chunk
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        f.write(pcm_data)


def save_pokey_format(pcm_data, original_rate, output_path, target_rate=4000):
    """Downsample and convert to 4-bit for POKEY playback."""
    # Simple decimation
    ratio = original_rate / target_rate
    out = bytearray()

    i = 0.0
    while int(i) < len(pcm_data):
        sample = pcm_data[int(i)]
        # Convert 8-bit unsigned to 4-bit (0-15) for POKEY volume
        out.append(sample >> 4)
        i += ratio

    with open(output_path, 'wb') as f:
        f.write(out)


# ============================================
# Main
# ============================================

def main():
    parser = argparse.ArgumentParser(description='DOOM WAD Extractor for Atari VBXE')
    parser.add_argument('wadfile', help='Path to DOOM WAD file')
    parser.add_argument('--sprites', action='store_true', help='Extract sprites')
    parser.add_argument('--sounds', action='store_true', help='Extract sounds')
    parser.add_argument('--palette', action='store_true', help='Extract palette')
    parser.add_argument('--all', action='store_true', help='Extract everything')
    parser.add_argument('--output', '-o', default='extracted',
                        help='Output directory')
    parser.add_argument('--sprite-size', type=int, default=32,
                        help='Target sprite size (default: 32x32)')
    parser.add_argument('--list', action='store_true',
                        help='List all lumps in WAD')

    args = parser.parse_args()

    if not os.path.exists(args.wadfile):
        print(f"ERROR: File not found: {args.wadfile}")
        sys.exit(1)

    print(f"Opening: {args.wadfile}")
    wad = WADFile(args.wadfile)

    if args.list:
        print(f"\nAll lumps ({len(wad.lumps)}):")
        for lump in wad.lumps:
            print(f"  {lump.name:8s}  offset={lump.offset:8d}  size={lump.size:8d}")
        return

    if args.all:
        args.sprites = args.sounds = args.palette = True

    if not (args.sprites or args.sounds or args.palette):
        print("Specify --sprites, --sounds, --palette, or --all")
        sys.exit(1)

    palette = extract_palette(wad)

    if args.palette and palette:
        save_palette_vbxe(palette, os.path.join(args.output, 'palette'))

    if args.sprites:
        extract_sprites(wad, os.path.join(args.output, 'sprites'),
                       palette, args.sprite_size)

    if args.sounds:
        extract_sounds(wad, os.path.join(args.output, 'sounds'))

    print("\nDone!")


if __name__ == '__main__':
    main()
