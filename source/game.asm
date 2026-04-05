;==============================================
; DOOM2D - Game utilities (init, tile collision, sound)
; game.asm
;==============================================

; ============================================
; INIT GAME
; ============================================
.proc init_game
        lda #0
        sta zfr
        sta fps_count
        sta level_complete
        lda RTCLOK3
        sta fps_rtclk
        jsr init_player
        jsr init_enemies
        jsr init_pickups
        jsr init_decorations
        jsr restart_close_doors
        jsr init_doors
        jsr init_eproj
        lda #$FF
        sta ft_prev_col
        sta ft_prev_row
        rts
.endp

; ============================================
; GET TILE AT PIXEL POSITION
; Input: gt_px, gt_py (pixel coords)
; Output: A = tile index from map
; ============================================
.proc get_tile_at
        ; tile_col = (gt_px_hi:gt_px) / 16
        lda gt_px_hi
        asl
        asl
        asl
        asl                 ; hi * 16 (0 or 16)
        sta gt_col
        lda gt_px
        lsr
        lsr
        lsr
        lsr                 ; lo / 16
        clc
        adc gt_col
        sta gt_col
        ; tile_row = gt_py / 16
        lda gt_py
        lsr
        lsr
        lsr
        lsr
        sta gt_row
        ; bounds check
        lda gt_col
        cmp #MAP_W
        bcs ?oob
        sta r_col
        lda gt_row
        cmp #MAP_H
        bcs ?oob
        sta r_row
        jsr calc_map_ptr
        ldy #0
        lda (ztptr),y
        rts
?oob    lda #1             ; out of bounds = solid (wall)
        rts
.endp
gt_px   dta 0
gt_px_hi dta 0
gt_py   dta 0
gt_col  dta 0
gt_row  dta 0

; ============================================
; CALC MAP POINTER
; Input: r_row, r_col (tile coords)
; Output: ztptr = address in map_data
; ============================================
.proc calc_map_ptr
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        ldy r_row
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
; TILE COL HELPERS (shared by LOS, can_hear, pickups, doors)
; ============================================

; Shared temp for tile col helpers
gt_tmp  dta 0

; Enemy tile col from en_x[X], enxhi[X] → A
; (does NOT add +8 center offset — caller does if needed)
.proc get_enemy_tile_col
        lda en_x,x
        lsr
        lsr
        lsr
        lsr
        sta gt_tmp
        lda enxhi,x
        asl
        asl
        asl
        asl
        ora gt_tmp
        rts
.endp

; Player tile col from zpx, zpx_hi → A
.proc get_player_tile_col
        lda zpx
        lsr
        lsr
        lsr
        lsr
        sta gt_tmp
        lda zpx_hi
        asl
        asl
        asl
        asl
        ora gt_tmp
        rts
.endp

; Player center tile col from (zpx+8), zpx_hi → A
.proc get_player_center_col
        lda zpx
        clc
        adc #8
        pha             ; save low byte (preserve carry for zpx_hi)
        lda zpx_hi
        adc #0          ; add carry from zpx+8
        asl
        asl
        asl
        asl
        sta gt_tmp
        pla             ; restore low byte
        lsr
        lsr
        lsr
        lsr
        ora gt_tmp
        rts
.endp

; Map row address LUT: map_data + row * 32 for rows 0-31
map_row_lo
        :32 dta <[map_data + #*32]
map_row_hi
        :32 dta >[map_data + #*32]


; Dirty row base offset LUT: row_x20[i] = i * 20
row_x20
        :13 dta [#*20]

; ============================================
; TILE SOLID TABLE
; 0=passable, 1=solid
; Index: 0=empty 1=wall 2=platform 3=ceil 4=door 5=sky 6=darkbg(wall) 7=tech 8=metal 9=support 10=stone
; ============================================
tile_solid
        dta 0,1,0,1,1,0,1,1,1,1,1
;               ^ floor=0 (one-way)  ^ sky=0  ^ darkbg=1 (wall)
        dta 0,0,0,0         ; 11-14 = floor variants (one-way)
        dta 1                ; 15 = invisible solid (barrel)
        ; New tiles 16-24 (VRAM $032000+):
        dta 1                ; 16 = CEIL3_5 (wall)
        dta 1                ; 17 = CEIL5_1 (wall)
        dta 1                ; 18 = DEM1_1 (wall)
        dta 1                ; 19 = FLAT1 (wall)
        dta 1                ; 20 = FLAT22 (wall)
        dta 0                ; 21 = FLOOR0_6 (one-way)
        dta 1                ; 22 = FLOOR1_1 (wall)
        dta 0                ; 23 = FLOOR5_1 (one-way)
        dta 1                ; 24 = MFLR8_1 (wall)
        dta 1                ; 25 = door red (solid)
        dta 1                ; 26 = door blue (solid)
        dta 1                ; 27 = door yellow (solid)
        dta 0                ; 28 = switch OFF (passable, on wall)
        dta 0                ; 29 = switch ON (passable, on wall)

; ============================================
; ONE-WAY PLATFORM TABLE
; Tiles that are solid only when falling onto them from above
; ============================================
tile_oneway
        dta 0,0,1,0,0,0,0,0,0,0,0
;             ^ floor=one-way
        dta 1,1,1,1          ; 11-14 = floor variants (one-way)
        dta 0                ; 15 = invisible solid (not one-way)
        ; New tiles 16-24:
        dta 0                ; 16 = CEIL3_5 (wall, not one-way)
        dta 0                ; 17 = CEIL5_1 (wall, not one-way)
        dta 0                ; 18 = DEM1_1 (wall, not one-way)
        dta 0                ; 19 = FLAT1 (wall, not one-way)
        dta 0                ; 20 = FLAT22 (wall, not one-way)
        dta 1                ; 21 = FLOOR0_6 (one-way platform)
        dta 0                ; 22 = FLOOR1_1 (wall, not one-way)
        dta 1                ; 23 = FLOOR5_1 (one-way platform)
        dta 0                ; 24 = MFLR8_1 (wall, not one-way)
        dta 0                ; 25 = door red (not one-way)
        dta 0                ; 26 = door blue (not one-way)
        dta 0                ; 27 = door yellow (not one-way)
        dta 0                ; 28 = switch OFF (not one-way)
        dta 0                ; 29 = switch ON (not one-way)

; ============================================
; HALF-HEIGHT TILE TABLE
; 1 = half-height (only top 8px have texture, bottom 8px transparent)
; ============================================
tile_halfh
        dta 0,0,0,0,0,0,0,0,0,0,0  ; 0-10
        dta 1,1,1,1                  ; 11-14 = half-height floor variants
        dta 0                        ; 15
        dta 0,0,0,0,0,0,0,0,0       ; 16-24
        dta 0,0,0                    ; 25-27 = doors
        dta 0,0                      ; 28-29 = switch OFF/ON

; ============================================
; CHECK IF TILE AT (gt_px, gt_py) IS SOLID
; Output: Z=0 if solid, Z=1 if passable
; ============================================
.proc check_solid
        jsr get_tile_at
        tax
        lda tile_solid,x
        rts                 ; A!=0 means solid
.endp

; ============================================
; CHECK IF TILE AT (gt_px, gt_py) IS SOLID OR PLATFORM
; For use during falling - platforms count as solid
; Output: Z=0 if solid/platform, Z=1 if passable
; ============================================
.proc check_solid_or_platform
        jsr get_tile_at
        tax
        lda tile_oneway,x
        bne ?plat           ; one-way tile = solid when falling
        lda tile_solid,x
        rts
?plat   lda #1              ; one-way = solid when falling
        rts
.endp

; sound_update is in sound.asm
