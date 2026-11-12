;==============================================
; DOOM2D - Trigger actions placed past the foreground code ($BA00+, free
; RAM below the Y-address tables): SOUND, SPAWNITEM, ACTIVATE_SHOT
;==============================================

; SOUND: p0 = SFX_* (D2DF plays it PlayCount times: 1 in the maps)
.proc t_sound
        lda tr_p0,x
        tax
        jsr snd_play
        jmp tr_done
.endp

; SPAWNITEM: a new pickup at pk_x = p0/p1, feet y = p2/p3, pk_type = flag
; bits 3-7; it falls (Gravity). No free slot: nothing (C=0).
.proc t_spawn
        ldy pk_end
        cpy #MAX_PICKUPS
        bcs ?no
        lda tr_p0,x
        sta pk_x,y
        lda tr_p1,x
        sta pk_xhi,y
        lda tr_p2,x
        sta pk_y,y
        lda tr_p3,x
        sta pk_y_hi,y
        lda tr_flag,x
        lsr
        lsr
        lsr
        sta pk_type,y
        lda #1
        sta pk_act,y
        jsr pk_set_tile         ; keeps X, Y
        iny
        sty pk_end
        jsr pk_wake
        jmp tr_done
?no     clc
        rts
.endp

; ============================================
; TRIG_SHOT - a shot over the cells [mc0, mc1) x [mr0, mr1): its SHOT
; triggers fire (g_Triggers_PressR/L/C with ACTIVATE_SHOT, no keys).
; ============================================
.proc trig_shot
        lda tr_shot
        and #AC_SHOT
        beq ?r                  ; the level has none
        ldx #0
        beq ?test               ; (always)
?lp     lda tr_act,x
        and #AC_SHOT
        beq ?nx
        lda tr_to,x
        ora tr_keys,x
        bne ?nx
        jsr over_mon
        bcc ?nx
        lda #$FF                ; nobody is moved (teleport)
        sta tr_who
        lda #AC_SHOT
        jsr tr_activate
        ldx tu_i
?nx     inx
?test   cpx n_tr
        bcc ?lp
?r      rts
.endp

