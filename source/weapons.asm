;==============================================
; DOOM2D - Weapon system
; weapons.asm
;
; 8 weapons like DOOM 1 (1993)
; Keyboard 1-7 to switch
;==============================================

; Weapon property tables (indexed by weapon 0-6)
; Key 1 = fist (upgrades to chainsaw when picked up)
; Damage per shot (g_weapons.pas: g_Weapon_gun 3 a bullet, the shotgun's 10
; pellets as one shot, punch 3, rocket hit 10 + its blast, plasma 5, BFG 100)
weap_dmg
        dta 3                   ; WP_FIST
        dta 3                   ; WP_PISTOL
        dta 30                  ; WP_SHOTGUN
        dta 3                   ; WP_CHAINGUN
        dta 10                  ; WP_ROCKET (+splash)
        dta 5                   ; WP_PLASMA
        dta 100                 ; WP_BFG
        dta 3                   ; WP_SAW (g_Weapon_chainsaw: 3 in single player)

; Frames between shots: WEAPON_RELOAD (g_player.pas, 36 Hz ticks) x 50/36
weap_cooldown
        dta 7                   ; WP_FIST (5 ticks)
        dta 8                   ; WP_PISTOL (6)
        dta 25                  ; WP_SHOTGUN (18)
        dta 3                   ; WP_CHAINGUN (2)
        dta 17                  ; WP_ROCKET (12)
        dta 3                   ; WP_PLASMA (2)
        dta 19                  ; WP_BFG (14)
        dta 3                   ; WP_SAW (2)

; Ammo type: 0=bullets, 1=shells, 2=rockets, 3=cells, $FF=melee
weap_ammotype
        dta AMMO_NONE           ; WP_FIST
        dta 0                   ; WP_PISTOL   (bullets)
        dta 1                   ; WP_SHOTGUN  (shells)
        dta 0                   ; WP_CHAINGUN (bullets)
        dta 2                   ; WP_ROCKET   (rockets)
        dta 3                   ; WP_PLASMA   (cells)
        dta 3                   ; WP_BFG      (cells)
        dta AMMO_NONE           ; WP_SAW

weap_ammocost
        dta 0                   ; WP_FIST
        dta 1                   ; WP_PISTOL
        dta 1                   ; WP_SHOTGUN
        dta 1                   ; WP_CHAINGUN
        dta 1                   ; WP_ROCKET
        dta 1                   ; WP_PLASMA
        dta 40                  ; WP_BFG (DOOM: 40 cells/shot)
        dta 0                   ; WP_SAW

; Melee range (0 = projectile weapon)
weap_range
        dta 16                  ; WP_FIST
        dta 0                   ; WP_PISTOL
        dta 0                   ; WP_SHOTGUN
        dta 0                   ; WP_CHAINGUN
        dta 0                   ; WP_ROCKET
        dta 0                   ; WP_PLASMA
        dta 0                   ; WP_BFG
        dta 16                  ; WP_SAW (its 32 px hit rect at half scale)

; Weapon -> its ammo counter (AM_*; $FF = melee, no ammo)
weap_ammo_ix
        dta $FF                 ; WP_FIST
        dta AM_BUL              ; WP_PISTOL
        dta AM_SHL              ; WP_SHOTGUN
        dta AM_BUL              ; WP_CHAINGUN
        dta AM_RKT              ; WP_ROCKET
        dta AM_CEL              ; WP_PLASMA
        dta AM_CEL              ; WP_BFG
        dta $FF                 ; WP_SAW

; The ammo counters (16-bit, D2DF FAmmo): the lo bytes in zero page, the hi
; bytes and the limits (D2DF AmmoLimits) here; am_hi..pl_caph are one run
; for the save slot (AM_BYTES)
AM_BUL  = 0
AM_SHL  = 1
AM_RKT  = 2
AM_CEL  = 3
am_zp   dta zpammo, zpshells, zprockets, zpcells
am_hi   dta 0, 0, 0, 0
pl_capl dta <200, <50, <50, <300
pl_caph dta >200, >50, >50, >300
AM_BYTES = *-am_hi
am_cap0 dta <200, <50, <50, <300, >200, >50, >50, >300  ; no backpack
am_cap1 dta <400, <100, <100, <600, >400, >100, >100, >600 ; the backpack
        ert pl_caph<>pl_capl+4
gca_lo  dta 0                   ; get_cur_ammo: the count
gca_hi  dta 0

; Weapon -> projectile sprite (base frame, animates +1)
weap_proj_spr
        dta 0                   ; WP_FIST (melee, unused)
        dta SPR_PROJ1           ; WP_PISTOL (hitscan)
        dta SPR_PROJ1           ; WP_SHOTGUN
        dta SPR_PROJ1           ; WP_CHAINGUN
        dta SPR_ROCKET_PROJ     ; WP_ROCKET
        dta SPR_PLASMA_PROJ1    ; WP_PLASMA
        dta SPR_BFG_PROJ1       ; WP_BFG
        dta 0                   ; WP_SAW (melee, unused)

; Weapon -> HUD icon (the pickup's texture; $FF = none)
weap_hud_spr
        dta $FF                 ; WP_FIST
        dta SPR_PISTOLPK        ; WP_PISTOL
        dta SPR_SHOTGUNPK       ; WP_SHOTGUN
        dta SPR_CHAINGUNPK      ; WP_CHAINGUN
        dta SPR_ROCKETPK        ; WP_ROCKET
        dta SPR_PLASMAGUNPK     ; WP_PLASMA
        dta SPR_BFGPK           ; WP_BFG
        dta SPR_SAWPK           ; WP_SAW

; Weapon -> sound effect. Every weapon has one: player_update plays it
; with no "$FF = none" test (the guards below keep it that way).
weap_sfx
        dta SFX_PUNCH           ; WP_FIST
        dta SFX_PISTOL          ; WP_PISTOL
        dta SFX_SHOTGUN         ; WP_SHOTGUN
        dta SFX_PISTOL          ; WP_CHAINGUN (same as pistol)
        dta SFX_ROCKET          ; WP_ROCKET
        dta SFX_PLASMA          ; WP_PLASMA
        dta SFX_BFG             ; WP_BFG
        dta SFX_SAWFUL          ; WP_SAW
        ert SFX_PUNCH=$FF
        ert SFX_PISTOL=$FF
        ert SFX_SHOTGUN=$FF
        ert SFX_ROCKET=$FF
        ert SFX_PLASMA=$FF
        ert SFX_BFG=$FF

; Keyboard scancode -> weapon mapping
; Atari scancodes: 1=$1F, 2=$1E, 3=$1A, 4=$18, 5=$1D, 6=$1B, 7=$33
key_to_weap_sc
        dta $1F, $1E, $1A, $18, $1D, $1B, $33   ; index = weapon id

; ============================================
; CHECK WEAPON SWITCH (called from read_input)
; Uses OS shadow CH ($02FC), cleared to $FF after read
; ============================================
.proc check_weapon_switch
        lda CH
        cmp #$FF
        beq ?done               ; no key pressed
        ldx #$FF
        stx CH                  ; acknowledge key (clear for next press); A = scancode
        ; SPACE ($21) = USE key (TPlayer.Use: PLAYERPRESS triggers)
        cmp #$21
        jeq trig_use            ; tail call (it reads no A/X on entry)
        ; Check against weapon keys 1-7
        ldx #6
?lp     cmp key_to_weap_sc,x
        beq ?found
        dex
        bpl ?lp
?done   rts
?found  ; X = key index = weapon id (the old id table was the identity)
        txa                     ; key 1: the saw if owned and not selected
        bne ?wk                 ; (D2DF: knuckles and saw share it), else
        bit zpweap              ; the fist
        bpl ?wk                 ; N = bit 7: the saw
        lda zpwcur
        cmp #WP_SAW
        beq ?wk                 ; X = 0: back to the fist
        lda #WP_SAW
        sta zpwcur
        rts
?wk     lda zpweap
        and weap_bitmask,x
        beq ?done               ; don't own it
        stx zpwcur
        rts
.endp

; ============================================
; MELEE ATTACK - check proximity to enemies
; ============================================
.proc melee_attack
        ldx zpwcur
        lda weap_dmg,x
        sta hitscan_fire.hs_dmg ; hs_damage_enemy's damage (hitscan sets its own)
        lda weap_range,x
        sta ml_range+1          ; SMC: range as the cmp # operand
        ldx #$FF                ; the inx makes it slot 0 (num_en = 0: no slot
?nx     inx                     ; is active, so skipping slot 0 changes nothing)
        cpx num_en              ; only slots 0..num_en-1 can ever be active
        bcs ?done
        lda en_act,x
        cmp #1
        bne ?nx
        ; Check X distance: 16-bit |zpx - en_x|.
        ; (Was an 8-bit test guarded by "enxhi == zpx_hi", so melee simply
        ;  did not reach across the x=256 page line - same bug as the barrel
        ;  blast and the pickup radius.)
        lda zpx
        sec
        sbc en_x,x
        sta abs16.ab_lo
        lda zpx_hi
        sbc enxhi,x
        jsr abs16               ; clobbers Y, preserves X
        bcc ?nx
ml_range cmp #0                 ; operand patched above
        bcs ?nx
        ; Check Y distance (16-bit |zpy - en_y| < 20)
        lda zpy
        sec
        sbc en_y,x
        sta abs16.ab_lo
        lda zpy_hi
        sbc en_y_hi,x
        jsr abs16
        bcc ?nx
        cmp #20                 ; vertical range
        bcs ?nx
        ; Hit! Same damage/pain/face/kill block as the hitscan (hs_dmg set
        ; above); it returns with the A/flags the old inline copy had here
        jmp hs_damage_enemy     ; tail call
?done   rts
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
        dta $80                 ; bit7 = chainsaw

; ============================================
; GET CURRENT AMMO COUNT
; Returns: A = current ammo for active weapon
;          (99 for melee = always can fire)
; ============================================
; Out: X = zpwcur, gca_lo/gca_hi = the count, Z = none left; Y untouched.
.proc get_cur_ammo
        ldx zpwcur
        lda weap_ammo_ix,x
        bmi ?melee              ; $FF: melee weapon
        tax
        lda am_hi,x
        sta gca_hi
        lda am_zp,x
        sta ?rd+1               ; SMC: zp address of the lo byte
        ldx zpwcur
?rd     lda zpammo              ; operand patched above
        sta gca_lo
        ora gca_hi              ; Z: 16-bit zero
        rts
?melee  lda #0
        sta gca_hi
        lda #99
        sta gca_lo              ; Z=0
        rts
.endp

; ============================================
; DEDUCT AMMO for current weapon
; ============================================
; Out: X = zpwcur at entry (callers index with it). A/Y/flags: no caller
; reads them (both go on to lda weap_sfx,x / jsr spawn_proj; zt2 no longer
; written - every zt2 reader stores it first).
.proc deduct_ammo
        ldx zpwcur
        ldy weap_ammo_ix,x
        bmi ?done               ; melee = no ammo
        lda am_zp,y
        sta ?ld+1               ; SMC: zp address of the lo byte
        sta ?st+1
        sta ?or+1
?ld     lda zpammo              ; operand patched above
        sec
        sbc weap_ammocost,x
?st     sta zpammo              ; operand patched above
        lda am_hi,y             ; the borrow into the hi byte
        sbc #0
        sta am_hi,y
?or     ora zpammo              ; (patched) Z: 16-bit zero
        bne ?done
        ; Ammo ran out — find best weapon with ammo (Y = candidate)
        ; Priority: chaingun, shotgun, pistol, fist
        ldy #WP_CHAINGUN
        lda zpweap
        and #$08                ; chaingun
        beq ?no_cg
        lda zpammo
        ora am_hi+AM_BUL
        bne ?sw
?no_cg  ldy #WP_SHOTGUN
        lda zpweap
        and #$04                ; shotgun
        beq ?no_sg
        lda zpshells
        ora am_hi+AM_SHL
        bne ?sw
?no_sg  ldy #WP_PISTOL
        lda zpammo
        ora am_hi+AM_BUL
        bne ?sw                 ; pistol always owned, check bullets
        ldy #WP_FIST            ; fallback to fist
?sw     sty zpwcur
?done   rts
.endp

