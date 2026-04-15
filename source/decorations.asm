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
        dta 16                   ; DC_EVILEYE
        dta 16                   ; DC_SKULPILLAR
        dta 16                   ; DC_ELECLAMP
        dta 16                   ; DC_DEADTREE
        dta 16                   ; DC_BROWNTREE
        dta 16                   ; DC_HANGBODY
        dta 16                   ; DC_HANGLEG
        dta 16                   ; DC_IMPALED
        dta 16                   ; DC_SKULLPILE
        dta 16                   ; DC_REDTORCH

dc_htab
        dta 16                   ; DC_BARREL
        dta 32                   ; DC_TORCH (tall)
        dta 32                   ; DC_PILLAR (tall)
        dta 32                   ; DC_LAMP (tall)
        dta 16                   ; DC_DEADGUY
        dta 16                   ; DC_TECHTHING
        dta 32                   ; DC_EVILEYE
        dta 32                   ; DC_SKULPILLAR
        dta 32                   ; DC_ELECLAMP
        dta 32                   ; DC_DEADTREE
        dta 32                   ; DC_BROWNTREE
        dta 32                   ; DC_HANGBODY
        dta 16                   ; DC_HANGLEG
        dta 32                   ; DC_IMPALED
        dta 16                   ; DC_SKULLPILE
        dta 32                   ; DC_REDTORCH

; Solid flag: 1 = blocks movement (player can't walk through)
dc_solid
        dta 1                    ; DC_BARREL: solid
        dta 0                    ; DC_TORCH: pass through
        dta 1                    ; DC_PILLAR: solid
        dta 0                    ; DC_LAMP: pass through
        dta 0                    ; DC_DEADGUY: pass through
        dta 0                    ; DC_TECHTHING: pass through
        dta 1                    ; DC_EVILEYE: solid
        dta 1                    ; DC_SKULPILLAR: solid
        dta 0                    ; DC_ELECLAMP: pass through
        dta 1                    ; DC_DEADTREE: solid
        dta 1                    ; DC_BROWNTREE: solid
        dta 0                    ; DC_HANGBODY: pass through (ceiling)
        dta 0                    ; DC_HANGLEG: pass through (ceiling)
        dta 0                    ; DC_IMPALED: pass through
        dta 0                    ; DC_SKULLPILE: pass through
        dta 0                    ; DC_REDTORCH: pass through

; Decoration type -> sprite index
dc_spr_tab
        dta 56                   ; DC_BARREL     -> barrel
        dta 58                   ; DC_TORCH      -> torch
        dta 57                   ; DC_PILLAR     -> pillar
        dta 59                   ; DC_LAMP       -> lamp
        dta 0                    ; DC_DEADGUY    -> TODO
        dta 0                    ; DC_TECHTHING  -> TODO
        dta SPR_DECOR_EVILEYE    ; DC_EVILEYE     -> evil eye
        dta SPR_DECOR_SKULPILLAR ; DC_SKULPILLAR -> skull pillar
        dta SPR_DECOR_ELECLAMP   ; DC_ELECLAMP   -> electric lamp
        dta SPR_DECOR_DEADTREE   ; DC_DEADTREE   -> dead tree
        dta SPR_DECOR_BROWNTREE  ; DC_BROWNTREE  -> brown tree
        dta SPR_DECOR_HANGBODY   ; DC_HANGBODY   -> hanging body
        dta SPR_DECOR_HANGLEG    ; DC_HANGLEG    -> hanging leg
        dta SPR_DECOR_IMPALED    ; DC_IMPALED    -> impaled human
        dta SPR_DECOR_SKULLPILE  ; DC_SKULLPILE  -> skull pile
        dta SPR_DECOR_REDTORCH1  ; DC_REDTORCH   -> red torch (frame 1)

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
        cmp #DC_REDTORCH
        beq ?anim
        tax
        lda dc_spr_tab,x
        jmp ?blit
?anim   lda zfr
        lsr
        lsr
        lsr                      ; zfr >> 3
        and #3                   ; & 3 -> frame 0-3
        clc
        adc #SPR_DECOR_REDTORCH1
?blit   jsr blit_sprite
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
        ldx #0
?lp     lda dc_act,x
        cmp #1
        beq ?vis
        jmp ?nx                 ; was bne ?nx (out of range)
?vis
        stx rn_idx
        ; Animated decorations (red torch) always redraw
        lda dc_type,x
        cmp #DC_REDTORCH
        beq ?force_draw
        ; Static decorations: only redraw if inside dirty bbox
        lda dirty_any
        beq ?nx_jmp
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
        bcs ?col_min_ok
        jmp ?nx2
?col_min_ok
        cmp dirty_max_col
        beq ?col_ok
        bcc ?col_ok
        jmp ?nx2
?col_ok lda dc_type,x
        tay
        jmp ?row_chk
?force_draw
        ; Red torch: mark dirty + draw every frame
        ldx rn_idx
        lda dc_type,x
        tay
        lda dc_y,x
        sec
        sbc dc_htab,y
        bcc ?nx_jmp
        sta zdy
        lda dc_x,x
        sta zdx
        lda dc_xhi,x
        sta zdxh
        lda dc_wtab,y
        sta md_w
        lda dc_htab,y
        sta md_h
        jsr mark_dirty_sprite
        jmp ?do_draw             ; skip bbox check, go straight to draw
?nx_jmp jmp ?nx2
?row_chk
        lda dc_type,x
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
?do_draw
        ldx rn_idx
        lda dc_type,x
        cmp #DC_REDTORCH
        beq ?anim
        tax
        lda dc_spr_tab,x
        jmp ?blit
?anim   lda zfr
        lsr
        lsr
        lsr
        and #3
        clc
        adc #SPR_DECOR_REDTORCH1
?blit   jsr blit_sprite
?nx2    ldx rn_idx
?nx     inx
        cpx #MAX_DECOR
        beq ?skip
        jmp ?lp                 ; was bne ?lp (out of range)
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
