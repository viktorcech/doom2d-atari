;==============================================
; DOOM2D - Enemy attack logic (per-type)
; enemies_attack.asm
;
; Called from update_enemies after LOS detection.
; Input: X = enemy index (zzidx set)
;==============================================

.proc enemy_do_attack
        ; --- Attack logic ---
?atk_check
        lda en_atk,x
        beq ?do_attack
        dec en_atk,x
        rts
?do_attack
        ; Check Y distance first (must be on similar level)
        lda en_y,x
        sec
        sbc zpy
        bpl ?atk_yp
        eor #$FF
        clc
        adc #1
?atk_yp cmp #24               ; within 24px vertical = can shoot
        bcc ?in_range
        rts                    ; too far vertically, skip
?in_range
        ; Lost Soul: charge melee (like Pinky but flies)
        lda en_type,x
        cmp #EN_LOSTSOUL
        bne ?not_lostsoul
        ; Check X distance for melee range (|en_x - zpx| < 20)
        lda en_x,x
        sec
        sbc zpx
        bpl ?ls_xp
        eor #$FF
        clc
        adc #1
?ls_xp  cmp #20
        bcs ?ls_no            ; too far for melee
        ; Lost Soul charge hit! 10 damage
        lda #10
        jsr player_take_damage
        lda #SFX_SKLATK
        jsr play_sfx_unlock
        ; Cooldown: 30-45 frames
        lda zfr
        eor RTCLOK3
        and #$0F
        clc
        adc #30
        sta en_atk,x
        rts
?ls_no  rts
?not_lostsoul
        ; Pinky: melee only (must be close)
        cmp #EN_PINKY          ; A still has en_type from lostsoul check
        bne ?not_pinky
        ; Check X distance for melee range (|en_x - zpx| < 20)
        lda en_x,x
        sec
        sbc zpx
        bpl ?pk_xp
        eor #$FF
        clc
        adc #1
?pk_xp  cmp #20
        bcs ?no_atk2            ; too far for melee, skip
        ; Pinky bite! 15 damage, aggressive cooldown
        lda #15
        jsr player_take_damage
        lda #SFX_SGTATK
        jsr play_sfx_unlock
        ; Short cooldown: 20-35 frames (~0.3-0.6s)
        lda zfr
        eor RTCLOK3
        and #$0F
        clc
        adc #20
        sta en_atk,x
        rts
?no_atk2 rts
?not_pinky
        ; Cacodemon: fireball (same projectile as imp, different damage)
        lda en_type,x
        cmp #EN_CACO
        bne ?not_caco
        ; Spawn caco fireball (reuses imp fireball system)
        jsr spawn_eproj
        ldx zzidx
        ; Fire sound (same as imp)
        lda #SFX_FIRSHT
        jsr play_sfx_unlock
        ; Caco cooldown: 50-80 frames (~0.8-1.3s)
        lda zfr
        eor RTCLOK3
        and #$0F
        clc
        adc #50
        sta en_atk,x
        rts
?not_caco
        ; Baron: fireball (high damage, reuses caco fireball sprite)
        lda en_type,x
        cmp #EN_BARON
        bne ?not_baron
        jsr spawn_eproj
        ldx zzidx
        lda #SFX_FIRSHT
        jsr play_sfx_unlock
        lda zfr
        eor RTCLOK3
        and #$0F
        clc
        adc #50
        sta en_atk,x
        rts
?not_baron
        ; Imp: melee if close, fireball if far
        lda en_type,x
        cmp #EN_IMP
        bne ?hitscan
        ; Check X distance for melee range (|en_x - zpx| < 20)
        lda en_x,x
        sec
        sbc zpx
        bpl ?imp_xp
        eor #$FF
        clc
        adc #1
?imp_xp cmp #20
        bcs ?imp_far
        ; Imp melee attack — claw damage 10
        lda #10
        jsr player_take_damage
        ; Imp claw melee sound
        lda #SFX_CLAW
        jsr play_sfx_unlock
        ; Melee has shorter cooldown (15-30 frames = aggressive!)
        lda zfr
        eor RTCLOK3
        and #$0F              ; random 0-15
        clc
        adc #15               ; 15-30 frames (~0.25-0.5s)
        sta en_atk,x
        rts
?imp_far
        ; Spawn imp fireball (ranged attack)
        jsr spawn_eproj
        ; Restore enemy index (spawn_eproj clobbers X)
        ldx zzidx
        ; Fire sound
        lda #SFX_FIRSHT
        jsr play_sfx_unlock
        jmp ?set_cd
?hitscan
        ; Hitscan damage + sound (table-driven by enemy type)
        ldy en_type,x
        lda en_atk_dmg,y
        jsr player_take_damage
        lda en_atk_sfx,y
        jsr play_sfx_unlock
?set_cd ; Reset timer by enemy type: base + random 0-63
        lda zfr
        eor RTCLOK3
        eor en_x,x
        and #$0F
        ldy en_type,x
        clc
        adc en_cd_base,y
        sta en_atk,x
        rts

; Base cooldown per enemy type (indexed by EN_*)
en_cd_base
        dta 20              ; EN_ZOMBIE  = 0: 20-35 frames (~0.4-0.7s)
        dta 20              ; EN_IMP     = 1: 20-35 frames
        dta 20              ; EN_PINKY   = 2: 20-35 frames
        dta 20              ; EN_CACO    = 3: 20-35 frames
        dta 20              ; EN_SHOTGUN = 4: 20-35 frames
        dta 20              ; EN_BARON   = 5: 20-35 frames
        dta 20              ; EN_LOSTSOUL = 6: 20-35 frames

; Hitscan damage per enemy type
en_atk_dmg
        dta 3               ; EN_ZOMBIE: 3 dmg
        dta 0               ; EN_IMP: (melee/proj, not hitscan)
        dta 0               ; EN_PINKY: (melee only)
        dta 0               ; EN_CACO: (proj only)
        dta 15              ; EN_SHOTGUN: 15 dmg (3 pellets)
        dta 0               ; EN_BARON: (proj only)
        dta 0               ; EN_LOSTSOUL: (melee only)

; Hitscan attack SFX per enemy type
en_atk_sfx
        dta SFX_PISTOL      ; EN_ZOMBIE: pistol sound
        dta SFX_FIRSHT      ; EN_IMP: (unused for hitscan)
        dta SFX_SGTATK      ; EN_PINKY: (unused for hitscan)
        dta SFX_FIRSHT      ; EN_CACO: (unused for hitscan)
        dta SFX_SHOTGUN     ; EN_SHOTGUN: shotgun sound
        dta SFX_FIRSHT      ; EN_BARON: (unused for hitscan)
        dta SFX_SGTATK      ; EN_LOSTSOUL: (unused for hitscan)
.endp
