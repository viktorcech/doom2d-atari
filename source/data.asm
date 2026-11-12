;==============================================
; DOOM2D - Data tables and binary includes
; data.asm
;==============================================

; ============================================
; SPRITE TABLES (auto-generated in sprite_defs.asm)
; ============================================
        icl 'sprite_defs.asm'
        icl 'gen/mon_frames.asm'

; ============================================
; LEVEL STATE
; ============================================
current_level   dta 0           ; 0-based level index
start_level     dta 0           ; new game's first level (mapedit: bin/doom2d_level.atr)
num_levels      dta LVL_COUNT   ; levels on disk (build_doom2d.py: gen/atr_layout_const.asm)
pl_start_x      dta a(0)        ; player spawn X (16-bit, set by load_level)
pl_start_y      dta 0           ; player spawn Y lo (set by load_level)
pl_start_y_hi   dta 0           ; player spawn Y hi (16-bit for tall maps)

; foreground layer state (fore.asm; its code block ends at $BE00)
fu_c0   dta 0                   ; sprites' cells (order kept: c0, c1, r0, r1)
fu_c1   dta 0
fu_r0   dta 0
fu_r1   dta 0
fo_p    dta 0,0                 ; first foreground slot of the frame
fo_n    dta 0                   ; foreground slots used
fo_c1   dta 0                   ; first column / row past the view
fo_r1   dta 0
fo_bx0  dta 0
fo_bx1  dta 0
fo_bx   dta 0
fo_by   dta 0
fo_by1  dta 0
fo_b    dta 0
fo_i    dta 0
fo_c0   dta 0
fo_cw   dta 0
fo_n1   dta 0
fo_n2   dta 0
fo_r0   dta 0
fo_rh   dta 0
fo_m1   dta 0
fo_m2   dta 0
fo_x    dta 0,0
fo_y    dta 0
fo_cl   dta 0
fo_ct   dta 0
fo_s    dta 0,0,0

; ============================================
; ENTITY SPAWN DATA (RAM buffers, filled by load_level from disk)
; ============================================
enemy_spawn_x
        :MAX_ENEMIES dta a(0)
enemy_spawn_y
        :MAX_ENEMIES dta 0
enemy_spawn_type
        :MAX_ENEMIES dta 0
enemy_spawn_dir
        :MAX_ENEMIES dta 0
enemy_spawn_sleep
        :MAX_ENEMIES dta 0
pickup_spawn_x
        :MAX_PICKUPS dta 0
pickup_spawn_xhi
        :MAX_PICKUPS dta 0
pickup_spawn_y
        :MAX_PICKUPS dta 0
pickup_spawn_type
        :MAX_PICKUPS dta 0
decor_spawn_x
        :MAX_DECOR dta 0
decor_spawn_xhi
        :MAX_DECOR dta 0
decor_spawn_y
        :MAX_DECOR dta 0
enemy_spawn_yhi
        :MAX_ENEMIES dta 0
pickup_spawn_yhi
        :MAX_PICKUPS dta 0
decor_spawn_yhi
        :MAX_DECOR dta 0

; ============================================
; BINARY DATA
; ============================================
; palette_data moved to INI segment in main.asm (saves 768B RAM)
; hud_font_data moved to INI segment in main.asm (saves 768B RAM)

; ============================================
; PIXEL-TO-CELL LUT: div8_lut[i] = i / TW (low byte of a world coordinate;
; cell = hi*32 | div8_lut[lo]). Page-aligned at $1F00 (no page-cross).
; ============================================
div8_save = *
        org $1F00
div8_lut
        :256 dta [# / TW]
        org div8_save
        ert TW<>8

; The levels' first sectors (build_doom2d.py): after the lifts' arrays in the
; gap behind the last sky display list (triggers.asm)
levels_save = *
        org n_lf+1
        icl 'gen/atr_levels.asm'
ts_walls    dta 0               ; the level's sizes (diskio.asm: header +6,
ts_bg       dta 0               ; +7, +10): tileset sectors, trigger panel
tpc_sectors dta 0               ; cell sectors
        ert *>$1B00
        org levels_save

; Monster/player animation tables: free RAM below the code ($0C00-$0C45
; and the pages up to $1A45 are free since the sky left ANTIC).
anims_save = *
        org $0C00+582
        icl 'gen/mon_anims.asm'
        ert *>$1000
        org anims_save

; Spritesheet is loaded via multi-segment (see main.asm)
; NOT included here - would exceed $C000 RAM limit
