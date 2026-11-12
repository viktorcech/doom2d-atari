;==============================================
; DOOM2D - Game utilities (init, tile collision, sound)
; game.asm
;==============================================

; ============================================
; INIT GAME
; ============================================
; (init_player reads/writes none of zfr / level_complete / stat_*, so it may
;  run before init_level_ents zeroes them)
.proc init_game
        lda #0
        sta zfr
        jsr init_player
        jsr init_level_ents
        jsr init_eproj
        lda #$FF                ; Z=0: main's new-game path branches on it
        rts
.endp
; (init_level_ents is in main.asm, in front of init_decorations)

; ============================================
; GET_TILE_AT16 - tile at pixel (gt_px_hi:gt_px, gt_py_hi:gt_py).
; Output: A = tile (out of map = 1, solid), ztptr -> tile with its map bank
; selected (callers write doors/switches), gt_col/gt_row. X is PRESERVED.
; ============================================
.proc get_tile_at16
        ldy gt_px               ; col = hi*32 | lo/8: lsr + 3x ror = hi*32 for
        lda gt_px_hi            ; hi 0..3; hi 4..7 and -5..-1 give >= MAP_W
        lsr                     ; (out of the map)
        ror
        ror
        ror
        ora div8_lut,y
        cmp #MAP_W
        bcs ?oob
        sta gt_col
        ldy gt_py               ; row = hi*32 | lo/8 (the same)
        lda gt_py_hi
        lsr
        ror
        ror
        ror
        ora div8_lut,y
        cmp #MAP_H
        bcs ?oob
        sta gt_row          ; keep gt_row valid for callers (switch code)
        tay
        lda map_row_bank,y
        sta VBXE_BANK_SEL
        lda map_row_lo,y        ; C=0 (bcs ?oob not taken)
        adc gt_col
        sta ztptr
        lda map_row_hi,y
        adc #0
        sta ztptr+1
        ldy #0
        lda (ztptr),y
        rts
?oob    lda #1
        rts
.endp

; CHECK_SOLID16 / CHECK_SOLID_OR_PLATFORM16 - 16-bit-Y versions (player).
; X register preserved (uses Y for the table lookup).
.proc check_solid16
        jsr get_tile_at16
        bmi ?pass
        tay
        lda tile_solid,y
        rts
?pass   lda #0
        rts
.endp

.proc check_solid_or_platform16
        jsr get_tile_at16
        bmi ?pass
        tay
        lda tile_oneway,y
        bne ?plat               ; tile_oneway is 0/1: A = 1 already
        lda tile_solid,y
?plat   rts
?pass   lda #0
        rts
.endp

; ============================================
; ABS16 - absolute value of a 16-bit difference, clamped to one byte.
; In:  abs16.ab_lo = low byte of (a-b), A = high byte of (a-b), N/Z = A
;      (every caller ends on the sbc that made A: no cmp #0 needed)
; Out: C=1 -> A = |a-b| (0..255)
;      C=0 -> |a-b| >= 256, out of any blast/hit radius
; Clobbers A only - X and Y are preserved, so it drops into loops indexed
; either way. (Replaces every hand-rolled copy of this pattern in the tree.)
; ============================================
.proc abs16
        beq ?pos                ; hi = 0 -> difference is already 0..255
        cmp #$FF
        bne ?far                ; hi != $FF -> further than 255 px
        lda ab_lo               ; C=1 from the equal cmp #$FF
        beq ?far                ; hi=$FF, lo=0 -> exactly -256
        eor #$FF
        adc #0                  ; C=1: A = ~ab_lo + 1 = 0 - ab_lo
        sec
        rts
?pos    lda ab_lo
        sec
        rts
?far    clc
        rts
ab_lo   dta 0
.endp

; ============================================
; WORLD_TO_TILE - 16-bit world point -> wt_col / wt_row.
; Callers only use it for entities that are already inside the map.
; Clobbers A, Y. Preserves X.
; ============================================
.proc world_to_tile
        lda wt_xhi
        asl
        asl
        asl
        asl
        asl                     ; hi * 32 (low 5 bits 0 -> ORA = ADD)
        ldy wt_x
        ora div8_lut,y
        sta wt_col
        lda wt_yhi
        asl
        asl
        asl
        asl
        asl
        ldy wt_y
        ora div8_lut,y
        sta wt_row
        rts
.endp

; ============================================
; CALC MAP POINTER
; Input: r_row, r_col (tile coords)
; Output: ztptr = address of the tile in the MEMAC window, its bank selected
; ============================================
.proc calc_map_ptr
        ldy r_row
        lda map_row_bank,y
        sta VBXE_BANK_SEL
        lda map_row_lo,y
        clc
        adc r_col
        sta ztptr
        lda map_row_hi,y
        adc #0
        sta ztptr+1
        rts
.endp

; ============================================
; PLAYER CELL HELPERS (pickups). Preserve X (Y is the LUT index).
; ============================================

; Player tile col from zpx, zpx_hi → A
.proc get_player_tile_col
        ldy zpx
        lda zpx_hi
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,y       ; hi*32 | zpx/8
        rts
.endp

; Player row of (zpy_hi:zpy) - A (A = pixels above the feet) → A (16-bit Y)
.proc get_player_row
        eor #$FF                ; zpy + ~A + 1 = zpy - A: the same add the
        sec                     ; sbc does (result and C identical)
        adc zpy
        tay
        lda zpy_hi
        sbc #0
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,y          ; hi*32 | lo/8
        rts
.endp

; Map row LUTs (free RAM below the main segment, each table inside one page):
; row R lives in VRAM bank BANK_MAP + R/MAP_RPB at MEMW + (R mod MAP_RPB)*
; MAP_STRIDE: a row never straddles a bank or a page; map_row_bank holds the
; BANK_SEL value.
map_lut_save = *
        org $1B00
map_row_lo
        :MAP_H dta <[MEMW + [# - [#/MAP_RPB]*MAP_RPB]*MAP_STRIDE]
map_row_hi
        :MAP_H dta >[MEMW + [# - [#/MAP_RPB]*MAP_RPB]*MAP_STRIDE]
        ert >*<>$1B
        org $1C00
map_row_bank
        :MAP_H dta BANK_EN+BANK_MAP+[#/MAP_RPB]
; the rest of the page: trigger actions (triggers_shot.asm)
        icl 'triggers_shot.asm'
        ert *>$1D00
        org map_lut_save


; ============================================
; TILE BEHAVIOUR TABLES - per level, 256 entries each, loaded with the level
; (diskio.asm load_map_tiles from tools/d2df2map.py): tile_solid 1 = wall,
; tile_oneway 1 = platform (solid only from above). Ids 128-255 are
; background (passable: callers test bit 7 first). Page-aligned free RAM
; below the code.
; ============================================
tile_solid      = $0B00
tile_oneway     = $1D00         ; [128]: ids 0..127 (a background id is never read)
                                ; $1D80-$1DFF: bl_s7 (blood.asm)

; sound_update is in sound.asm
