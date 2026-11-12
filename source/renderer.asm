;==============================================
; DOOM2D - Rendering (tiles, sprites)
; renderer.asm
;==============================================

; ============================================
; RENDER TILES - the NSX x NSY tile window (cam_tcol/cam_trow .. +TILES_X/
; +TILES_Y) into the RING canvas: map column C -> canvas slot C mod NSX, map
; row R -> slot R mod NSY (camera.asm). Row pointer + row slot hoisted out of
; the column loop.
; ============================================
.proc render_tiles
        lda cam_tcol            ; end column = min(cam_tcol + NSX, MAP_W)
        clc
        adc #NSX                ; cam_tcol < MAP_W -> no wrap, end > start
        cmp #MAP_W
        bcc ?ncok
        lda #MAP_W
?ncok   sta ?cend+1             ; SMC: column bound as cpy # operand
        lda #0                  ; A = rt_j at the loop head
        clc                     ; loop-back arrives with C=0 (bcc taken)
?rrow   sta rt_j
        adc cam_trow            ; map row = window row + camera tile row
        cmp #MAP_H
        bcs ?done               ; past map bottom -> rest stays transparent (sky)
        tax
        lda sloty_lut,x
        sta r_row               ; ring slot row (constant for this row)
        lda map_row_bank,x
        sta ?bk+1               ; the row's bank as the column loop's immediate
        lda map_row_lo,x        ; ztptr = map row base (index with map col)
        sta ztptr
        lda map_row_hi,x
        sta ztptr+1
        ldy cam_tcol            ; Y = map column, cam_tcol .. end-1
?rcol
?bk     lda #0                  ; re-set each tile (tl_add leaves BCB bank)
        sta VBXE_BANK_SEL
        lda (ztptr),y           ; @pagecross: false (row base is 128-aligned, MAP_W <= 128)
        beq ?skip               ; tile 0 = empty -> sky shows through
        cmp #15
        beq ?skip               ; tile 15 = invisible solid (barrel)
        tax                     ; X = the tile (tl_add)
        lda slotx_lut,y
        sta r_col               ; ring slot column
        sty rt_mcol             ; (only a drawn tile needs Y saved)
        jsr tl_add
        ldy rt_mcol             ; tl_add clobbers Y
?skip   iny
?cend   cpy #0                  ; patched: end column
        bcc ?rcol               ; @taken: true  (loops over the NSX columns)
        jsr tl_flush
        ldx rt_j
        inx
        txa
        cmp #NSY                ; TILES_Y+1 rows (one extra for fine scroll)
        bcc ?rrow
?done   rts
rt_j    dta 0
rt_mcol dta 0
.endp

; r_row/r_col moved to zero page (zeropage.asm)

; ============================================
; RENDER PLAYER - the Doomer model (mon_frames.asm, type 7): DIE1 when dead
; (the body stays), PAIN, ATTACK while a gun cools down, WALK, STAND;
; stepped per 36 Hz tick like TAnimation. Frames face right, left mirrored.
; ============================================
PA_STAND  = 0                   ; ma_* slots of the player (prepare_sprites.py)
PA_WALK   = 1
PA_DIE1   = 2
PA_ATTACK = 4
PA_PAIN   = 6
MA_PLAYER = 7*8

.proc render_player
        lda zphp
        bne ?alive
        lda #PA_DIE1
        bne ?set                ; (always)
?alive  lda pl_pain_timer
        beq ?np
        lda #PA_PAIN
        bne ?set
?np     lda zpwcool
        beq ?ns
        ldx zpwcur
        lda weap_range,x
        bne ?ns                 ; melee: no attack pose
        lda #PA_ATTACK
        bne ?set
?ns     lda zpst
        cmp #1                  ; walking
        beq ?w
        lda #PA_STAND
        dta $2C                 ; bit abs: skips lda #PA_WALK
?w      lda #PA_WALK
?set    cmp pl_anim
        beq ?step
        sta pl_anim
        lda #0
        sta pl_afr
        sta pl_acnt
?step   ldy pl_anim
        ldx an_cnt              ; once per animation tick of the frame
        beq ?draw
?tk     inc pl_acnt
        lda pl_acnt
        cmp ma_spd+MA_PLAYER,y
        bcc ?tn
        lda #0
        sta pl_acnt
        inc pl_afr
        lda pl_afr
        cmp ma_n+MA_PLAYER,y
        bcc ?tn
        lda ma_flg+MA_PLAYER,y  ; played: bit 0 = loop
        lsr
        lda #0
        bcs ?wrap
        dec pl_afr              ; stays on the last frame
        bcc ?tn                 ; (always: C=0)
?wrap   sta pl_afr
?tn     dex
        bne ?tk
?draw   lda zpdir               ; 0 = right, 1 = left: mirrored
        beq ?r
        lda #$FF
?r      sta bf_mir
        lda zpwcur              ; the weapon first: the body covers it
        beq ?body               ; the fist: none (wa_fr has no row for it)
        asl
        asl
        asl
        ora pl_anim
        tay
        lda wa_fr-8,y
        cmp #$FF
        beq ?body               ; fist, DIE, PAIN: none
        adc pl_afr              ; C=0 (A < $FF)
        tax
        jsr pl_blit
?body   ldy pl_anim
        lda ma_r+MA_PLAYER,y
        clc
        adc pl_afr
        tax                     ; X = frame
        ert *<>pl_blit          ; falls through
.endp

; PL_BLIT - frame X at the player (zpx, zpy), mirrored when bf_mir = $FF
.proc pl_blit
        lda bf_mir
        bne ?m
        lda mf_ox,x
        jmp ?pos
?m      lda mf_oxm,x
?pos    sta ?ox+1               ; zdxh:zdx = zpx + signed offset
        clc
        adc zpx
        sta zdx
?ox     lda #0                  ; (patched: the offset, for its sign)
        and #$80
        beq ?xp
        lda #$FF
?xp     adc zpx_hi
        sta zdxh
        lda mf_oy,x             ; zdy_hi:zdy = zpy + signed offset
        sta ?oy+1
        clc
        adc zpy
        sta zdy
?oy     lda #0                  ; (patched)
        and #$80
        beq ?yp
        lda #$FF
?yp     adc zpy_hi
        sta zdy_hi
        jmp blit_frame
.endp
pl_anim dta 0
pl_afr  dta 0
pl_acnt dta 0

; ============================================
; RENDER PROJECTILES
; ============================================
.proc render_projs
        ldx #0
        beq ?lp                 ; ldx #0 -> Z=1: enter at the loop head
?done   rts
?nx     inx
        cpx #MAX_PROJ
        beq ?done
?lp     lda proj_a,x
        beq ?nx
        ; Rockets, plasma and BFG balls are drawn (hitscan = invisible); all
        ; animate every 4 frames, a rocket flying left uses its _L frames
        lda proj_spr,x
        cmp #SPR_ROCKET_PROJ
        beq ?rocket
        cmp #SPR_PLASMA_PROJ1
        beq ?two
        cmp #SPR_BFG_PROJ1
        bne ?nx                 ; not a drawn projectile
?two    tay                     ; 2 frames: base + (zfr>>2 & 1)
        lda zfr
        lsr
        lsr
        lsr                     ; C = zfr bit 2
        tya
        adc #0                  ; base <= 254 (PROJ2 = PROJ1+1, ert): C=0
        bcc ?draw_spr           ; (always)
?rocket lda zfr                 ; 4 frames, +4 = _L
        lsr
        lsr
        and #3
        ldy proj_vx,x
        bpl ?rr
        ora #4
?rr     clc
        adc #SPR_ROCKET_PROJ
?draw_spr
        stx rj_idx
        tay                     ; Y = sprite (blit_sprite clobbers X and Y)
        lda spr_ox,y            ; zdxh:zdx = proj_x + signed offset (centred)
        sta ?ox+1
        clc
        adc proj_x,x
        sta zdx
?ox     lda #0                  ; (patched: the offset, for its sign)
        and #$80
        beq ?xp
        lda #$FF
?xp     adc proj_xh,x
        sta zdxh
        lda spr_oy,y
        sta ?oy+1
        clc
        adc proj_y,x
        sta zdy
?oy     lda #0                  ; (patched)
        and #$80
        beq ?yp
        lda #$FF
?yp     adc proj_y_hi,x
        sta zdy_hi
        tya
        jsr blit_sprite
        ldx rj_idx
        bpl ?nx                 ; X < MAX_PROJ -> N=0
rj_idx  dta 0
.endp
        ert SPR_PLASMA_PROJ2<>SPR_PLASMA_PROJ1+1 .or SPR_BFG_PROJ2<>SPR_BFG_PROJ1+1
