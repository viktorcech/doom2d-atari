;==============================================
; DOOM2D - Decorations (static map objects)
; decorations.asm
;
; Torches, pillars, lamps, gore
; Barrel logic is in barrel.asm
;==============================================

; Decoration arrays
dc_act  .ds MAX_DECOR            ; 0=dead, 1=active, 2=exploding
dc_x    .ds MAX_DECOR            ; X position (lo)
dc_xhi  .ds MAX_DECOR            ; X position (hi)
dc_orig_tile .ds MAX_DECOR       ; original tile under barrel (for restore)
dc_y    .ds MAX_DECOR            ; Y position
dc_type .ds MAX_DECOR            ; type (DC_xxx)
dc_hp   .ds MAX_DECOR            ; hit points (barrels only)
dc_timer .ds MAX_DECOR           ; explosion timer

; Decoration properties: width, height per type
dc_wtab
        dta 16                   ; DC_BARREL
        dta 16                   ; DC_TORCH
        dta 16                   ; DC_PILLAR
        dta 16                   ; DC_LAMP
        dta 16                   ; DC_DEADGUY
        dta 16                   ; DC_TECHTHING

dc_htab
        dta 16                   ; DC_BARREL
        dta 32                   ; DC_TORCH (tall)
        dta 32                   ; DC_PILLAR (tall)
        dta 16                   ; DC_LAMP
        dta 16                   ; DC_DEADGUY
        dta 16                   ; DC_TECHTHING

; Solid flag: 1 = blocks movement (player can't walk through)
dc_solid
        dta 1                    ; DC_BARREL: solid
        dta 0                    ; DC_TORCH: pass through
        dta 1                    ; DC_PILLAR: solid
        dta 0                    ; DC_LAMP: pass through
        dta 0                    ; DC_DEADGUY: pass through
        dta 0                    ; DC_TECHTHING: pass through

; Decoration type -> sprite index
dc_spr_tab
        dta 56                   ; DC_BARREL     -> barrel
        dta 58                   ; DC_TORCH      -> torch
        dta 57                   ; DC_PILLAR     -> pillar
        dta 59                   ; DC_LAMP       -> lamp
        dta 0                    ; DC_DEADGUY    -> TODO
        dta 0                    ; DC_TECHTHING  -> TODO

; init_decorations is in the overlay segment (end of main.asm)

; ============================================
; RENDER DECORATIONS (initial full render)
; ============================================
.proc render_decorations
        ldx #0
?lp     lda dc_act,x
        beq ?nx
        stx rd_idx
        lda dc_x,x
        sta zdx
        lda dc_xhi,x
        sta zdxh
        lda dc_type,x
        tay
        lda dc_y,x
        sec
        sbc dc_htab,y
        bcc ?nx2
        sta zdy
        lda dc_wtab,y
        sta md_w
        lda dc_htab,y
        sta md_h
        jsr mark_dirty_sprite
        ldx rd_idx
        lda dc_act,x
        cmp #2
        bne ?draw
        lda dc_timer,x
        and #4
        beq ?nx2
?draw   ldx rd_idx
        lda dc_type,x
        tax
        lda dc_spr_tab,x
        jsr blit_sprite
?nx2    ldx rd_idx
?nx     inx
        cpx #MAX_DECOR
        bne ?lp
        rts
rd_idx  dta 0
.endp

; ============================================
; RENDER DECORATIONS - NO DIRTY (per-frame static redraw)
; ============================================
.proc render_decor_nodirty
        lda dirty_any
        beq ?skip
        ldx #0
?lp     lda dc_act,x
        cmp #1
        bne ?nx
        stx rn_idx
        lda dc_xhi,x
        asl
        asl
        asl
        asl
        sta rn_tc
        lda dc_x,x
        lsr
        lsr
        lsr
        lsr
        ora rn_tc
        cmp dirty_min_col
        bcc ?nx2
        cmp dirty_max_col
        beq ?col_ok
        bcs ?nx2
?col_ok lda dc_type,x
        tay
        lda dc_y,x
        sec
        sbc dc_htab,y
        bcc ?nx2
        lsr
        lsr
        lsr
        lsr
        cmp dirty_min_row
        bcc ?nx2
        cmp dirty_max_row
        beq ?row_ok
        bcs ?nx2
?row_ok ldx rn_idx
        lda dc_x,x
        sta zdx
        lda dc_xhi,x
        sta zdxh
        lda dc_type,x
        tay
        lda dc_y,x
        sec
        sbc dc_htab,y
        sta zdy
        ldx rn_idx
        lda dc_type,x
        tax
        lda dc_spr_tab,x
        jsr blit_sprite
?nx2    ldx rn_idx
?nx     inx
        cpx #MAX_DECOR
        bne ?lp
?skip   rts
rn_idx  dta 0
rn_tc   dta 0
.endp

; ============================================
; RENDER EXPLODING BARRELS (game loop)
; ============================================
.proc render_exploding
        ldx #0
?lp     lda dc_act,x
        cmp #2
        bne ?nxj
        jmp ?draw
?nxj    jmp ?nx
?draw
        stx rx_idx
        lda dc_x,x
        sta zdx
        lda dc_xhi,x
        sta zdxh
        lda dc_type,x
        tay
        lda dc_y,x
        sec
        sbc dc_htab,y
        bcc ?nx2
        sta zdy
        lda dc_wtab,y
        sta md_w
        lda dc_htab,y
        sta md_h
        jsr mark_dirty_sprite
        ldx rx_idx
        lda dc_act,x
        cmp #3
        beq ?nx2
        lda dc_type,x
        cmp #DC_BARREL
        bne ?blink
        ; Barrel explosion: timer 30-21=exp1, 20-11=exp2, 10-1=exp3+blink
        lda dc_timer,x
        cmp #21
        bcs ?exp1
        cmp #11
        bcs ?exp2
        lsr
        bcs ?nx2
        lda #SPR_BARREL_EXP3
        jmp ?draw_exp
?exp1   lda #SPR_BARREL_EXP1
        jmp ?draw_exp
?exp2   lda #SPR_BARREL_EXP2
?draw_exp
        jsr blit_sprite
        jmp ?nx2
?blink  lda dc_timer,x
        and #4
        beq ?nx2
        lda dc_type,x
        tax
        lda dc_spr_tab,x
        jsr blit_sprite
?nx2    ldx rx_idx
?nx     inx
        cpx #MAX_DECOR
        beq ?ret
        jmp ?lp
?ret    rts
rx_idx  dta 0
.endp
