;==============================================
; DOOM2D - Barrel logic
; barrel.asm
;
; Barrel explosion, chain reactions, damage,
; projectile collision, map solid tile management.
; Uses decoration arrays from decorations.asm.
;
; Modelled on DOOM's MT_BARREL / A_Explode / P_RadiusAttack:
;   - box metric: dist = max(|dx|,|dy|)
;   - linear falloff: damage = BARREL_DMG - dist
;   - line of sight required (no damage through walls)
;   - thrust away from the blast, horizontal AND vertical
;   - the chain is just barrels being damaged by the blast
;
; Invariant (relied on by every barrel scan below):
;   dc_hp[i] != 0  <=>  slot i is a LIVE, not-yet-ignited barrel
; (barrel_ignite clears hp).
;==============================================

; --- Shared explosion parameters (barrel + rocket splash) ---
spl_x       dta 0               ; blast centre, 16-bit world coords
spl_xhi     dta 0               ; (same anchor as entities: left edge / feet)
spl_y       dta 0
spl_yhi     dta 0
spl_radius  dta 0
spl_max     dta 0               ; damage at point blank
spl_scale   dta 0               ; damage lost per pixel of distance
spl_kbx     dta 0               ; horizontal knockback speed
spl_kby     dta 0               ; vertical knockback speed
spl_los     dta 0               ; 1 = require line of sight to the player

; --- blast_los endpoints (tile coords) ---
bl_c0       dta 0               ; blast tile
bl_r0       dta 0
bl_c1       dta 0               ; target tile
bl_r1       dta 0

; --- world_to_tile in/out ---
wt_x        dta 0
wt_xhi      dta 0
wt_y        dta 0
wt_yhi      dta 0
wt_col      dta 0
wt_row      dta 0

; (abs16 / world_to_tile moved to game.asm 2026-08-14 - they are general
;  geometry helpers, used by pickups and melee too, not barrel-specific)


; ============================================
; LOS_BLOCKS - A = tile index. C=1 if it stops an explosion.
; Tile 15 never blocks: it is a barrel's own invisible solid, and in DOOM a
; barrel is a thing, not a wall - a tight row of them still chains.
; ============================================
.proc los_blocks
        bmi ?open               ; bit7 = BG tile, passable
        cmp #15
        beq ?open
        tay
        lda tile_solid,y
        cmp #1                  ; C = (tile_solid != 0)
        rts
?open   clc
        rts
.endp

; ============================================
; BLAST_LOS - cheap L-shaped line of sight for explosions: walk the blast
; row between the two columns, then the target column between the two rows.
; Endpoints are excluded (the blast and the target stand in open tiles).
; In:  bl_c0/bl_r0 = blast tile, bl_c1/bl_r1 = target tile
; Out: C=1 clear, C=0 blocked. Clobbers A, Y, ztptr. Preserves X.
; ============================================
.proc blast_los
        ; --- horizontal leg, along the blast row ---
        ldy bl_r0
        lda map_row_bank,y
        sta VBXE_BANK_SEL
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        lda bl_c0
        cmp bl_c1
        beq ?vert
        bcc ?hfwd
        ldy bl_c1               ; blast right of target (A = bl_c0)
        bcs ?hgo                ; C=1: bcc not taken
?hfwd   tay                     ; blast left of target (A = bl_c0)
        lda bl_c1
?hgo    sta bl_end
        iny                     ; strictly between the endpoints
?hlp    cpy bl_end
        bcs ?vert
        lda (ztptr),y
        jsr los_blocks
        bcs ?blocked
        iny
        bne ?hlp                ; (always: Y < bl_end <= 255)
?vert   ; --- vertical leg, along the target column ---
        lda bl_r0
        cmp bl_r1
        beq ?clear
        bcc ?vfwd
        ldy bl_r1               ; blast below target (A = bl_r0)
        bcs ?vgo                ; C=1: bcc not taken
?vfwd   tay                     ; blast above target (A = bl_r0)
        lda bl_r1
?vgo    sta bl_end
        iny
?vlp    cpy bl_end
        bcs ?clear
        sty bl_cur
        lda map_row_bank,y      ; rows of the leg may lie in different banks
        sta VBXE_BANK_SEL
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldy bl_c1
        lda (ztptr),y
        jsr los_blocks
        bcs ?blocked
        ldy bl_cur
        iny
        bne ?vlp                ; (always: Y < bl_end <= 255)
?clear  rts                     ; C=1: reached by beq after cmp, or by bcs
?blocked
        clc
        rts
bl_end  dta 0
bl_cur  dta 0
.endp

; ============================================
; BARREL_TILE_POS - top-left cell of decoration X (16x16 px = 2x2 cells)
; -> r_col / r_row. dc_y is the BOTTOM edge, so the row comes from
; (dc_y-16), 16-bit. Preserves X.
; ============================================
.proc barrel_tile_pos
        lda dc_xhi,x
        asl
        asl
        asl
        asl
        asl
        ldy dc_x,x
        ora div8_lut,y
        sta r_col
        lda dc_y,x              ; top edge = dc_y - 16 (16-bit)
        sec
        sbc #16
        tay                     ; (TAY leaves C alone)
        lda dc_y_hi,x
        sbc #0
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,y
        sta r_row
        rts
.endp

; BARREL_BL0 - blast tile of barrel X -> r_col/r_row and bl_c0/bl_r0
; (.copy: r_col/r_row already set). Preserves X.
.proc barrel_bl0
        jsr barrel_tile_pos
copy    lda r_col
        sta bl_c0
        lda r_row
        sta bl_r0
        rts
.endp

; ============================================
; FIND_BARREL_AT - which live barrel owns tile (gt_col, gt_row)?
; Out: C=1 -> X = decoration index, C=0 -> none (stale solid tile)
; ============================================
.proc find_barrel_at
        ldx #0
?lp     cpx num_dc
        bcs ?none
        lda dc_hp,x
        beq ?nx                 ; not a live barrel
        jsr barrel_tile_pos
        lda r_col
        cmp gt_col
        bne ?nx
        lda r_row
        cmp gt_row
        bne ?nx
        rts                     ; C=1: equal cmp
?nx     inx
        bne ?lp                 ; (always: X < num_dc <= MAX_DECOR)
?none   clc
        rts
.endp

; ============================================
; BARREL_IGNITE - start the explosion sequence for barrel X.
; Clearing hp is what keeps the dc_hp invariant true.
; Preserves X.
; ============================================
.proc barrel_ignite
        lda #0
        sta dc_hp,x
        lda #2
        sta dc_act,x
        lda #BARREL_EXP_TIME
        sta dc_timer,x
        inc dc_exp_cnt
        rts
.endp

; ============================================
; UPDATE DECORATIONS (barrel explosion logic)
; Returns immediately unless something is actually exploding - the common
; case, and this runs every frame.
; ============================================
.proc update_decorations
        lda dc_exp_cnt
        bne ?go
        rts
?go     ldx #0
?lp     lda dc_act,x
        cmp #2
        beq ?exp
?nx     inx
        cpx num_dc
        bcc ?lp
        rts
?exp    lda dc_timer,x
        cmp #BARREL_EXP_CHAIN
        bne ?chk_dmg
        jsr barrel_chain        ; uncover tile + sound + ignite neighbours
        bpl ?tick               ; (always: it ends on ldx bh_idx < MAX_DECOR)
?chk_dmg
        cmp #BARREL_EXP_DMG
        bne ?tick
        jsr barrel_explode      ; radius damage (~0.2s after the flash)
?tick   dec dc_timer,x
        bne ?nx
        lda #0                  ; timer 0: barrel disappears
        sta dc_act,x
        dec dc_exp_cnt
        bne ?nx
        rts                     ; that was the last one - skip the rest
.endp

; ============================================
; BARREL_CHAIN - X = barrel reaching BARREL_EXP_CHAIN: uncover its tile,
; play the blast and ignite every live barrel within BARREL_RADIUS that it
; can actually see. Newly lit barrels run their own chain scan when their
; timer gets here, so the reaction propagates outwards a few frames at a
; time - exactly like DOOM, where the blast simply damages the next barrel.
; Preserves X.
; ============================================
.proc barrel_chain
        stx bh_idx
        jsr barrel_clear_solid  ; the barrel stops blocking the moment it
                                ; blows, same as P_KillMobj dropping MF_SOLID
                                ; (its barrel_tile_pos left r_col/r_row set)
        jsr barrel_bl0.copy     ; blast tile for the LOS checks below
        lda #SFX_BAREXP
        jsr play_sfx            ; (preserves X = bh_idx, as do the calls above)
                                ; cache the blast centre: the scan below
        lda dc_x,x              ; indexes dc_* by the CANDIDATE instead
        sta bh_x
        lda dc_xhi,x
        sta bh_xhi
        lda dc_y,x
        sta bh_y
        lda dc_y_hi,x
        sta bh_yhi
        ldx #0
?lp     cpx bh_idx
        beq ?nx                 ; never chain to self
        lda dc_hp,x
        beq ?nx                 ; other decoration, or already lit
        lda bh_x                ; |dx| < BARREL_RADIUS ?
        sec
        sbc dc_x,x
        sta abs16.ab_lo
        lda bh_xhi
        sbc dc_xhi,x
        jsr abs16
        bcc ?nx
        cmp #BARREL_RADIUS
        bcs ?nx
        lda bh_y                ; |dy| < BARREL_RADIUS ?
        sec
        sbc dc_y,x
        sta abs16.ab_lo
        lda bh_yhi
        sbc dc_y_hi,x
        jsr abs16
        bcc ?nx
        cmp #BARREL_RADIUS
        bcs ?nx
        jsr barrel_tile_pos     ; candidate tile -> LOS
        lda r_col
        sta bl_c1
        lda r_row
        sta bl_r1
        jsr blast_los
        bcc ?nx                 ; wall in between - no chain
        jsr barrel_ignite
?nx     inx
        cpx num_dc
        bcc ?lp
        ldx bh_idx
        rts
bh_idx  dta 0
bh_x    dta 0
bh_xhi  dta 0
bh_y    dta 0
bh_yhi  dta 0
.endp

; ============================================
; BLAST_SEES_ENEMY - Y = enemy index. C=1 if the blast at bl_c0/bl_r0 can
; see the enemy's centre/chest tile. Clobbers A, X, Y.
; ============================================
.proc blast_sees_enemy
        lda en_x,y              ; enemy centre X
        clc
        adc #8
        sta wt_x
        lda enxhi,y
        adc #0
        sta wt_xhi
        lda en_y,y              ; enemy chest Y
        sec
        sbc #8
        sta wt_y
        lda en_y_hi,y
        sbc #0
        sta wt_yhi
.endp
        ert *<>blast_sees_wt
; BLAST_SEES_WT - C=1 if the blast at bl_c0/bl_r0 sees world point wt_*.
; Clobbers A, Y, ztptr. Preserves X (world_to_tile and blast_los do).
.proc blast_sees_wt
        jsr world_to_tile
        lda wt_col
        sta bl_c1
        lda wt_row
        sta bl_r1
        jmp blast_los
.endp

; ============================================
; BARREL EXPLODE - apply radius damage
; Input: X = barrel decoration index (preserved)
; ============================================
.proc barrel_explode
        stx bx_idx
        jsr barrel_bl0          ; blast tile, for every LOS check below
        ; --- Radius damage to enemies ---
        ldy #0
?elp    cpy num_en              ; only slots 0..num_en-1 can ever be active
        bcs ?edone
        sty bx_eidx
        lda en_act,y
        cmp #1
        bne ?enx
        ldx bx_idx              ; |dx| < BARREL_RADIUS ? (full 16-bit: the old
        lda dc_x,x              ; 8-bit page test left a dead zone at x=256)
        sec
        sbc en_x,y
        sta abs16.ab_lo
        lda dc_xhi,x
        sbc enxhi,y
        jsr abs16               ; preserves X and Y
        bcc ?enx
        cmp #BARREL_RADIUS
        bcs ?enx
        sta bx_dist
        lda dc_y,x              ; |dy| < BARREL_RADIUS ? (X = bx_idx, Y = bx_eidx)
        sec
        sbc en_y,y
        sta abs16.ab_lo
        lda dc_y_hi,x
        sbc en_y_hi,y
        jsr abs16
        bcc ?enx
        cmp #BARREL_RADIUS
        bcs ?enx
        cmp bx_dist             ; dist = max(|dx|,|dy|)  (DOOM box metric)
        bcs ?dok
        lda bx_dist
?dok    sta bx_dist
        jsr blast_sees_enemy    ; Y = bx_eidx; no damage through walls (P_CheckSight)
        bcc ?enx
        ldy bx_eidx
        jsr barrel_hurt_enemy
?enx    ldy bx_eidx
        iny
        bne ?elp                ; (always: Y <= num_en < 256)
?edone
        ; --- Radius damage + knockback to the player ---
        ldx bx_idx
        lda dc_x,x
        sta spl_x
        lda dc_xhi,x
        sta spl_xhi
        lda dc_y,x
        sta spl_y
        lda dc_y_hi,x
        sta spl_yhi
        ldy #?prm_n-1           ; spl_radius..spl_los (adjacent cells)
?prm    lda ?prm_t,y
        sta spl_radius,y
        dey
        bpl ?prm
        jmp explosion_splash_player ; tail call: it preserves X = bx_idx
?prm_t  dta BARREL_RADIUS,BARREL_PLR_MAX,BARREL_PLR_SCALE,BARREL_KB_X,BARREL_KB_Y
        dta 1                   ; spl_los: barrels respect walls (bl_c0/bl_r0 set)
?prm_n  = *-?prm_t
bx_idx  dta 0
bx_eidx dta 0
bx_dist dta 0
.endp
        ert spl_max<>spl_radius+1 || spl_scale<>spl_radius+2 || spl_kbx<>spl_radius+3 || spl_kby<>spl_radius+4 || spl_los<>spl_radius+5

; ============================================
; ENEMY_RIGHT_OF_BLAST - Y = enemy index. C=1 if it stands at or right of
; barrel barrel_explode.bx_idx. Full 16-bit, so a blast either side of
; x=256 still throws corpses the right way. Clobbers A, X.
; ============================================
.proc enemy_right_of_blast
        ldx barrel_explode.bx_idx
        lda en_x,y
        sec
        sbc dc_x,x
        lda enxhi,y
        sbc dc_xhi,x
        eor #$80                ; C = NOT bit 7 (the bmi test): 1 = right
        asl
        rts
.endp

; ============================================
; BARREL_HURT_ENEMY - Y = enemy index inside the blast radius,
; barrel_explode.bx_dist = box distance to the blast.
; DOOM-style linear falloff, then the kill / gib roll / death sound.
; Clobbers X, Y (its one caller, barrel_explode, reloads both).
; ============================================
.proc barrel_hurt_enemy
        lda #BARREL_DMG         ; damage = BARREL_DMG - dist, minimum 1
        sec
        sbc barrel_explode.bx_dist
        beq ?dmg_1              ; 0 -> 1
        bcs ?dmg_set            ; no borrow: 1..
?dmg_1  lda #1                  ; underflow -> 1
?dmg_set
        sta be_dmg
        lda en_hp,y
        sta be_oldhp
        sec
        sbc be_dmg
        bcs ?hok
        lda #0
?hok    sta en_hp,y
        beq ?kill
        tya                     ; survived: pain / wake-up (TMonster.Damage)
        tax
        lda be_dmg
        jmp en_hurt             ; tail call
?kill   lda #2
        sta en_act,y
        lda #0
        sta en_gib,y
        inc stat_kills          ; barrel kills count for the level stats too
        ; --- knockback away from the blast (DOOM thrusts every victim) ---
        jsr enemy_right_of_blast
        bcs ?kbr
        lda #$FF                ; corpse left of the barrel -> fling left
        bne ?kbset              ; always
?kbr    lda #1
?kbset  sta envelx,y
        lda #$FF                ; a little lift, gravity takes it from there
        sta envely,y
        ; Gib check: only zombie, imp, shotgun
        lda en_type,y
        cmp #EN_ZOMBIE
        beq ?gchk
        cmp #EN_IMP
        beq ?gchk
        cmp #EN_SHOTGUN
        bne ?death_snd
?gchk   ; overkill = damage dealt - old hp; threshold = overkill*3 + 10
        lda be_dmg
        sec
        sbc be_oldhp
        bcs ?ovk_ok
        lda #0
?ovk_ok sta be_thr
        asl                     ; overkill <= be_dmg <= BARREL_DMG < 128: C=0
        adc be_thr              ; *3
        adc #10                 ; +10 base
        sta be_thr
        ; Roll per ENEMY, not per explosion: zfr/RTCLOK3 are constant for the
        ; whole blast, so on their own every victim got the same coin flip.
        lda zfr
        eor RTCLOK3
        eor en_x,y
        eor en_y,y
        and #$3F
        cmp be_thr
        bcs ?death_snd          ; roll too high -> normal death
        ; Gib! Set flag + a much harder throw
        lda #1
        sta en_gib,y
        lda #$FE
        sta envely,y
        jsr enemy_right_of_blast
        bcs ?bkr
        lda #$FE
        bne ?bkset              ; always
?bkr    lda #2
?bkset  sta envelx,y
        lda #SFX_SLOP
        jmp play_sfx            ; (2026-11-10 6502-idioms.md "jsr X / rts -> jmp X")
?death_snd
        tya                     ; Y = the enemy (nothing since entry wrote Y)
        tax
        jmp play_enemy_death    ; tail call
be_oldhp dta 0
be_dmg   dta 0
be_thr   dta 0
.endp

; ============================================
; EXPLOSION SPLASH ON THE PLAYER - shared by barrels and rockets.
; In: spl_x/spl_xhi, spl_y/spl_yhi = blast centre (16-bit world, same anchor
;     as the player: left edge / feet)
;     spl_radius, spl_max, spl_scale, spl_kbx, spl_kby
;     spl_los = 1 -> require line of sight (bl_c0/bl_r0 must be set)
; damage = spl_max - max(|dx|,|dy|) * spl_scale, minimum 1
; plus knockback away from the blast, horizontal and vertical.
; pl_expl_iframe gates it so a chain of barrels cannot stack full hits.
; Preserves X.
; ============================================
.proc explosion_splash_player
        lda pl_expl_iframe
        bne ?out
        lda zphp
        bne ?live
?out    rts                     ; immune, or already dead
?live   lda spl_x               ; |dx| within radius?
        sec
        sbc zpx
        sta abs16.ab_lo
        lda spl_xhi
        sbc zpx_hi
        jsr abs16
        bcc ?out
        cmp spl_radius
        bcs ?out
        sta spl_dist
        lda spl_y               ; |dy| within radius?
        sec
        sbc zpy
        sta abs16.ab_lo
        lda spl_yhi
        sbc zpy_hi
        jsr abs16
        bcc ?out
        cmp spl_radius
        bcs ?out
        cmp spl_dist            ; distance = max(|dx|, |dy|)
        bcs ?dok
        lda spl_dist
?dok    sta spl_dist
        lda spl_los             ; walls stop the blast (DOOM P_CheckSight)
        beq ?in_range
        lda zpx                 ; player centre / chest
        clc
        adc #8
        sta wt_x
        lda zpx_hi
        adc #0
        sta wt_xhi
        lda zpy
        sec
        sbc #16
        sta wt_y
        lda zpy_hi
        sbc #0
        sta wt_yhi
        jsr blast_sees_wt       ; preserves X
        bcc ?out
?in_range
        lda spl_dist
        asl                     ; dist*2 (dist < radius <= 32, no carry out)
        ldy spl_scale
        cpy #3
        bcc ?scaled
        clc
        adc spl_dist            ; dist*3
?scaled sta spl_dist
        lda spl_max             ; farther = less damage
        sec
        sbc spl_dist
        bcc ?pmin               ; underflow = minimum damage
        bne ?papply             ; (A >= 1 <=> A <> 0)
?pmin   lda #1
?papply jsr player_take_damage
        lda #EXPL_IFRAME
        sta pl_expl_iframe
        ; --- Knockback: throw the player away from the blast ---
        lda zpx                 ; sign of (player - blast), 16-bit
        sec
        sbc spl_x
        lda zpx_hi
        sbc spl_xhi
        bpl ?kb_r               ; player right of blast -> push right
        lda #0                  ; player left of blast -> push left
        sec
        sbc spl_kbx
        bcc ?kb_set             ; kbx <> 0 borrows; kbx = 0 falls into ?kb_r: 0 too
?kb_r   lda spl_kbx
?kb_set sta zpvx
        ; Vertical: standing on or above the blast gets lifted (the barrel
        ; jump); strictly below it gets slammed down. Smaller Y = higher up.
        lda zpy
        sec
        sbc spl_y
        sta spl_dist            ; (spl_dist is free again, damage is applied)
        lda zpy_hi
        sbc spl_yhi
        bmi ?kb_up              ; player above the blast
        ora spl_dist
        beq ?kb_up              ; same level - standing next to / on it
        lda spl_kby             ; player below the blast -> slam down
        sta zpvy
        rts
?kb_up  lda #0
        sec
        sbc spl_kby             ; lift
        sta zpvy
        lda #0
        sta zpgnd               ; airborne, so the lift actually happens
        rts
spl_dist  dta 0
.endp

; ============================================
; PROJ_HIT_BARREL - a projectile reached the invisible solid tile at
; (gt_col, gt_row). Damage the barrel that owns it.
; Input: X = projectile index (clobbered: its one caller reloads it)
; ============================================
.proc proj_hit_barrel
        stx pb_proj
        jsr find_barrel_at      ; X = decoration index
        bcc ?ret
        ldy pb_proj
        lda dc_hp,x
        sbc proj_dmg,y          ; C=1: the bcc above not taken
        bcs hp_set
        lda #0
hp_set  sta dc_hp,x             ; (hs_chk_barrel's tail too)
        jeq barrel_ignite       ; tail call (6502-idioms: bxx skip / jmp T)
?ret    rts
pb_proj dta 0
.endp

; ============================================
; BARREL MAP SOLID: write/clear solid tile
; X = decoration index (preserved)
;
; The bg canvas is only recomposited when the camera crosses a tile
; (camera.asm composite_frame), so a map write that CHANGES what is visible
; has to force a rebuild - same as doors and switches do.
; ============================================
; BARREL_SET_SOLID / BARREL_CLEAR_SOLID - the 2x2 cells of barrel X become
; the invisible solid tile 15 (originals kept in dc_orig_tile) / get their
; originals back. A cell whose visible tile changes is queued for a canvas
; patch. X is never written (calc_map_ptr and canvas_mark_tile keep it).
.proc barrel_set_solid
        clc                     ; C=0: set
        dta $24                 ; bit zp: skips the sec (C kept)
        ert *<>barrel_clear_solid
.endp
.proc barrel_clear_solid
        sec                     ; C=1: clear
        ert *<>barrel_cells
.endp
.proc barrel_cells
        ror bc_mode             ; bit 7 = C: clear
        stx bc_x
        jsr barrel_tile_pos     ; keeps X
        stx bc_k                ; dc_orig_tile index of cell 0
        jsr ?row
        inc r_row
        jsr ?row
        dec r_row
        ldx bc_x
        rts
?row    jsr calc_map_ptr
        ldy #0
        jsr ?cell
        iny                     ; (?cell returns with Y kept)
?cell   sty bc_y
        ldx bc_k                ; X = this cell's dc_orig_tile index,
        txa                     ; bc_k = the next cell's
        clc
        adc #MAX_DECOR
        sta bc_k
        bit bc_mode
        bmi ?clr
        lda (ztptr),y           ; set: keep the original (a stray 15 reads as 0)
        cmp #15
        bne ?keep
        lda #0
?keep   sta dc_orig_tile,x
        lda #15
        sta (ztptr),y
        lda dc_orig_tile,x      ; a visible tile just got hidden -> patch
        jmp ?next
?clr    lda dc_orig_tile,x
        sta (ztptr),y           ; a hidden tile becomes visible -> patch
?next   beq ?ret
        lda r_col               ; patch this cell: (r_col + bc_y, r_row)
        clc
        adc bc_y
        ldy r_row
        jsr canvas_mark_tile
?ret    ldy bc_y
        rts
bc_mode dta 0
bc_k    dta 0
bc_y    dta 0
bc_x    dta 0
.endp
