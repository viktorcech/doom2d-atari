;==============================================
; DOOM2D - Enemy rendering
; enemies_render.asm
;==============================================

; ============================================
; RENDER ALL ENEMIES - the frame of en_anim/en_afr at en_x + mf_ox, en_y +
; mf_oy; facing left the type's _L frame or the right one mirrored
; (TMonster.Draw). Corpses (en_act 3) show their last DIE/MESS frame.
; ============================================
.proc render_enemies
        ; The cheap reject's window (fable-skill-atari: pass 1): a frame is at
        ; most 50 x 45 px, within 37 px of en_x / en_y (gen/mon_frames.asm), so
        ; only en_x - (cam_x - 64) and en_y - (cam_y - 64) under 512 can show.
        lda cam_x
        sec
        sbc #64
        sta ?cxl+1
        lda cam_x_hi
        sbc #0
        sta ?cxh+1
        lda cam_y
        sec
        sbc #64
        sta ?cyl+1
        lda cam_y_hi
        sbc #0
        sta ?cyh+1
        ldx #0
        beq ?lp                 ; (always) slot 0 is tested before the bound
?nx2    ldx zzidx               ; (the loop's end up here: in reach of ?lp)
?nx     inx
        cpx num_en              ; only slots 0..num_en-1 can ever be active
        bcc ?lp
        rts
?lp     lda en_act,x
        beq ?nx
        lda en_x,x              ; far off the window: no frame, no clip
?cxl    cmp #0                  ; (patched: cam_x - 64; the cmp is the borrow)
        lda enxhi,x
?cxh    sbc #0
        cmp #2
        bcs ?nx
        lda en_y,x
?cyl    cmp #0                  ; (patched: cam_y - 64)
        lda en_y_hi,x
?cyh    sbc #0
        cmp #2
        bcs ?nx
        stx zzidx
        lda en_type,x           ; Y = type*8 + anim (type < 32: the asl
        asl                     ; shift out zeros, C=0 down to ?pos)
        asl
        asl
        ora en_anim,x
        tay
        lda en_dir,x
        bne ?left
        sta bf_mir              ; A = 0: facing right, not mirrored
        lda ma_r,y
        adc en_afr,x
        tay                     ; Y = frame
        lda mf_ox,y
        bcc ?pos                ; (always: C=0, see ?pos)
?left   lda ma_flg,y            ; bit 7: left = the right frames mirrored
        bmi ?mir
        lda #0                  ; the type's own left frames
        sta bf_mir
        lda ma_l,y
        adc en_afr,x
        tay                     ; Y = frame
        lda mf_ox,y
        bcc ?pos                ; (always: C=0)
?mir    lda #$FF
        sta bf_mir
        lda ma_l,y
        adc en_afr,x
        tay                     ; Y = frame
        lda mf_oxm,y
        ; zdxh:zdx / zdy_hi:zdy = en_x / en_y + signed offset: the sign is the
        ; N of the offset's load (bcc keeps it), negative (most) falls through
        ; (2026-10-30 6502-idioms.md "Flags are values you track")
?pos    bpl ?xpos               ; C=0: a frame number + en_afr < 256
        adc en_x,x
        sta zdx
        lda enxhi,x
        adc #$FF                ; C from the low add
?xh     sta zdxh
        lda mf_oy,y
        bpl ?ypos
        clc
        adc en_y,x
        sta zdy
        lda en_y_hi,x
        adc #$FF
?yh     sta zdy_hi
        tya
        tax
        jsr blit_frame
        jmp ?nx2
?xpos   adc en_x,x              ; offset >= 0 (out of line: 6502-cycles-layout.md
        sta zdx                 ; "rare case out of line")
        lda enxhi,x
        adc #0
        bcc ?xh                 ; (always: a map x high byte + a carry)
?ypos   clc
        adc en_y,x
        sta zdy
        lda en_y_hi,x
        adc #0
        bcc ?yh                 ; (always: a map y high byte + a carry)
.endp
