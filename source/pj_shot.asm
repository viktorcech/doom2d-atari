;==============================================
; DOOM2D - pj_shot (player_proj.asm), in the page after y_addr_hi
;==============================================

; PJ_SHOT - SHOT triggers on the cells within A of (gt_col, gt_row)
.proc pj_shot
        sta ?rad
        lda gt_col
        sec
        sbc ?rad
        bcs ?c
        lda #0
?c      sta mc0
        lda gt_row
        sec
        sbc ?rad
        bcs ?r
        lda #0
?r      sta mr0
        lda gt_col
        sec                     ; + rad + 1: exclusive
        adc ?rad
        sta mc1
        lda gt_row
        sec
        adc ?rad
        sta mr1
        jmp trig_shot
?rad    dta 0
.endp

