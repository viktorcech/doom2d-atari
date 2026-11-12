;==============================================
; DOOM2D - Enemies (arrays, init, update, render)
; enemies.asm
;==============================================

; ============================================
; ENEMY ARRAYS (indexed by X = 0..MAX_ENEMIES-1), all in LVL_BUF: the level
; file's buffer is free once a level is in (load_level and trig_load use it
; before init_enemies; the save slot buffer is VRAM, savegame.asm)
; ============================================
en_x    = LVL_BUF              ; X position (low byte)
enxhi   = en_x+MAX_ENEMIES     ; X position (high byte)
en_y    = enxhi+MAX_ENEMIES    ; Y position (low byte)
en_y_hi = en_y+MAX_ENEMIES     ; Y position (high byte, 16-bit for tall maps)
en_dir  = en_y_hi+MAX_ENEMIES  ; direction 0=right, 1=left
en_type = en_dir+MAX_ENEMIES   ; 0=zombie, 1=imp, 2=pinky, 3=caco ...
en_act  = en_type+MAX_ENEMIES  ; 0 none, 1 alive, 2 dying, 3 corpse
en_hp   = en_act+MAX_ENEMIES   ; hit points
en_atk  = en_hp+MAX_ENEMIES    ; 10/11 = attacking (shoot sprite), 0 = not
envely  = en_atk+MAX_ENEMIES   ; vertical velocity whole part (8.8 with en_vyf)
en_gib  = envely+MAX_ENEMIES   ; 1=gibbed (rocket kill), 0=normal death
envelx  = en_gib+MAX_ENEMIES   ; knockback (signed px/frame, decays per AI tick)
en_anim = envelx+MAX_ENEMIES   ; ANIM_* shown (mon_anims.asm ma_*)
en_afr  = en_anim+MAX_ENEMIES  ; its frame
en_acnt = en_afr+MAX_ENEMIES   ; ticks shown so far (TAnimation.mCounter)
EN_AI_RAM = en_acnt+MAX_ENEMIES ; the AI state (enemies_ai.asm)

; en_act values: 0=inactive, 1=alive, 2=dying, 3=corpse (the AI state: en_state)

; en_hp_tab is in sprite_defs.asm

; ============================================
; START_ENEMY_DEATH - common kill setup
; Input: X = enemy index
; Sets dying state (en_animate picks DIE), no gib, no knockback, falling
; ============================================
.proc start_enemy_death
        lda #2
        sta en_act,x
        lda #0
        sta en_gib,x
        sta envelx,x
        lda #1                  ; falls until move_corpse lands it (one frame
        sta envely,x            ; when it died standing on a floor)
        inc stat_kills
        ; Drop pickup on zombie/shotgun death
        lda en_type,x
        beq ?drop_ammo          ; EN_ZOMBIE (0) → ammo
        cmp #4                  ; EN_SHOTGUN
        bne ?no_drop
        lda #PK_SHOTGUN
        dta $2C                 ; bit $xxA9, xx = PK_AMMO (RAM, no I/O): skips lda #PK_AMMO
?drop_ammo
        lda #PK_AMMO
        ert PK_AMMO>=$C0        ; keeps that bit read out of $D000-$D7FF
        pha                     ; save pickup type
        ldy #0                  ; (X is never written below: no save/restore)
?find   lda pk_act,y
        beq ?slot
        iny
        cpy #MAX_PICKUPS
        bcc ?find
        pla                     ; discard type (no free slot)
        rts
?slot   lda #1
        sta pk_act,y
        pla
        sta pk_type,y
        lda en_x,x
        sta pk_x,y
        lda enxhi,x
        sta pk_xhi,y
        lda en_y,x
        sta pk_y,y
        lda en_y_hi,x
        sta pk_y_hi,y
        jsr pk_set_tile         ; keeps X, Y
        cpy pk_end
        bcc ?no_drop            ; slot inside the active range
        iny
        sty pk_end              ; (Y dies here)
?no_drop
        rts
.endp

; ============================================
; init_enemies is in the overlay segment (end of main.asm)

; ============================================
; UPDATE ALL ENEMIES
; ============================================
; ============================================
; MOVE_CORPSE - one knockback step for a corpse (X = index, preserved).
; Corpses and gibs shoved by a blast stop at walls and land on the floor.
; ============================================
.proc move_corpse
        ; Move the corpse whenever it has velocity - not just when gibbed.
        ; DOOM thrusts every victim of a blast, so a barrel now throws normal
        ; corpses too (start_enemy_death clears both, so plain deaths still
        ; stay put).
        lda envelx,x
        ora envely,x
        bne ?move        ; no knockback, skip movement
        rts
?move
        ; Horizontal knockback (16-bit, signed velocity)
        lda en_x,x
        sta ?kbsav_lo+1     ; SMC: old X parked in the back-out's lda # operands
        clc
        adc envelx,x
        sta en_x,x
        lda enxhi,x         ; A = hi stays for the add (no reload)
        sta ?kbsav_hi+1
        ldy envelx,x        ; N = sign; Y = envelx kept to the wall test
        bmi ?kb_neg
        adc #0              ; positive: add carry
        dta $2C             ; bit $FF69 (ROM/RAM, no I/O): skips adc #$FF
?kb_neg adc #$FF            ; negative: sign extend ($FF + carry)
        sta enxhi,x
?kb_wall
        ; A shoved corpse must not slide into a wall
        tya                 ; = envelx,x (Y untouched since ldy)
        beq ?kb_vy
        lda en_x,x
        clc
        adc #8              ; body centre
        sta gt_px
        lda enxhi,x
        adc #0
        sta gt_px_hi
        lda en_y,x
        sec
        sbc #8
        sta gt_py
        lda en_y_hi,x
        sbc #0
        sta gt_py_hi
        jsr check_solid16   ; preserves X
        beq ?kb_vy
?kbsav_lo
        lda #0              ; hit a wall: back out and stop sliding (patched)
        sta en_x,x
?kbsav_hi
        lda #0              ; (patched)
        sta enxhi,x
        lda #0
        sta envelx,x
?kb_vy
        ; Vertical knockback (gravity applied), 16-bit Y
        ; Y = envely: lo += vy, hi += carry (inc) + sign extension $FF (dec)
        ldy envely,x
        tya
        clc
        adc en_y,x
        sta en_y,x
        bcc ?kb_nc
        inc en_y_hi,x
?kb_nc  tya
        bmi ?kb_vyneg       ; signed velocity: sign-extend into hi
        ; Add gravity to knockback (signed: negative = going up)
        cpy #EN_MAXFALL
        bcs ?kb_floor       ; positive >= EN_MAXFALL → capped
        bcc ?do_kb_grav     ; (always)
?kb_vyneg
        dec en_y_hi,x       ; negative velocity → always add gravity
?do_kb_grav
        inc envely,x
?kb_floor
        ; land instead of sinking through the floor
        lda en_x,x
        clc
        adc #8
        sta gt_px
        lda enxhi,x
        adc #0
        sta gt_px_hi
        lda en_y,x
        sta gt_py
        lda en_y_hi,x
        sta gt_py_hi
        jsr check_solid_or_platform16   ; preserves X
        beq ?ret                     ; still airborne, keep falling
        lda en_y,x                      ; snap to the tile top and settle
        and #$100-TH
        sta en_y,x
        lda #0
        sta envely,x
        sta envelx,x                    ; no sliding on the floor
?ret    rts
.endp

; UPDATE_ENEMIES - every frame: physics (en_move); on AI ticks also the
; state machine (en_think), as Doom 2D Forever (enemies_ai.asm).
.proc update_enemies
        jsr en_ai_frame
        lda #<?nx               ; a sleeper: nothing off its AI ticks (SMC,
        ldx #>?nx               ; once a step)
        bit ai_now
        bpl ?p
        lda #<?sl
        ldx #>?sl
?p      sta ?sj+1
        stx ?sj+2
        ldx #0                  ; slot 0 is tested before the bound
?lp     lda en_act,x
        beq ?nx
        cmp #1
        beq ?alive
        jsr move_corpse         ; dying / corpse: blast knockback (preserves X)
        lda en_act,x
        cmp #2
        bne ?nx                 ; a corpse shows its last frame
        beq ?an                 ; (always) dying: en_animate in the shared tail
?alive  lda en_state,x          ; a sleeper does not move (TMonster SLEEP)
        bne ?mv
?sj     jmp ?nx                 ; (patched: ?sl on AI steps; off them nothing
                                ;  changes a sleeper, en_animate keeps SLEEP)
?mv     stx zzidx
        jsr en_move
        bit ai_now
        bmi ?tk
        jsr en_animate.alive    ; off AI ticks: en_move kills no one, en_act = 1
        jmp ?nx
?sl     stx zzidx
?tk     jsr en_think
        ldx zzidx
?an     jsr en_animate          ; (en_think may have changed en_act)
?nx     inx
        cpx num_en              ; only slots 0..num_en-1 can ever be active
        bcc ?lp
        rts
.endp


