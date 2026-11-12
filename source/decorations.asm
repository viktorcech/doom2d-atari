;==============================================
; DOOM2D - Decorations: the barrels (the original's maps have no others)
; decorations.asm
;
; Barrel logic is in barrel.asm
;==============================================

; Decoration arrays
dc_act  .ds MAX_DECOR            ; 0=dead, 1=active, 2=exploding
dc_x    .ds MAX_DECOR            ; X position (lo)
dc_xhi  .ds MAX_DECOR            ; X position (hi)
dc_orig_tile .ds 4*MAX_DECOR     ; original tiles under a barrel's 2x2 cells
                                 ; (cell k of decoration X at k*MAX_DECOR+X)
dc_y    .ds MAX_DECOR            ; Y position (low byte)
dc_y_hi .ds MAX_DECOR            ; Y position (high byte, 16-bit for tall maps)
dc_hp   .ds MAX_DECOR            ; hit points
dc_timer .ds MAX_DECOR           ; explosion timer

dc_exp_cnt dta 0                 ; how many slots are currently act==2.
                                 ; update_decorations / render_exploding bail
                                 ; out on 0, which is the normal case - that
                                 ; is two 16-slot scans saved every frame.

; Only barrels are solid: the invisible tile 15 they write into the map.

; init_decorations is in the overlay segment (end of main.asm)

; ============================================
; RENDER STATIC: draw all pickups, then falls into render_decorations (every
; frame).
; ============================================
.proc render_static
        ldx an_cnt              ; item animations: one phase for all items of
        beq ?nt                 ; a speed (TAnimation per item, all in step),
?tk     inc it_c20              ; once per animation tick of the frame
        lda it_c20
        cmp #20
        bcc ?c15
        lda #0
        sta it_c20
        ldy it_p20              ; 0..11: a multiple of every sequence (4, 6)
        iny
        cpy #12
        bcc ?s20
        ldy #0
?s20    sty it_p20
?c15    inc it_c15
        lda it_c15
        cmp #15
        bcc ?tn
        lda #0
        sta it_c15
        ldy it_p15              ; 0..5: the sphere's sequence
        iny
        cpy #6
        bcc ?s15
        ldy #0
?s15    sty it_p15
?tn     dex
        bne ?tk
?nt     ; Cheap reject before any setup: an item reaches at most 32 px
        ; (4 cells) right / up of its cell, so the window it can show in is
        ; columns cam_tcol-2..cam_tcol+TILES_X and rows cam_trow..+TILES_Y+2.
        lda #2                  ; the bounds negated: col + (2 - cam_tcol),
        sec                     ; row + (0 - cam_trow), added with C=0
        sbc cam_tcol
        sta ?c+1
        lda #0
        sec
        sbc cam_trow
        sta ?r+1
        ldx #0
        jmp ?test
?pk     lda pk_act,x            ; C=0 (jcc ?pk)
        jeq ?pnx
        lda pk_col,x
?c      adc #0                  ; (patched: 2 - cam_tcol)
        cmp #TILES_X+3
        bcs ?pnx
        lda pk_row,x            ; C=0 (bcs not taken)
?r      adc #0                  ; (patched: 0 - cam_trow)
        cmp #TILES_Y+3
        bcs ?pnx
        stx render_decorations.rd_idx   ; shared save cell: blit_frame clobbers X/Y
        ldy pk_type,x           ; frame = ip_r + phase mod ip_n (g_items.pas)
        lda ip_spd,y
        beq ?ph                 ; still: A = 0, C=0 (the row test)
        cmp #15
        bne ?p20
        lda it_p15
        bpl ?mod                ; (always: 0..5)
?p20    lda it_p20
?mod    cmp ip_n,y
        bcc ?fold
        sbc ip_n,y
        bcs ?mod                ; (always: C=1 from the sbc)
?fold   cmp ip_h,y              ; ping-pong: the way back is ip_n - phase
        bcc ?ph                 ; (C=0)
        eor #$FF                ; C=1: -phase-1 + ip_n + 1
        adc ip_n,y
        clc
?ph     adc ip_r,y              ; C=0 on every way in
        tay                     ; Y = frame
        lda it_ox,y             ; zdxh:zdx = pk_x + signed offset (C=0: a
        sta ?ox+1               ; frame number < 256)
        adc pk_x,x
        sta zdx
?ox     lda #0                  ; (patched: the offset, for its sign)
        and #$80
        beq ?xp
        lda #$FF
?xp     adc pk_xhi,x
        sta zdxh
        lda it_oy,y             ; zdy_hi:zdy = pk_y (feet) + signed offset
        sta ?oy+1
        clc
        adc pk_y,x
        sta zdy
?oy     lda #0                  ; (patched)
        and #$80
        beq ?yp
        lda #$FF
?yp     adc pk_y_hi,x
        sta zdy_hi
        jsr it_blit             ; item frame Y
        ldx render_decorations.rd_idx
?pnx    inx
?test   cpx pk_end
        jcc ?pk
        ert *<>render_decorations   ; falls into decorations (16-bit Y, own zdy_hi)
.endp

; ============================================
; RENDER DECORATIONS - standing barrels: BARREL_SLEEP, 3 frames a loop of
; 3 AI ticks each (TMonster anim), one phase for all barrels
; ============================================
.proc render_decorations
        bit ai_now
        bpl ?go
        inc bl_c
        lda bl_c
        cmp #3
        bcc ?go
        lda #0
        sta bl_c
        ldy bl_p
        iny
        cpy #3
        bcc ?p
        ldy #0
?p      sty bl_p
?go     ldx #0
        beq ?lp             ; (always) slot 0 first
?nx2    stx rd_idx
?nx     ldx rd_idx
        inx
        cpx num_dc          ; slots >= num_dc are always empty
        bcs ?r
?lp     lda dc_act,x
        cmp #1
        bne ?nx2            ; 0 = empty; 2 = exploding: render_exploding
        lda bl_p            ; C=1: the cmp #1 was equal
        adc #BARREL_SLEEP0-1
        jsr dc_draw
        jmp ?nx
?r      rts
rd_idx  dta 0
bl_c    dta 0
bl_p    dta 0
.endp

; ============================================
; RENDER EXPLODING BARRELS - BARREL_DIE, 4 frames over the explosion
; (dc_timer BARREL_EXP_TIME..0, 8 frames each); then nothing (D2DF: a dead
; barrel is not drawn)
; ============================================
.proc render_exploding
        lda dc_exp_cnt
        bne ?go             ; nothing burning -> skip the whole scan
        rts
?go     ldx #0
        beq ?lp             ; ldx #0 -> Z=1: enter at the loop head
?nx     ldx render_decorations.rd_idx
        inx
        cpx num_dc
        bcc ?lp
        rts
?lp     stx render_decorations.rd_idx
        lda dc_act,x
        cmp #2
        bne ?nx
        lda #BARREL_EXP_TIME    ; C=1: the cmp #2 was equal
        sbc dc_timer,x
        lsr
        lsr
        lsr                 ; 0..3
        clc
        adc #BARREL_DIE0
        jsr dc_draw
        jmp ?nx
        ert BARREL_EXP_TIME>31
.endp

; DC_DRAW - frame A at barrel X (dc_x = centre - 8, dc_y = feet), not
; mirrored. Saves X in render_decorations.rd_idx (blit_frame clobbers it).
.proc dc_draw
        stx render_decorations.rd_idx
        tay                     ; Y = frame
        lda mf_ox,y             ; zdxh:zdx = dc_x + signed offset
        sta ?ox+1
        clc
        adc dc_x,x
        sta zdx
?ox     lda #0                  ; (patched: the offset, for its sign)
        and #$80
        beq ?xp
        lda #$FF
?xp     adc dc_xhi,x
        sta zdxh
        lda mf_oy,y             ; zdy_hi:zdy = dc_y + signed offset
        sta ?oy+1
        clc
        adc dc_y,x
        sta zdy
?oy     lda #0                  ; (patched)
        and #$80
        beq ?yp
        lda #$FF
?yp     adc dc_y_hi,x
        sta zdy_hi
        lda #0
        sta bf_mir
        tya
        tax
        jmp blit_frame
.endp

; ============================================
; DECOR_RECOUNT_EXP - rebuild dc_exp_cnt from dc_act. Called after loading a
; savegame, which restores the dc_* arrays but not the derived counter.
; ============================================
.proc decor_recount_exp
        ldx #0
        stx dc_exp_cnt
?lp     cpx num_dc
        bcs ?ret
        lda dc_act,x
        cmp #2
        bne ?nx
        inc dc_exp_cnt
?nx     inx
        bne ?lp             ; X <= num_dc <= MAX_DECOR -> never wraps, Z=0
?ret    rts
.endp

it_c20  dta 0               ; item animation ticks / phases (render_static)
it_p20  dta 0
it_c15  dta 0
it_p15  dta 0
        icl 'gen/item_anims.asm'
