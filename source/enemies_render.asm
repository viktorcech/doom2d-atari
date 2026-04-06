;==============================================
; DOOM2D - Enemy rendering
; enemies_render.asm
;==============================================

; ============================================
; RENDER ALL ENEMIES
; ============================================
.proc render_enemies
        ldx #0
?lp     lda en_act,x
        bne ?vis
        jmp ?nx
?vis    stx zzidx
        ; Screen position
        lda en_x,x
        sta zdx
        lda enxhi,x
        sta zdxh
        bpl ?xok
        jmp ?nx2
?xok    lda en_y,x
        sec
        sbc #32
        bcs ?yok
        jmp ?nx2
?yok
        sta zdy
        ; Check if dying -> use death sprite
        lda en_act,x
        cmp #2
        beq ?dying
        jmp ?walkanim
?dying
        ; Death animation: select sprite by timer phase and gib flag
        ; Gib: timer 20-10 = gib1, 9-1 = gib2 + blink
        ; Normal: timer 20-14 = death1, 13-7 = death2, 6-1 = death3 + blink
        lda en_gib,x
        bne ?gib
        ; --- Normal death ---
        lda en_dtimer,x
        cmp #14
        bcs ?d_fr1
        cmp #7
        bcs ?d_fr2
        ; Blink in last phase
        lsr
        bcs ?skip_draw
        ; Frame 3: death3 from table (0 = fallback to death1)
        jsr ?get_death3
        jmp ?deathdraw
?d_fr1  ; Frame 1: base death sprite (base_spr + 5)
        jsr ?get_death1
        jmp ?deathdraw
?d_fr2  ; Frame 2: death2 from table (0 = fallback to death1)
        jsr ?get_death2
        jmp ?deathdraw
?gib    ; --- Gib death ---
        lda en_dtimer,x
        cmp #10
        bcs ?g_fr1
        ; Blink in last phase
        lsr
        bcs ?skip_draw
        ; Frame 2: gib2 from table
        lda en_type,x
        tax
        lda en_gib2_spr,x
        ldx zzidx
        jmp ?deathdraw
?g_fr1  ; Frame 1: gib1 from table
        lda en_type,x
        tax
        lda en_gib1_spr,x
        ldx zzidx
?deathdraw
        ; Mark dirty + draw WITHOUT mirror
        pha
        lda #16
        sta md_w
        lda #32
        sta md_h
        jsr mark_dirty_sprite
        pla
        jsr blit_sprite
        jmp ?nx2
?skip_draw
        jmp ?nx2
        ; --- Helper: get death sprite by type ---
?get_death1
        lda en_type,x
        tax
        lda en_base_spr,x
        clc
        adc #5
        ldx zzidx
        rts
?get_death2
        lda en_type,x
        tax
        lda en_death2_spr,x
        beq ?gd2_fb         ; 0 = no death2, use death1
        ldx zzidx
        rts
?gd2_fb ldx zzidx
        jsr ?get_death1
        rts
?get_death3
        lda en_type,x
        tax
        lda en_death3_spr,x
        beq ?gd3_fb         ; 0 = no death3, use death1
        ldx zzidx
        rts
?gd3_fb ldx zzidx
        jsr ?get_death1
        rts
?walkanim
        ; Calculate sprite index: base + walk frame
        lda en_type,x
        tax
        lda en_base_spr,x
        sta re_base
        ldx zzidx
        ; Check pain first
        lda en_pain_tmr,x
        beq ?no_epain
        ; Show pain sprite
        lda en_type,x
        tay
        lda en_pain_spr,y
        beq ?no_epain          ; 0 = no pain sprite
        ldy en_dir,x
        beq ?epain_r
        jmp ?dodraw_pain       ; dir=1 (left) = base variant
?epain_r
        clc
        adc #1                 ; +1 = _L variant
?dodraw_pain
        pha
        lda #16
        sta md_w
        lda #32
        sta md_h
        jsr mark_dirty_sprite
        pla
        jmp ?dopain
?no_epain
        ; Check if shooting (just fired: alerted + timer in shoot range)
        lda en_type,x
        cmp #EN_ZOMBIE
        beq ?chk_shoot
        cmp #EN_SHOTGUN
        beq ?chk_shoot
        cmp #EN_IMP
        beq ?chk_shoot
        cmp #EN_PINKY
        beq ?chk_shoot
        cmp #EN_CACO
        beq ?chk_shoot
        jmp ?walk
?chk_shoot
        lda en_cooldown,x
        beq ?walk              ; not alerted = no shoot sprite
        lda en_atk,x
        cmp #15
        bcs ?walk
        beq ?walk
        lda re_base
        clc
        adc #4                 ; shoot = base + 4
        jmp ?dodraw
?walk   ; Walk animation: cycle through 3 walk frames in pattern 1,2,3,2
        ; (zfr >> 3) & 3 gives values 0,1,2,3 cycling every 8 frames
        ; When result is 3, remap to 1 → final pattern: 0,1,2,1
        ; Then +1 to offset from base (walk sprites = base+1..base+3)
        lda zfr
        lsr
        lsr
        lsr                ; zfr / 8 = change frame every 8 game frames
        and #$03           ; mod 4 = values 0,1,2,3
        cmp #3
        bne ?fok
        lda #1             ; 3 → 1 (creates bounce: 0,1,2,1,0,1,2,1...)
?fok    clc
        adc #1             ; walk1=base+1, walk2=base+2, walk3=base+3
        clc
        adc re_base
?dodraw ; Mark dirty tiles before drawing
        pha
        lda #16
        sta md_w
        lda #32
        sta md_h
        jsr mark_dirty_sprite
        pla
        ; Base sprites face LEFT, _L sprites face RIGHT
        ; dir=0 (right) -> +MIRROR_OFFSET, dir=1 (left) -> base
        ldx zzidx
        ldy en_dir,x
        bne ?noflip
        clc
        adc #MIRROR_OFFSET
?noflip
?dopain jsr blit_sprite
?nx2    ldx zzidx
?nx     inx
        cpx #MAX_ENEMIES
        bcs ?ret
        jmp ?lp
?ret    rts
re_base dta 0
.endp
