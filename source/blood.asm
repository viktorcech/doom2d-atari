;==============================================
; DOOM2D - Blood (g_gfx.pas g_GFX_Blood / thinkerBloodAndWater, g_monsters.pas
; TMonster.Damage, MakeBloodSimple)
; blood.asm
;
; BL_N droplets in a ring (the original: 2000). A hit throws min(dmg,200)*4
; - dmg/4 + rnd droplets (at most BL_PER) from the body's middle, half each
; way; each flies with gravity, sticks to a wall or a ceiling (and drips
; from there, 1 in 256 a tick), stays on a floor, dissolves in a liquid.
; Drawn as the original (g_game.pas: after the monsters, before the
; liquids): every droplet in view is a 1x1 fill BCB in this set's blood
; list (frame.asm banks, 25-byte slots), which a link BCB in the sprite list
; jumps to and which jumps back (VBXE FX 1.27 jump containers).
; Units: position a 16-bit pixel + a fraction byte (1/256 px, a multiple of
; 8: the old 1/32 px, bit-identical); speed 1/32 px a tick (36 Hz animation
; ticks, signed byte). The map is looked at only when the cell changes.
;==============================================

BL_N      = 128
BL_PER    = 64                  ; droplets a hit at most (a rocket: 375 PC)
BL_G      = 13                  ; gravity 0.8 PC px = 0.4 px = 13/32
BL_LIQ    = 140                 ; ticks in a liquid (liveTime 120+rnd(40))
BL_DRIP   = 8                   ; a drip's first speed (0.5 PC px)
BS_FLY    = 1                   ; bd_st: 0 free, flying, on a wall / ceiling,
BS_WALL   = 2                   ; on a floor
BS_CEIL   = 3
BS_FLOOR  = 4
BS_SPARK  = 5                   ; a spark (bd_t its life)
BS_SHELL  = 6                   ; a casing flying (bd_t: 32-tick units left)
BS_SHREST = 7                   ; a casing at rest
BL_GOBJ     = 16                  ; the casings' gravity: 1 PC px (g_Obj_Move)
BL_PAGE_A = $58                 ; the sets' blood lists: $058000, $059000
BL_PAGE_B = $59
BLD_W     = MEMW                ; slots from the bank's start
BL_SL     = 32                  ; particle i's slot: BLD_W + i*32 (bl_draw)
BL_DUM    = $FF00               ; an unshown byte of a screen's bank (bl_draw)
        ert BL_N*BL_SL<>$1000


bd_pxl  :BL_N dta 0             ; x, px: the low byte
bd_fx   :BL_N dta 0             ; its fraction: bits 7-3 (1/32 px); bits 1-0 the
                                ; pixel's high byte (the map is < 1024 px)
bd_pyl  :BL_N dta 0             ; y (the droplet's own pixel)
bd_pyh  :BL_N dta 0
bd_fy   :BL_N dta 0             ; its fraction; bits 1-0 the cell: BK_*
bd_vx   :BL_N dta 0             ; speed, signed
bd_vy   :BL_N dta 0
bd_st   :BL_N dta 0             ; BS_*
bd_c    :BL_N dta 0             ; colour (palette index)
bd_t    :BL_N dta 0             ; ticks left (a liquid, a spark, a casing)
bd_w    :BL_N dta 0             ; bits 1-0 width - 1 (a casing); bits 7-2 bl_draw's,
                                ; set A / B: V 7/6 its slot up to date, D 5/4 the
                                ; slot is the dummy, C 3/2 the slot has its colour
                                ; and width (a move clears V, a death all)
BK_LIQ  = 1                     ; the particle's cell (bd_fy): 0 empty, a liquid,
BK_PLAT = 2                     ; a platform, not looked at yet (a spark, a
BK_NEW  = 3                     ; casing: bl_mvy looks every tick, as before)
; speed -> its whole pixels a tick (v >> 5, signed): the pixel's add; the
; fraction's is (v << 3) & $FF
bl_vhi  :256 dta [[#>>5]|[[#>>7]*$F8]]&$FF
bl_sh5  dta 0,$20,$40,$60       ; a pixel's high byte (0..3) -> its cell's bits
bd_i    dta 0                   ; the ring's next slot
bl_top  dta 0                   ; slots ever used (the loops' end)
bl_cols ins '../data/blood_cols.bin'   ; tools/sky2vbxe.py: red, blue, green x 8
bl_kind dta 0, 0, 0, 8, 0, 16, 0       ; en_type -> colour row (caco blue, baron green)

; BL_SOLID - cell A = column, Y = row: C=1 a wall or off the map; else C=0,
; A = the cell's liquid (0 none), or $80 a platform (a step: solid only
; from above, thinkerBloodAndWater GridTagStep). Clobbers Y.
.proc bl_solid
        cmp #MAP_W
        bcs ?r
        cpy #MAP_H
        bcs ?r
        ora map_row_lo,y        ; the cell = the row's base | the column (rows
        sta ?m+1                ; 128-aligned, MAP_W <= 128) as a patched
        lda map_row_hi,y        ; absolute operand, no (zp),y (6502-loops-
        sta ?m+2                ; tables-smc)
        lda map_row_bank,y
        sta VBXE_BANK_SEL
?m      lda $FFFF               ; (patched)
        tay
        bmi ?bg                 ; a background tile: passable
        lda tile_solid,y        ; 1 a wall: C=1
        cmp #1
        bcs ?r
        lda tile_oneway,y       ; 0/1, C=0 kept: empty A = 0, a platform $80
        beq ?r
        lda #$80
?r      rts
?bg     lda tile_solid,y        ; its liquid 0..3
        clc
        rts
.endp
        ert MAP_STRIDE<>128 .or MAP_W>128

; (bl_hit, the enemies' entry, and the hits' ways: the end of this file)

; BL_PL - the player takes A damage (player_take_damage, TPlayer.Damage):
; red, from PLAYER_RECT's middle (centre zpx + PL_W/2, feet zpy - 13: 52/2
; PC px halved). Keeps X, Y.
.proc bl_pl
        stx bl_x
        sty bl_y
        sta bl_d
        lda #0
        sta bl_ck
        lda #13
        jsr bl_pm
.endp
        ert *<>bl_go            ; falls through

; BL_GO - bl_d damage at bl_cx / bl_cy (px): c = min(d,200)*4 - d/4 +
; rnd(min/2) droplets (at most BL_PER): all the hit's way (bl_hd +-48,
; MakeBloodVector) or half each way (bl_hd 0, MakeBloodSimple); X, Y back
; from bl_x / bl_y
.proc bl_go
        lda bl_d
        cmp #18                 ; d*4 - d/4 >= BL_PER from d = 18 on
        bcs ?max
        lsr                     ; rnd(d/2) ~ RANDOM AND d/2 (0 for d/2 = 0)
        sta ?h+1
        lda RANDOM
?h      and #0                  ; (patched: d/2)
        sta ?n+1
        lda bl_d                ; d*4 - d/4: d*4 + ~(d/4) + 1
        lsr
        lsr
        eor #$FF
        sec
        adc bl_d                ; d - d/4, carry out (256 + d - d/4): C=1
        clc
        adc bl_d                ; + 3d: d < 18, the sums stay < 256, C=0
        adc bl_d
        adc bl_d
?n      adc #0                  ; (patched: rnd)
        cmp #BL_PER
        bcc ?cnt
?max    lda #BL_PER
?cnt    tax                     ; no droplet (a 0 would loop 256 times)
        beq ?r
        ldy bl_hd               ; +-48: a hit with a way, every droplet that
        bne ?v                  ; way (MakeBloodVector), one pass
        lsr                     ; 0: half each way (MakeBloodSimple)
        beq ?r
        ldy #48                 ; +8 PC px, vx +3; then -8, -3
        ldx #-48&$FF
        dta $2C                 ; bit abs: skips ldx #0 (RAM/ROM: $00A2)
?v      ldx #0                  ; (no second pass)
        stx ?nx+1
        sta ?k+1
        sty bl_sv
        lda #0                  ; used: the next hit sets its own way
        sta bl_hd
        lda bl_cy               ; dy = rnd(0..15) - 8: the base y - 8
        sec
        sbc #8
        sta bl_cy
        bcs ?side
        dec bl_cy+1
?side   lda bl_cx               ; this side's base x: right the centre (dx
        ldy bl_cx+1             ; 0..7), left - 8 (dx -8..-1)
        bit bl_sv
        bpl ?rt
        sec
        sbc #8
        bcs ?rt
        dey
?rt     sta bl_bx
        sty bl_bx+1
?k      lda #0                  ; (patched: droplets a pass)
        sta bl_cnt
?one    jsr bl_new
        dec bl_cnt
        bne ?one
        lda bl_sv               ; the left pass done: the end
        bmi ?r
?nx     lda #0                  ; (patched: -48 the left half, 0 none)
        sta bl_sv
        bne ?side
?r
bl_xy   ldx bl_x                ; (bl_wall's end too)
        ldy bl_y
        rts
.endp
bl_x    dta 0                   ; the callers' X, Y
bl_y    dta 0
bl_d    dta 0                   ; the damage
bl_cx   dta 0,0                 ; the hit's centre, px (bl_go: bl_cy - 8)
bl_cy   dta 0,0
bl_bx   dta 0,0                 ; this side's base x
bl_sv   dta 0                   ; this side's speed (+-48: 3 PC px), its sign the side
bl_hd   dta 0                   ; the next hit's way: +-48 (bl_way), 0 both
bl_ck   dta 0                   ; colour row
bl_cnt  dta 0

; BL_NEW - one droplet into the ring (g_GFX_Blood's loop body): x = centre
; +- 4 px (the side) + rnd(-4..3), y = middle + rnd(-8..7), velX = side +
; tri, velY = -1 + tri - 4 PC px but not under -4, a random shade; not in
; a wall
.proc bl_new
        ldx bd_i
        lda RANDOM              ; x = the side's base + rnd(0..7)
        and #7
        clc
        adc bl_bx
        sta bd_pxl,x
        lda bl_bx+1
        adc #0
        sta bd_fx,x             ; (the fraction 0)
        tay
        cpy #4                  ; off the map: no droplet
        bcs ?r
        lda bd_pxl,x
        lsr
        lsr
        lsr
        ora bl_sh5,y
        sta ?col+1
        lda RANDOM              ; y = the base + rnd(0..15)
        and #15
        clc
        adc bl_cy
        sta bd_pyl,x
        lda bl_cy+1
        adc #0
        sta bd_pyh,x
        tay
        cpy #4
        bcs ?r
        lda bd_pyl,x
        lsr
        lsr
        lsr
        ora bl_sh5,y
        tay                     ; the cell: a wall -> no droplet (Pascal continue)
?col    lda #0                  ; (patched)
        jsr bl_solid
        bcs ?r
        jsr bl_bk               ; its cell (bl_mvy), the fraction 0
        sta bd_fy,x
        lda #0
        sta bd_w,x
        jsr bl_tri              ; velX = side + tri
        clc
        adc bl_sv
        sta bd_vx,x
        jsr bl_tri              ; velY = -1 + tri - 4 PC px (-16 - 64), not
        clc                     ; under -4 PC px (-64); tri in -47..47: no
        adc #-80&$FF            ; overflow, A in -127..-33
        cmp #-64&$FF
        bcs ?vy                 ; -64..-33 unsigned $C0..$DF: kept
        lda #-64&$FF
?vy     sta bd_vy,x
        lda RANDOM              ; crnd = 20 * Random(6) - 50: a shade
        and #7
        ora bl_ck
        tay
        lda bl_cols,y
        sta bd_c,x
        lda #BL_LIQ
        sta bd_t,x
        lda #BS_FLY
        sta bd_st,x
        jmp bl_adv
?r      rts
.endp

; (bl_nh, bl_bk: page 6, after bl_shell)

; BL_TRI - (Random - Random) * 3 PC px as 1/32 px: (r1&63 - r2&63) * 3/4
.proc bl_tri
        lda RANDOM
        and #63
        sta ?s+1
        lda RANDOM
        and #63
        eor #$FF                ; r1 - r2 = r1 + ~r2 + 1
        sec
?s      adc #0                  ; (patched: r1)
        sta ?t+1                ; t - t/4 (arithmetic)
        cmp #$80
        ror @
        cmp #$80
        ror @
        eor #$FF
        sec
?t      adc #0                  ; (patched: t)
        rts
.endp

; BL_TICK - every animation tick (update_triggers): blood (thinkerBloodAnd
; Water), sparks (thinkerSpark), casings (g_Player_UpdatePhysicalObjects).
; The ring is walked only while something moves (bl_mov: recounted by the
; walk) or on the casings' clock tick; blood stuck to a wall / ceiling drips
; without a walk: one random slot a tick, half the time - 1/128 * 1/2 =
; 1/256 per droplet and tick, as before. Blood in its own cell moves inline
; (no map look, no call); sparks, casings and a new cell go out of line.
.proc bl_tick
        inc bl_tk               ; the casings' clock: a unit every 32 ticks
        lda bl_tk
        and #31
        bne ?c                  ; a casing at rest works on the unit's tick only
        lda #1
        dta $2C                 ; bit abs: skips the lda
?c      lda #0
        sta ?wk+BS_SHREST
        lda RANDOM              ; the drip: one slot, a stuck one half the time
        and #BL_N-1
        cmp bl_top
        bcs ?nd
        tax
        lda bd_st,x
        cmp #BS_WALL
        beq ?dr
        cmp #BS_CEIL
        bne ?nd
?dr     lda RANDOM
        bmi ?nd
        lda #0
        sta bd_vx,x
        lda #BL_DRIP
        sta bd_vy,x
        lda #BS_FLY
        sta bd_st,x
        jsr bl_ext
?nd     lda bl_mov              ; nothing moves and no clock tick: no walk
        ora ?wk+BS_SHREST
        beq ?r
        ldy mv_lo               ; the walk: the movers' range [mv_lo, mv_hi],
        ldx mv_hi               ; on the clock tick every slot (bl_mov > 0:
        inx                     ; the range is not empty)
        lda ?wk+BS_SHREST
        beq ?rg
        ldy #0
        ldx bl_top
?rg     cpy bq_lo               ; the walk's range [Y, X): both sets' slots
        bcs ?q1                 ; in it may be out of date (bl_draw)
        sty bq_lo
?q1     cpy bq_lo+1
        bcs ?q2
        sty bq_lo+1
?q2     cpx bq_hi
        bcc ?q3
        stx bq_hi
?q3     cpx bq_hi+1
        bcc ?q4
        stx bq_hi+1
?q4     dey
        sty ?end+1              ; stop below the range's bottom
        lda #0                  ; the walk finds the movers' range again;
        sta bl_mov              ; bl_mov (a yes / no) is set at its end
        sta mv_hi
        lda #$FF
        sta mv_lo
        bne ?nx                 ; (always)
?nf     cpy #BS_SPARK           ; not blood (out of the common path)
        bne ?cs
        jmp ?spark
?cs     lda bl_tk               ; a casing: SHELL_TIMEOUT 60 s
        and #31
        bne ?sh
        dec bd_t,x
        beq ?die
?sh     cpy #BS_SHELL
        bne ?nx                 ; at rest
        jmp ?shell
?die    lda #0
        sta bd_w,x              ; (bl_draw: its slots again)
        sta bd_st,x
        beq ?nx                 ; (always)
?we     lda mv_lo               ; the walk's end: a mover left (mv_lo < $FF)
        bmi ?r                  ; keeps it going
        inc bl_mov
?r      rts
?nx     dex
?end    cpx #0                  ; (patched: the bottom - 1)
        beq ?we
?lp     ldy bd_st,x             ; idle (free, stuck, on a floor, a casing at
        lda ?wk,y               ; rest off its tick): one table look
        beq ?nx
        lda bd_w,x              ; it works (moves): both sets' slots out of
        and #$3F                ; date (bl_draw), once here, not per axis
        sta bd_w,x
        cpy #BS_FLY             ; blood, the common mover, falls through
        bne ?nf
        lda #BL_G               ; velY += gravity, at most 127
        clc
        adc bd_vy,x
        bvc ?g1
        lda #127
?g1     sta bd_vy,x
        ldy bd_vx,x             ; x in the same cell, inline (as bl_mvx)
        tya
        asl
        asl
        asl
        clc
        adc bd_fx,x
        sta bd_fx,x             ; stored at once (6502-idioms: store once); a
        lda bd_pxl,x            ; new cell, the rare case, takes it back
        sta zt
        adc bl_vhi,y
        sta bd_pxl,x
        eor zt
        and #$F8
        bne ?xc
?fy     ldy bd_vy,x             ; y in the same cell, no platform (as bl_mvy)
        tya
        asl
        asl
        asl
        clc
        adc bd_fy,x
        sta bd_fy,x
        lda bd_pyl,x
        sta zt
        adc bl_vhi,y
        sta bd_pyl,x
        eor zt
        and #$F8
        bne ?yc
        lda bd_fy,x             ; the cell: empty (most) falls through
        and #3
        bne ?yk
?mv     lda mv_lo               ; it moves on: the walk goes down, the first
        bpl ?m2                 ; mover ($FF: none yet) is the range's top,
        stx mv_hi               ; the last its bottom (no count: bl_mov is a
?m2     stx mv_lo               ; yes / no, set at the walk's end)
        jmp ?nx
?lq     dec bd_t,x              ; in a liquid: it dissolves
        bne ?mv
?sd     jmp ?die
?ss     sta bd_st,x
        jmp ?nx
?xc     lda zt                  ; a new cell: the step back (Y = the speed:
        sta bd_pxl,x            ; the fraction - (v << 3)), then the map look
        tya
        asl
        asl
        asl
        eor #$FF
        sec
        adc bd_fx,x
        sta bd_fx,x
        jsr bl_mvx
        bcc ?fy
        lda #BS_WALL            ; stickToWall (freeze)
        bne ?ss                 ; (always)
?yk     cmp #BK_LIQ             ; in a liquid: moved; a platform, BK_NEW: back
        beq ?lq
?yc     lda zt
        sta bd_pyl,x
        tya
        asl
        asl
        asl
        eor #$FF
        sec
        adc bd_fy,x
        sta bd_fy,x
        jsr bl_mvy
        bcs ?hf
?mz     beq ?mv                 ; Z: no liquid
        bne ?lq                 ; (always)
?hf     lda bd_vy,x             ; up: stickToCeiling, down: hitAFloor
        bmi ?ceil
        lda #BS_FLOOR
        dta $2C                 ; bit abs: skips the lda
?ceil   lda #BS_CEIL
        bne ?ss                 ; (always)
?spark  dec bd_t,x              ; liveTime 30 + rnd(60)
        beq ?sd
        lda #BL_G/2
        clc
        adc bd_vy,x
        bvc ?g2
        lda #127
?g2     sta bd_vy,x
        jsr bl_mvx
        bcc ?sy
        lda #0                  ; the wall: it falls down vertically
        sta bd_vx,x
?sy     jsr bl_mvy
        bcs ?sd                 ; a floor / a ceiling
        bne ?sd                 ; a liquid
        beq ?mz                 ; (always; ?mv through its branch: out of reach)
?shell  lda #BL_GOBJ            ; g_Obj_Move: Vel.Y += 1
        clc
        adc bd_vy,x
        bvc ?g3
        lda #127
?g3     sta bd_vy,x
        jsr bl_mvx
        bcc ?hy
        lda bd_vx,x             ; MOVE_HITWALL: Vel.X := -(Vel.X div 2)
        cmp #$80                ; div 2, signed: the sign into C (inlined: < a call)
        ror @
        eor #$FF
        clc
        adc #1
        sta bd_vx,x
?hy     jsr bl_mvy
        bcc ?hm
        lda bd_vy,x             ; HITLAND / HITCEIL: Vel.Y := -(Vel.Y div 2),
        cmp #$80                ; Vel.X := Vel.X div 2 (signed: the sign into C)
        ror @
        eor #$FF
        clc
        adc #1
        sta bd_vy,x
        lda bd_vx,x
        cmp #$80                ; div 2, signed: the sign into C (inlined: < a call)
        ror @
        sta bd_vx,x
        lda bd_vy,x             ; both under a PC px a tick: at rest
        clc
        adc #8
        cmp #16
        bcs ?hm
        lda bd_vx,x
        clc
        adc #8
        cmp #16
        bcs ?hm
        lda #BS_SHREST
        sta bd_st,x
        jmp ?nx
?hm     jmp ?mv
?wk     dta 0, 1, 0, 0, 0, 1, 1, 0      ; BS_*: works this tick (7 patched)
        ert BS_SHREST<>7 .or BS_FLOOR<>4 .or BS_WALL<>2 .or BS_CEIL<>3
.endp
bl_tk   dta 0
bl_mov  dta 0                   ; the particles that moved last walk (+ new ones)
mv_lo   dta $FF                 ; their index range ($FF / 0: none)
mv_hi   dta 0
bq_lo   dta $FF,$FF             ; per set: the slots [lo, hi) walked since its
bq_hi   dta 0,0                 ; last build ($FF / 0: none)

; BL_EXT - particle X moves (new, a drip): bl_mov + 1, X into the movers'
; range. Keeps X.
.proc bl_ext
        inc bl_mov
        cpx mv_lo
        bcs ?h
        stx mv_lo
?h      cpx mv_hi
        bcc ?r
        stx mv_hi
?r      rts
.endp



; BL_MVX - particle X: x += velX unless the new cell is a wall (C=1, x kept)
.proc bl_mvx
        ldy bd_vx,x
        tya                     ; the fraction's add: (v << 3) & $FF
        asl
        asl
        asl
        clc
        adc bd_fx,x
        sta ?f+1
        lda bd_pxl,x            ; the pixel's: v >> 5 + the carry
        adc bl_vhi,y
        sta ?l+1
        eor bd_pxl,x            ; the same cell: free (the particle is in it),
        and #$F8                ; no map look (C kept: the pixel's carry)
        bne ?cell
?l      lda #0                  ; (patched)
        sta bd_pxl,x
?f      lda #0                  ; (patched)
        sta bd_fx,x
        clc
        rts
?cell   lda bd_fx,x             ; the new high byte, its cell
        and #3
        jsr bl_nh
        cpy #4                  ; off the map: a wall (C=1)
        bcs ?r
        sta ?nh+1
        lda ?l+1
        lsr
        lsr
        lsr
        ora bl_sh5,y
        sta ?c+1
        ldy bd_pyh,x            ; its row
        lda bd_pyl,x
        lsr
        lsr
        lsr
        ora bl_sh5,y
        tay
?c      lda #0                  ; (patched: the new column)
        jsr bl_solid
        bcs ?r
        jsr bl_bk               ; the new cell into bd_fy (C = 0 kept)
        sta ?k+1
        lda bd_fy,x
        and #$F8
?k      ora #0                  ; (patched)
        sta bd_fy,x
        lda ?f+1                ; the high byte into the fraction's bits (on
        and #$F8                ; the map: 0..3)
?nh     ora #0                  ; (patched)
        sta ?f+1
        bcc ?l                  ; (always)
?r      rts
.endp

; BL_MVY - particle X: y += velY unless the new cell is a wall, or a
; platform while falling (C=1, y kept); else C=0, Z: no liquid in the cell
.proc bl_mvy
        ldy bd_vy,x
        tya
        asl
        asl
        asl
        clc
        adc bd_fy,x             ; (bits 2-0, the cell, ride along)
        sta ?f+1
        lda bd_pyl,x
        adc bl_vhi,y
        sta ?l+1
        eor bd_pyl,x
        and #$F8
        bne ?cell               ; (C kept: the pixel's carry)
        lda bd_fy,x             ; the same cell: what the last look found
        and #BK_PLAT            ; (bit 1: a platform or BK_NEW)
        bne ?kind
?go
?l      lda #0                  ; (patched)
        sta bd_pyl,x
?f      lda #0                  ; (patched)
        sta bd_fy,x
        and #BK_LIQ             ; Z: no liquid (a platform: bit 0 = 0)
        clc
        rts
?kind   lda bd_fy,x
        lsr
        bcs ?chk                ; BK_NEW: look
        tya                     ; a platform: rising through it, falling it
        bmi ?go                 ; lands
        sec
        rts
?chk    lda bd_pyh,x            ; (the same cell: the same high byte)
        tay
        bcs ?h                  ; (always: the lsr)
?cell   lda bd_pyh,x
        jsr bl_nh
?h      cpy #4                  ; off the map: a wall (C=1)
        bcs ?r
        sta ?nh+1
        lda ?l+1
        lsr
        lsr
        lsr
        ora bl_sh5,y
        sta ?rw+1
        lda bd_fx,x             ; its column
        and #3
        tay
        lda bd_pxl,x
        lsr
        lsr
        lsr
        ora bl_sh5,y
?rw     ldy #0                  ; (patched: the new row)
        jsr bl_solid
        bcs ?r
        jsr bl_bk
        sta ?k+1
        cmp #BK_PLAT
        bne ?in
        lda bd_vy,x             ; a platform: falling it lands (C=1: the cmp),
        bpl ?r                  ; rising through it
?in
?nh     lda #0                  ; (patched)
        sta bd_pyh,x
        lda ?f+1                ; the cell into the fraction's bits
        and #$F8
?k      ora #0                  ; (patched)
        sta ?f+1
        jmp ?go
?r      rts
.endp
        ert BK_LIQ<>1 .or BK_PLAT<>2

; BL_ADV - the new particle at X: bd_i = the next slot, bl_top.
.proc bl_adv
        jsr bl_ext              ; it moves (bl_tick walks the ring)
        inx
        cpx bl_top
        bcc ?t
        stx bl_top
?t      txa
        and #BL_N-1
        sta bd_i
        rts
.endp
        ert BL_N<>128


; BL_WALL - a bullet stopped at wall column A (hitscan_fire): sparks from
; the wall's near edge at height bl_cy (px: the gun's, zpy - 14, or a
; shotgun pellet's; hitscan_fire sets it), back to the shooter
; (g_weapons.pas: g_GFX_Spark(wallHitX, wallHitY, 2+Random(2), 180+a)).
; Keeps X, Y.
.proc bl_wall
        stx bl_x
        sty bl_y
        ldx zpdir               ; shot left: the wall's right edge + 1 =
        beq ?m                  ; (col + 1) * 8
        clc
        adc #1
?m      ldy #0                  ; * 8 (a column < 128: the first asl is clean)
        sty bl_cx+1
        asl
        asl
        rol bl_cx+1
        asl
        rol bl_cx+1
        sta bl_cx
        txa                     ; left: sparks fly right (bl_sv >= 0)
        bne ?y
        lda bl_cx               ; shot right: the wall's left edge - 1,
        bne ?d                  ; sparks fly left
        dec bl_cx+1
?d      dec bl_cx
        lda #$80
?y      sta bl_sv               ; (bl_cy: the caller's height, px)
        lda RANDOM              ; 2 + Random(2)
        and #1
        ora #2
        sta bl_cnt
?one    ldx bd_i
        jsr bl_at
        lda RANDOM              ; velX = cos * Random: 0..1 PC px, back
        and #15
        bit bl_sv
        bpl ?vp
        eor #$FF
        clc
        adc #1
?vp     sta bd_vx,x
        lda RANDOM              ; velY = -Random: 0..1 PC px up
        and #15
        eor #$FF
        clc
        adc #1
        sta bd_vy,x
        lda RANDOM              ; 255, 100 + Random(155), 64: a shade
        and #7
        tay
        lda bl_cols+24,y
        sta bd_c,x
        lda RANDOM              ; liveTime 30 + Random(60)
        and #63
        clc
        adc #30
        sta bd_t,x
        lda #BS_SPARK
        sta bd_st,x
        jsr bl_adv
        dec bl_cnt
        bne ?one
        jmp bl_go.bl_xy         ; X, Y back
.endp

; BL_PM - bl_cx / bl_cy = the player's middle: centre zpx + PL_W/2, A px
; above the feet. Keeps X, Y.
.proc bl_pm
        sta ?d+1
        lda zpx
        clc
        adc #PL_W/2
        sta bl_cx
        lda zpx_hi
        adc #0
        sta bl_cx+1
        lda zpy
        sec
?d      sbc #0                  ; (patched)
        sta bl_cy
        lda zpy_hi
        sbc #0
        sta bl_cy+1
        rts
.endp

; particle -> its slot's +7 in the slot's page (8 slots a page): the upper
; half of tile_oneway's page, which no tile id reads (game.asm)
bl_s7_save = *
        org tile_oneway+128
bl_s7   :BL_N dta [[#&7]*BL_SL]+7
        ert *>tile_oneway+256
        org bl_s7_save
bc_cam  dta $FF,$FF,$FF,$FF, $FF,$FF,$FF,$FF ; per set: the camera it was built with

; The cold blood routines in the cassette buffer's rest ($0400-$047F: the XL
; OS uses it only for a cassette and the boot sector read, long done)
blood_save = *
        org $0400
; BL_TEMPLATE - this set's blood slots: a 1x1 constant fill (AND 0, XOR =
; the colour) at the dummy, EXTENDED + NEXT, a relative jump to the slot
; below (particle i - 1: the list runs down, the drawing order); slot 0
; jumps back (bl_draw). frame.asm lists_init
.proc bl_template
        lda bl_bank
        sta VBXE_BANK_SEL
        lda #<BLD_W
        sta pl_p
        lda #>BLD_W
        sta pl_p+1
        ldx #BL_N
?s      ldy #SLOT-1
?t      lda ?tm,y
        sta (pl_p),y
        dey
        bpl ?t
        lda pl_p
        clc
        adc #BL_SL
        sta pl_p
        bcc ?n
        inc pl_p+1
?n      dex
        bne ?s
        rts
?tm     dta <HUD_ZERO,>HUD_ZERO,^HUD_ZERO, 0,0,1, <BL_DUM,>BL_DUM,0, <SCR_W,>SCR_W,1
        dta 0,0,0, 0, 0,0,0,0, $80+$08          ; 1 x 1, AND 0: fill, MODE 0
        dta $01,<[$10000-BL_SL-24],>[$10000-BL_SL-24],$00   ; relative, from its last byte
.endp

; BL_AT - particle X at bl_cx / bl_cy (px), its cell not looked at, bd_w 0
; (a spark, a casing). Keeps X, Y.
.proc bl_at
        lda bl_cx
        sta bd_pxl,x
        lda bl_cx+1             ; (the fraction 0)
        sta bd_fx,x
        lda bl_cy
        sta bd_pyl,x
        lda bl_cy+1
        sta bd_pyh,x
        lda #BK_NEW
        sta bd_fy,x
        lda #0
        sta bd_w,x
        rts
.endp

        ert *>$0480
; page 6's rest, after the sound's handlers (the boot's early_init ran there)
        org snd_lo_end
; BL_SHELL - the shot's casing (g_player.pas: g_Player_CreateShell at the
; player's middle, push (velX + rnd(4) - rnd(4), velY - 2 - rnd(4)) PC px):
; EBULLET (pistol, chaingun) 4x2 -> 2x1 px, ESHELL (shotgun) 7x3 -> 3x1
.proc bl_shell
        lda #16                 ; x = the centre, y = feet - 16 (Obj.Y +
        jsr bl_pm               ; PLAYER_RECT_CX = 32 PC px, halved)
        ldx bd_i
        jsr bl_at
        lda RANDOM              ; (rnd(4) - rnd(4)) * 16 (1 PC px = 16)
        and #3
        sta ?s+1
        lda RANDOM
        and #3
        sec
?s      sbc #0                  ; (patched)
        asl
        asl
        asl
        asl
        sta bd_vx,x
        lda RANDOM              ; -(2 + rnd(4)) * 16
        and #3
        asl
        asl
        asl
        asl
        eor #$FF
        sec
        sbc #31                 ; ~v - 31 = -v - 32
        sta bd_vy,x
        ldy #0                  ; the casing: pistol / chaingun a bullet's
        lda player_update.fire_wcur
        cmp #WP_SHOTGUN
        bne ?b
        iny
?b      lda bl_cols+32,y
        sta bd_c,x
        lda ?w,y
        sta bd_w,x
        lda #68                 ; 60 s in 32-tick units
        sta bd_t,x
        lda #BS_SHELL
        sta bd_st,x
        jmp bl_adv
?w      dta 1, 2                ; width - 1
.endp

; BL_NH - a pixel's new high byte: A = the old one, Y = the speed (its
; sign extends), C = the low byte's carry. Returns it in A and Y. Keeps X.
.proc bl_nh
        sta ?o+1
        tya
        bmi ?ng
        lda #0
        dta $2C                 ; bit abs: skips the lda (RAM/ROM: $FFA9)
?ng     lda #$FF
?o      adc #0                  ; (patched)
        tay
        rts
.endp

; BL_BK - bl_solid's A (0, a liquid 1..3, $80 a platform) -> BK_*. Keeps
; X, Y, C.
.proc bl_bk
        beq ?r
        bmi ?p
        lda #BK_LIQ
        rts
?p      lda #BK_PLAT
?r      rts
.endp
        ert *>dp_c0
        org blood_save

; BL_DRAW - the droplets in view into this set's blood list, a link BCB in
; the sprite list into it and back (main.asm: after the sprites, before the
; liquids). The slots' fields: +6, +7 the pixel, +12 the width, +16 the
; colour. Only the slots walked since this set's last build (bq_*) and the
; movers' are looked at; every used one when the camera moved.
.proc bl_draw
        lda bl_top              ; no blood yet: nothing (the common case)
        beq ?q
        lda spl_ptr             ; room for the link and its jump's slot
        cmp #<[SPRL_W+[SPRL_MAX-1]*21]
        lda spl_ptr+1
        sbc #>[SPRL_W+[SPRL_MAX-1]*21]
        bcc ?ok
?q      rts
?ok     lda bl_bank
        sta VBXE_BANK_SEL
        lda #<BLD_W             ; pl_p: the slot's page (8 slots a page)
        sta pl_p
        ldx lst_i               ; this set's bits in bd_w: V, D and C
        lda ?td,x
        sta ?dm+1
        sta ?e1+1
        ora ?tv,x
        sta ?o2+1
        ora ?tc,x
        sta ?o1+1
        lda ?tv,x
        sta ?vm+1
        lda ?tc,x
        sta ?cm+1
        lda mv_lo               ; the range: the set's own + the movers'
        cmp bq_lo,x
        bcc ?l1
        lda bq_lo,x
?l1     sta ?lb+1
        ldy mv_hi
        iny
        tya
        cmp bq_hi,x
        bcs ?h1
        lda bq_hi,x
?h1     sta ?hx+1
        lda #$FF
        sta bq_lo,x
        lda #0
        sta bq_hi,x
        txa                     ; the camera this set was last built with:
        asl                     ; moved, every slot is looked at again
        asl
        tay
        ldx #3
?cc     lda cam_x,x
        cmp bc_cam,y
        beq ?ce
        sta bc_cam,y
        lda #0                  ; (V ignored, every used slot)
        sta ?vm+1
        sta ?lb+1
        lda bl_top
        sta ?hx+1
?ce     iny
        dex
        bpl ?cc
        lda ?lb+1               ; nothing to look at: the link only
        cmp ?hx+1
        bcs ?je
        dec ?lb+1               ; (the loop's end: the bottom - 1)
?hx     ldx #0                  ; (patched: the range's top + 1; down: the
        bne ?nx                 ; drawing order) (always: > the bottom)
?je     jmp ?end
?dum    lda bd_w,x              ; free or out of view: the dummy, once
?dm     and #0                  ; (patched: D)
        bne ?sv
        ldy bl_s7,x
        lda #>BL_DUM
        sta (pl_p),y            ; +7
        dey
        lda #<BL_DUM
        sta (pl_p),y            ; +6
?sv     lda bd_w,x
?o2     ora #0                  ; (patched: V + D)
?st     sta bd_w,x
?nx     dex
?lb     cpx #0                  ; (patched: the range's bottom - 1)
        beq ?je                 ; (the end, once: out of reach)
?lp     lda bd_w,x
?vm     and #0                  ; (patched: V; 0 the camera moved)
        bne ?nx                 ; up to date: nothing to write
        txa                     ; the slot: BLD_W + X*32
        lsr
        lsr
        lsr
        ora #>BLD_W
        sta pl_p+1
        lda bd_st,x
        beq ?dum                ; free
        lda bd_pyl,x            ; screen y = the pixel - cam_y
        sec
        sbc cam_y
        tay                     ; (the screen y stays in Y)
        lda bd_pyh,x
        sbc cam_y_hi
        bne ?dum                ; above / far below
        lda bd_pxl,x            ; screen x; C = 1: a 0 without borrow (cam_y_hi
        sbc cam_x               ; <= $7F, camera.asm clamps it)
        sta ?sx+1
        lda bd_fx,x             ; (its high byte: bits 1-0; C kept)
        and #3
        sbc cam_x_hi
        beq ?x0                 ; 0..255
        cmp #1
        bne ?dum                ; left of the window, or right of 511
        lda ?sx+1
        cmp #<[SCR_W-256]
        bcs ?dum                ; 320 and right
        lda #1
?x0     sta ?sxh+1
        cpy #GAME_H
        bcs ?dum
        lda y_addr_lo,y         ; dst = back buffer + y*320 + x (C=0: the bcs)
?sx     adc #0                  ; (patched: x lo)
        pha                     ; (parked: Y is the row until the high byte)
        lda y_addr_hi,y
?sxh    adc #0                  ; (patched: x hi)
        ldy bl_s7,x             ; the slot's +7 in its page
        sta (pl_p),y            ; +7
        dey
        pla
        sta (pl_p),y            ; +6
        ldy bd_w,x
        tya
?cm     and #0                  ; (patched: C)
        beq ?col
        tya
?cd
?o1     ora #0                  ; (patched: V + D + C)
?e1     eor #0                  ; (patched: D)
        bne ?st                 ; (always: V)
        ; the slot gets its colour and width, once a particle and set
?col    lda bl_s7,x             ; the slot's +12
        clc
        adc #5
        tay
        lda bd_w,x
        and #3
        sta (pl_p),y            ; +12 width-1 (a casing 1 or 2)
        iny
        iny
        iny
        iny
        lda bd_c,x
        sta (pl_p),y            ; +16 the colour
        lda bd_w,x
        jmp ?cd
?end    lda #>BLD_W             ; slot 0 jumps back: to the sprite slot after
        sta pl_p+1              ; the link and the link's container slot
        lda spl_ptr
        clc
        adc #42
        tax
        lda spl_ptr+1
        adc #0                  ; (no carry out: C=0, the -1 below)
        sbc #[>MEMW]-1          ; VRAM: the main bank + (MEMW offset)
        ora ls_mid
        ldy #23
        sta (pl_p),y
        txa
        dey
        sta (pl_p),y
        lda #0
        dey
        sta (pl_p),y            ; +21 absolute
        lda ls_hi
        ldy #24
        sta (pl_p),y
        lda ls_bank             ; the link BCB: a 1x1 stencil of a 0 (draws
        sta VBXE_BANK_SEL       ; nothing), EXTENDED, jumps to the top slot;
        ldy #0                  ; the other fields: the slot's template
        lda #<HUD_ZERO
        sta (spl_ptr),y         ; +0..+2
        iny
        lda #>HUD_ZERO
        sta (spl_ptr),y
        iny
        lda #^HUD_ZERO
        sta (spl_ptr),y
        lda #0
        ldy #12
        sta (spl_ptr),y         ; +12 width-1
        ldy #14
        sta (spl_ptr),y         ; +14 height-1
        ldy #21
        sta (spl_ptr),y         ; (the next slot's +0..+3: its writers set them)
        lda #$80+$08+BLT_TRANS
        dey
        sta (spl_ptr),y         ; +20
        ldx bl_top              ; to the top slot: (bl_top - 1) * 32
        dex
        txa
        asl
        asl
        asl
        asl
        asl
        ldy #22
        sta (spl_ptr),y
        txa
        lsr
        lsr
        lsr
        ora bl_mid
        iny
        sta (spl_ptr),y
        lda #^[BL_PAGE_A<<12]
        iny
        sta (spl_ptr),y
        lda spl_ptr             ; past the link and its jump's slot (spl_lk:
        clc                     ; spl_close ends the list here if nothing follows)
        adc #42
        sta spl_ptr
        sta spl_lk
        lda spl_ptr+1
        adc #0
        sta spl_ptr+1
        sta spl_lk+1
        rts
?tv     dta $80,$40             ; the sets' V, D and C bits (bd_w)
?td     dta $20,$10
?tc     dta $08,$04
.endp
        ert [BLD_W&$FF]<>0 .or [>[BLD_W-MEMW]]<>0
        ert ^[BL_PAGE_A<<12]<>^[BL_PAGE_B<<12]

; PL_SPLASH - the player entered a liquid (pl_liquid): D2DF g_Obj_Splash,
; MaxVel = max(|vx|, |vy|) of that move (pl_damp runs after): 5..9 BULK1,
; 10+ BULK2, below 5 silent; at half scale x 0.72: PL_LIFTV, PL_JUMPV.
.proc pl_splash
        stx ?s+1                ; the sound so far: 0 none (pl_liquid: X = 0;
                                ; 2026-11-02 6502-idioms.md "stx when X is known 0")
        ldx #1                  ; vy, then vx (zpvy = zpvx+1, zpvy_f = zpvx_f+1)
?lp     lda zpvx,x              ; |v| (8.8): lo in A, hi in Y
        bpl ?pos
        lda #0                  ; negative: 0 - v
        sec
        sbc zpvx_f,x
        pha                     ; lo (2026-11-02 6502-idioms.md "no RAM cell for a
        lda #0                  ; value that only waits": the stack)
        sbc zpvx,x
        tay
        pla
        bcc ?c                  ; (always: 0 - a negative hi borrows; pla keeps C)
?pos    tay
        lda zpvx_f,x
?c      pha                     ; lo for the second compare
        cmp #<PL_LIFTV
        tya
        sbc #>PL_LIFTV
        pla                     ; lo again (C kept)
        bcc ?nx                 ; |v| < PL_LIFTV: silent
        cmp #<PL_JUMPV
        tya
        sbc #>PL_JUMPV
        lda #SFX_BULK1
        adc #0                  ; C = (|v| >= PL_JUMPV): SFX_BULK2
?s      cmp #0                  ; (patched: the sound so far)
        bcc ?nx
        sta ?s+1
?nx     dex
        bpl ?lp
        ldx ?s+1
        beq ?r
        jmp snd_play            ; (2026-11-02 6502-idioms.md "jsr X / rts -> jmp X")
?r      rts
        ert SFX_BULK2<>SFX_BULK1+1
        ert zpvy<>zpvx+1
        ert zpvy_f<>zpvx_f+1
.endp

; ============================================
; The hits' entries (TMonster.Damage's blood, MakeBloodVector's way), in the
; RAM the ANTIC sky's third display list had; enemies_ai.asm's code follows
; at bl_lo_end (its ert guards the end, tr_act)
; ============================================
bl_lo_save = *
        org tr_type+TR_MAX

; BL_HIT - enemy X takes A damage (en_hurt, TMonster.Damage): its blood
; colour, from the body's middle (feet - h/2, centre = en_x + 8). Keeps X, Y.
.proc bl_hit
        stx bl_x
        sty bl_y
        sta bl_d
        ldy en_type,x
        lda bl_kind,y
        sta bl_ck
        lda mon_h,y
        lsr @
        sta ?mh+1
        lda en_x,x
        clc
        adc #8
        sta bl_cx
        lda enxhi,x
        adc #0
        sta bl_cx+1
        lda en_y,x
        sec
?mh     sbc #0                  ; (patched: h/2)
        sta bl_cy
        lda en_y_hi,x
        sbc #0
        sta bl_cy+1
        jmp bl_go
.endp

; The next hit's way (bl_hd) - each one is called right before the hit's
; en_hurt / player_take_damage (a kill draws no blood: bl_hd is not set).
; BL_MWAY - monster X hit by monster en_by-1: away from the hitter. Clobbers Y.
.proc bl_mway
        ldy en_by
        lda en_x,x              ; N = the victim is left of the hitter
        cmp en_x-1,y
        lda enxhi,x
        sbc enxhi-1,y
        jmp bl_way
.endp

; BL_PFROM - the player hit by monster X: away from it. Keeps X, Y.
.proc bl_pfrom
        lda zpx                 ; N = the player is left of it
        cmp en_x,x
        lda zpx_hi
        sbc enxhi,x
        jmp bl_way
.endp

; BL_PSHOT - the player's hit on monster (hs_damage_enemy): a gun's blood
; the way he faces; the fist and the saw (D2DF punch / saw: Vel 0) both
; ways. Keeps X, Y.
.proc bl_pshot
        lda zpwcur
        beq ?r                  ; WP_FIST
        cmp #WP_SAW
        bne ?g
?r      rts
?g      lda zpdir               ; 1 left: bit 0 -> C -> bit 7 (N)
        ror @
        ror @
        ert WP_FIST<>0
.endp
        ert *<>bl_way           ; falls into bl_way

; BL_WAY - the next hit's blood flies all one way (MakeBloodVector): N of
; the caller's value = to the left. Keeps X, Y.
.proc bl_way
        bmi ?l
        lda #48
        bne ?s                  ; (always)
?l      lda #-48&$FF
?s      sta bl_hd
        rts
.endp

; BL_RESET - no blood from the last level (trig_load): the ring empty, no
; movers. Ends A = 0.
.proc bl_reset
        lda #0
        sta bl_top
        sta bl_mov
        sta mv_hi
        ldx #BL_N-1
?bl     sta bd_st,x
        sta bd_w,x              ; (bl_draw: the slots rewritten)
        dex
        bpl ?bl
        stx mv_lo               ; X = $FF: no movers
        rts
.endp
bl_lo_end = *
        org bl_lo_save
