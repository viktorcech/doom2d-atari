;==============================================
; DOOM2D - Data tables and binary includes
; data.asm
;==============================================

; ============================================
; SPRITE TABLES (auto-generated in sprite_defs.asm)
; ============================================
        icl 'sprite_defs.asm'

; ============================================
; MAP DATA - stored in VRAM bank $1E, accessed via MEMAC-A at $9000
; ============================================
map_data = MEMW              ; $9000 (MEMAC window = VRAM $01E000+)

; ============================================
; LEVEL STATE
; ============================================
current_level   dta 0           ; 0-based level index
num_levels      dta 2           ; total levels on disk (update when adding maps!)
pl_start_x      dta a(0)        ; player spawn X (16-bit, set by load_level)
pl_start_y      dta 0           ; player spawn Y (set by load_level)
num_en          dta 0           ; enemy count (set by load_level)
num_pk          dta 0           ; pickup count (set by load_level)
num_dc          dta 0           ; decoration count (set by load_level)

; ============================================
; ENTITY SPAWN DATA (RAM buffers, filled by load_level from disk)
; Initial values from map1 for XEX-only fallback.
; ============================================
        icl '../data/map1_ent.asm'

; ============================================
; BINARY DATA
; ============================================
; palette_data moved to INI segment in main.asm (saves 768B RAM)
; tilesheet_data moved to INI segment in main.asm (saves 4KB RAM)
; hud_font_data moved to INI segment in main.asm (saves 768B RAM)

; ============================================
; Y-ADDRESS LUT (200 entries, Y*320 low/high)
; Used by calc_dst for fast screen address calc
; ============================================
y_addr_lo
:200    dta <[#*320]

y_addr_hi
:200    dta >[#*320]

; ============================================
; PIXEL-TO-TILE LUT: div16_lut[i] = i / 16
; Replaces 4x LSR (8 cycles) with single LDX+LDA (6 cycles)
; Used in get_tile_at, mark_dirty_sprite, get_player_tile_col
; ============================================
div16_lut
:256    dta [# / 16]

; Spritesheet is loaded via multi-segment (see main.asm)
; NOT included here - would exceed $C000 RAM limit
