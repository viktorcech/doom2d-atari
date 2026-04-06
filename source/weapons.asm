;==============================================
; DOOM2D - Weapon system
; weapons.asm
;
; 8 weapons like DOOM 1 (1993)
; Keyboard 1-7 to switch
;==============================================

CH              = $02FC         ; OS keyboard shadow register ($FF = no key)

; Weapon property tables (indexed by weapon 0-6)
; Key 1 = fist (upgrades to chainsaw when picked up)
weap_dmg
        dta 2                   ; WP_FIST (3 with chainsaw)
        dta 1                   ; WP_PISTOL
        dta 5                   ; WP_SHOTGUN (DOOM: 7x pistol)
        dta 1                   ; WP_CHAINGUN (fast fire)
        dta 10                  ; WP_ROCKET (+splash)
        dta 2                   ; WP_PLASMA (very fast)
        dta 20                  ; WP_BFG (one-shots baron)

weap_cooldown
        dta 12                  ; WP_FIST (6 with chainsaw)
        dta 15                  ; WP_PISTOL
        dta 30                  ; WP_SHOTGUN
        dta 4                   ; WP_CHAINGUN
        dta 35                  ; WP_ROCKET
        dta 3                   ; WP_PLASMA
        dta 60                  ; WP_BFG

; Ammo type: 0=bullets, 1=shells, 2=rockets, 3=cells, $FF=melee
weap_ammotype
        dta AMMO_NONE           ; WP_FIST
        dta 0                   ; WP_PISTOL   (bullets)
        dta 1                   ; WP_SHOTGUN  (shells)
        dta 0                   ; WP_CHAINGUN (bullets)
        dta 2                   ; WP_ROCKET   (rockets)
        dta 3                   ; WP_PLASMA   (cells)
        dta 3                   ; WP_BFG      (cells)

weap_ammocost
        dta 0                   ; WP_FIST
        dta 1                   ; WP_PISTOL
        dta 1                   ; WP_SHOTGUN
        dta 1                   ; WP_CHAINGUN
        dta 1                   ; WP_ROCKET
        dta 1                   ; WP_PLASMA
        dta 40                  ; WP_BFG (DOOM: 40 cells/shot)

; Melee range (0 = projectile weapon)
weap_range
        dta 16                  ; WP_FIST
        dta 0                   ; WP_PISTOL
        dta 0                   ; WP_SHOTGUN
        dta 0                   ; WP_CHAINGUN
        dta 0                   ; WP_ROCKET
        dta 0                   ; WP_PLASMA
        dta 0                   ; WP_BFG

; Ammo ZP address table (indexed by ammo type 0-3)
ammo_addr
        dta zpammo              ; 0 = bullets
        dta zpshells            ; 1 = shells
        dta zprockets           ; 2 = rockets
        dta zpcells             ; 3 = cells

; Weapon -> projectile sprite (base frame, animates +1)
weap_proj_spr
        dta 0                   ; WP_FIST (melee, unused)
        dta 42                  ; WP_PISTOL -> SPR_PROJ1
        dta 42                  ; WP_SHOTGUN -> SPR_PROJ1
        dta 42                  ; WP_CHAINGUN -> SPR_PROJ1
        dta 104                 ; WP_ROCKET -> SPR_ROCKET_PROJ
        dta SPR_PLASMA_PROJ1    ; WP_PLASMA
        dta SPR_BFG_PROJ1       ; WP_BFG

; Weapon -> pickup sprite index for HUD display
weap_hud_spr
        dta 0                   ; WP_FIST (no pickup sprite, use 0)
        dta 47                  ; WP_PISTOL -> SPR_AMMO_CLIP
        dta 54                  ; WP_SHOTGUN -> SPR_SHOTGUNPK
        dta 102                 ; WP_CHAINGUN -> SPR_CHAINGUNPK
        dta 103                 ; WP_ROCKET -> SPR_ROCKETPK
        dta SPR_PLASMAGUNPK     ; WP_PLASMA
        dta SPR_BFGPK           ; WP_BFG

; Weapon -> sound effect ($FF = no sound yet)
weap_sfx
        dta SFX_PUNCH           ; WP_FIST
        dta SFX_PISTOL          ; WP_PISTOL
        dta SFX_SHOTGUN         ; WP_SHOTGUN
        dta SFX_PISTOL          ; WP_CHAINGUN (same as pistol)
        dta SFX_ROCKET          ; WP_ROCKET
        dta SFX_PLASMA          ; WP_PLASMA
        dta SFX_BFG             ; WP_BFG

; Keyboard scancode -> weapon mapping
; Atari scancodes: 1=$1F, 2=$1E, 3=$1A, 4=$18, 5=$1D, 6=$1B, 7=$33
key_to_weap_sc
        dta $1F, $1E, $1A, $18, $1D, $1B, $33
key_to_weap_id
        dta 0, 1, 2, 3, 4, 5, 6

; ============================================
; CHECK WEAPON SWITCH (called from read_input)
; Uses OS shadow CH ($02FC), cleared to $FF after read
; ============================================
.proc check_weapon_switch
        lda CH
        cmp #$FF
        beq ?done               ; no key pressed
        ; SPACE ($21) = USE key (open doors)
        cmp #$21
        bne ?not_space
        lda #$FF
        sta CH
        jsr try_open_door
        rts
?not_space
        sta wk_key              ; save scancode
        lda #$FF
        sta CH                  ; acknowledge key (clear for next press)
        lda wk_key
        ; Check against weapon keys 1-7
        ldx #6
?lp     cmp key_to_weap_sc,x
        beq ?found
        dex
        bpl ?lp
?done   rts
?found  ; X = index, get weapon id
        lda key_to_weap_id,x
        tax
        ; Check if player owns this weapon (bit X in zpweap)
        lda zpweap
        and weap_bitmask,x
        beq ?done               ; don't own it
        stx zpwcur
        rts
wk_key  dta 0
.endp

; ============================================
; MELEE ATTACK - check proximity to enemies
; ============================================
.proc melee_attack
        ldx zpwcur
        lda weap_dmg,x
        sta ml_dmg
        lda weap_range,x
        sta ml_range
        ldx #0
?lp     lda en_act,x
        cmp #1
        bne ?nx
        ; Check same hi byte
        lda enxhi,x
        cmp zpx_hi
        bne ?nx
        ; Check X distance
        lda zpx
        sec
        sbc en_x,x
        bpl ?xa
        eor #$FF
        clc
        adc #1
?xa     cmp ml_range
        bcs ?nx
        ; Check Y distance
        lda zpy
        sec
        sbc en_y,x
        bpl ?ya
        eor #$FF
        clc
        adc #1
?ya     cmp #20                 ; vertical range
        bcs ?nx
        ; Hit! Apply melee damage
        lda en_hp,x
        sec
        sbc ml_dmg
        bcs ?hok
        lda #0
?hok    sta en_hp,x
        lda #8
        sta en_pain_tmr,x
        lda en_hp,x
        bne ?alive
        jsr start_enemy_death
        jsr play_enemy_death
?alive  ; Face enemy
        jsr alert_enemies_sound
        rts
?nx     inx
        cpx #MAX_ENEMIES
        beq ?done
        jmp ?lp
?done   rts
ml_dmg  dta 0
ml_range dta 0
.endp

; Bitmask table for weapon ownership
weap_bitmask
        dta $01                 ; bit0 = fist/chainsaw
        dta $02                 ; bit1 = pistol
        dta $04                 ; bit2 = shotgun
        dta $08                 ; bit3 = chaingun
        dta $10                 ; bit4 = rocket
        dta $20                 ; bit5 = plasma
        dta $40                 ; bit6 = BFG

; ============================================
; GET CURRENT AMMO COUNT
; Returns: A = current ammo for active weapon
;          (99 for melee = always can fire)
; ============================================
.proc get_cur_ammo
        ldx zpwcur
        lda weap_ammotype,x
        cmp #AMMO_NONE
        beq ?melee
        cmp #1
        beq ?shells
        cmp #2
        beq ?rockets
        cmp #3
        beq ?cells
        ; ammo type 0 = bullets
        lda zpammo
        rts
?shells lda zpshells
        rts
?rockets lda zprockets
        rts
?cells  lda zpcells
        rts
?melee  lda #99
        rts
.endp

; ============================================
; DEDUCT AMMO for current weapon
; ============================================
.proc deduct_ammo
        ldx zpwcur
        lda weap_ammotype,x
        cmp #AMMO_NONE
        beq ?done               ; melee = no ammo
        ldy weap_ammocost,x     ; cost to deduct
        cmp #1
        beq ?shells
        cmp #2
        beq ?rockets
        cmp #3
        beq ?cells
        ; ammo type 0 = bullets
        tya
        sta zt2
        lda zpammo
        sec
        sbc zt2
        sta zpammo
        beq ?auto_switch
        rts
?shells tya
        sta zt2
        lda zpshells
        sec
        sbc zt2
        sta zpshells
        beq ?auto_switch
        rts
?rockets tya
        sta zt2
        lda zprockets
        sec
        sbc zt2
        sta zprockets
        beq ?auto_switch
        rts
?cells  tya
        sta zt2
        lda zpcells
        sec
        sbc zt2
        sta zpcells
        beq ?auto_switch
        rts
?auto_switch
        ; Ammo ran out — find best weapon with ammo
        ; Priority: chaingun, shotgun, pistol, fist
        lda zpweap
        and #$08                ; chaingun
        beq ?no_cg
        lda zpammo
        bne ?sw_cg
?no_cg  lda zpweap
        and #$04                ; shotgun
        beq ?no_sg
        lda zpshells
        bne ?sw_sg
?no_sg  lda zpammo
        bne ?sw_pi              ; pistol always owned, check bullets
        lda #WP_FIST            ; fallback to fist
        sta zpwcur
        rts
?sw_cg  lda #WP_CHAINGUN
        sta zpwcur
        rts
?sw_sg  lda #WP_SHOTGUN
        sta zpwcur
        rts
?sw_pi  lda #WP_PISTOL
        sta zpwcur
?done   rts
.endp

