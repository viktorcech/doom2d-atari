;==============================================
; DOOM2D - Pickups (health, ammo, armor, keys, weapons, powerups)
; pickups.asm
;==============================================

; Pickup arrays
pk_act  .ds MAX_PICKUPS         ; active flag
pk_x    .ds MAX_PICKUPS         ; X position (lo)
pk_xhi  .ds MAX_PICKUPS         ; X position (hi)
pk_y    .ds MAX_PICKUPS         ; Y position
pk_type .ds MAX_PICKUPS         ; type (PK_xxx constants)

; pk_spr_tab is in sprite_defs.asm (auto-generated)

; HP/ammo amounts per pickup type
pk_amount
        dta 10                  ; PK_HEALTH:     +10 HP
        dta 5                   ; PK_AMMO:       +5 ammo (zombie drop)
        dta 25                  ; PK_MEDIKIT:     +25 HP
        dta 100                 ; PK_GREENARMOR:  100 armor (DOOM: green=100)
        dta 200                 ; PK_BLUEARMOR:   200 armor (DOOM: blue=200)
        dta 100                 ; PK_SOULSPHERE:  +100 HP (over max)
        dta 1                   ; PK_KEYRED:      key bit 0
        dta 2                   ; PK_KEYBLUE:     key bit 1
        dta 4                   ; PK_KEYYELLOW:   key bit 2
        dta $04                 ; PK_SHOTGUN:     weapon bit2 (WP_SHOTGUN)
        dta 4                   ; PK_SHELLS:      +4 shells
        dta $02                 ; PK_PISTOL:      weapon bit1 (WP_PISTOL)
        dta $08                 ; PK_CHAINGUN:    weapon bit3 (WP_CHAINGUN)
        dta $10                 ; PK_ROCKETL:     weapon bit4 (WP_ROCKET)
        dta 5                   ; PK_ROCKETBOX:   +5 rockets
        dta $20                 ; PK_PLASMAGUN:   weapon bit5 (WP_PLASMA)
        dta 20                  ; PK_CELLS:       +20 cells
        dta $40                 ; PK_BFG:         weapon bit6 (WP_BFG)
        dta 1                   ; PK_ROCKET1:     +1 rocket
        dta 1                   ; PK_HEALTHBONUS: +1 HP (max 200)
        dta 1                   ; PK_ARMORBONUS:  +1 armor (max 200)

; Effect class per type: 0=health, 1=ammo, 2=armor, 3=key, 4=soul, 5=weapon
pk_class
        dta 0                   ; PK_HEALTH
        dta 1                   ; PK_AMMO
        dta 0                   ; PK_MEDIKIT
        dta 2                   ; PK_GREENARMOR
        dta 2                   ; PK_BLUEARMOR
        dta 4                   ; PK_SOULSPHERE
        dta 3                   ; PK_KEYRED
        dta 3                   ; PK_KEYBLUE
        dta 3                   ; PK_KEYYELLOW
        dta 5                   ; PK_SHOTGUN
        dta 1                   ; PK_SHELLS
        dta 5                   ; PK_PISTOL (weapon class)
        dta 5                   ; PK_CHAINGUN (weapon class)
        dta 5                   ; PK_ROCKETL (weapon class)
        dta 6                   ; PK_ROCKETBOX (rocket ammo class)
        dta 5                   ; PK_PLASMAGUN (weapon class)
        dta 7                   ; PK_CELLS (cells ammo class)
        dta 5                   ; PK_BFG (weapon class)
        dta 6                   ; PK_ROCKET1 (rocket ammo class)
        dta 4                   ; PK_HEALTHBONUS (soul class - goes over 100)
        dta 8                   ; PK_ARMORBONUS (armor bonus class)

; init_pickups is in the overlay segment (end of main.asm)

; ============================================
; UPDATE PICKUPS (collision with player)
; ============================================
.proc update_pickups
        ; Skip all pickup checks if player is dead
        lda zphp
        bne ?go
?ret    rts
?go     ldx #0
?lp     lda pk_act,x
        bne ?chk
        jmp ?nx
?chk    ; Check X hi byte match
        lda pk_xhi,x
        cmp zpx_hi
        bne ?nxj
        ; Check X distance: |pk_x - zpx| < 12
        lda pk_x,x
        sec
        sbc zpx
        bpl ?ax
        eor #$FF
        clc
        adc #1
?ax     cmp #12
        bcc ?xok
?nxj    jmp ?nx
?xok    ; Check Y distance: |pk_y - zpy| < 16
        lda pk_y,x
        sec
        sbc zpy
        bpl ?ay
        eor #$FF
        clc
        adc #1
?ay     cmp #16
        bcc ?hit
        jmp ?nx
?hit    ; Pickup collected! Route by class
        stx pk_tmp
        ldy pk_type,x
        lda pk_class,y
        cmp #1
        beq ?ammo
        cmp #2
        beq ?armor
        cmp #3
        beq ?key
        cmp #4
        beq ?soul
        cmp #5
        bne ?chk6
        jmp ?weapon
?chk6   cmp #6
        bne ?chk7
        jmp ?rockets
?chk7   cmp #7
        bne ?chk8
        jmp ?cells
?chk8   cmp #8
        bne ?chk_hp
        jmp ?armbonus
?chk_hp
        ; class 0: health
        lda zphp
        clc
        adc pk_amount,y
        cmp #100
        bcc ?hp_ok
        lda #100
?hp_ok  sta zphp
        jmp ?sfx_ammo
?ammo   ; Check if shells (PK_SHELLS) or bullets (PK_AMMO)
        lda pk_type,x
        cmp #PK_SHELLS
        beq ?ashell
        ; Bullets
        lda zpammo
        clc
        adc pk_amount,y
        cmp #200
        bcc ?am_ok
        lda #200
?am_ok  sta zpammo
        jmp ?sfx_ammo
?ashell lda zpshells
        clc
        adc pk_amount,y
        cmp #50
        bcc ?sh_ok
        lda #50
?sh_ok  sta zpshells
        jmp ?sfx_ammo
?armbonus ; +1 armor (max 200, always picks up)
        lda zparmor
        cmp #200
        bcs ?ab_skip
        inc zparmor
        jmp ?sfx_ammo
?ab_skip jmp ?nx
?armor  ; Set armor to value if current is less (DOOM behavior)
        lda pk_amount,y
        cmp zparmor
        bcc ?ar_skip            ; already have more armor
        beq ?ar_skip
        sta zparmor
        jmp ?sfx_ammo
?ar_skip jmp ?nx                ; don't pick up if already have enough
?key    lda pk_amount,y
        ora zpkeys
        sta zpkeys
        jmp ?sfx_ammo
?soul   lda zphp
        clc
        adc pk_amount,y
        cmp #200
        bcc ?so_ok
        lda #200
?so_ok  sta zphp
        jmp ?sfx_ammo
?rockets lda zprockets
        clc
        adc pk_amount,y
        cmp #50
        bcc ?rk_ok
        lda #50
?rk_ok  sta zprockets
        jmp ?sfx_ammo
?cells  lda zpcells
        clc
        adc pk_amount,y
        bcs ?cl_max
        cmp #200
        bcc ?cl_ok
?cl_max lda #200
?cl_ok  sta zpcells
        jmp ?sfx_ammo
?weapon lda pk_amount,y         ; weapon bitmask
        sta wp_mask             ; save for switch check
        lda zpweap
        and wp_mask
        sta wp_had              ; non-zero = already had this weapon
        lda zpweap
        ora wp_mask             ; add to owned weapons
        sta zpweap
        ; Auto-switch ONLY if weapon is NEW
        lda pk_type,x
        cmp #PK_PISTOL
        bne ?wshotg
        lda wp_had
        bne ?wpok2
        lda #WP_PISTOL
        sta zpwcur
?wpok2  lda zpammo
        clc
        adc #20
        cmp #200
        bcc ?wpok
        lda #200
?wpok   sta zpammo
        lda wp_had
        bne ?wp_ammo1
        jmp ?sfx_wpn
?wp_ammo1 jmp ?sfx_ammo
?wshotg cmp #PK_SHOTGUN
        bne ?wchain
        lda wp_had
        bne ?wsok2
        lda #WP_SHOTGUN
        sta zpwcur
?wsok2  lda zpshells
        clc
        adc #8
        cmp #50
        bcc ?wsok
        lda #50
?wsok   sta zpshells
        ldx #SFX_SGCOCK
        jsr snd_play
        jmp ?collect
?wchain cmp #PK_CHAINGUN
        bne ?wrocket
        lda wp_had
        bne ?wcok2
        lda #WP_CHAINGUN
        sta zpwcur
?wcok2  lda zpammo
        clc
        adc #20
        cmp #200
        bcc ?wcok
        lda #200
?wcok   sta zpammo
        lda wp_had
        bne ?sfx_ammo
        jmp ?sfx_wpn
?wrocket cmp #PK_ROCKETL
        bne ?wplasma
        lda wp_had
        bne ?wrok2
        lda #WP_ROCKET
        sta zpwcur
?wrok2  lda zprockets
        clc
        adc #2
        cmp #50
        bcc ?wrok
        lda #50
?wrok   sta zprockets
        lda wp_had
        bne ?sfx_ammo
        jmp ?sfx_wpn
?wplasma cmp #PK_PLASMAGUN
        bne ?wbfg
        lda wp_had
        bne ?wplok2
        lda #WP_PLASMA
        sta zpwcur
?wplok2 lda zpcells
        clc
        adc #40
        bcs ?wpl_max
        cmp #200
        bcc ?wplok
?wpl_max lda #200
?wplok  sta zpcells
        lda wp_had
        bne ?jsfx_ammo
        jmp ?sfx_wpn
?wbfg   cmp #PK_BFG
        bne ?collect
        lda wp_had
        bne ?wbok2
        lda #WP_BFG
        sta zpwcur
?wbok2  lda zpcells
        clc
        adc #40
        bcs ?wb_max
        cmp #200
        bcc ?wbok
?wb_max lda #200
?wbok   sta zpcells
        lda wp_had
?jsfx_ammo
        bne ?sfx_ammo
?sfx_wpn
        ldx #SFX_WPNUP
        jsr snd_play
        jmp ?collect
?sfx_ammo
        ldx #SFX_ITEMUP
        jsr snd_play
?collect
        ; Mark dirty tiles under pickup so background restores
        ldx pk_tmp
        lda pk_x,x
        sta zdx
        lda pk_xhi,x
        sta zdxh
        lda pk_y,x
        sec
        sbc #16
        sta zdy
        lda #16
        sta md_w
        sta md_h
        jsr mark_dirty_sprite
        ldx pk_tmp
        lda #0
        sta pk_act,x
        ; Check if this pickup triggers a switch action
        jsr pickup_check_trigger
?nx     inx
        cpx #MAX_PICKUPS
        bne ?lp2
        rts
?lp2    jmp ?lp
pk_tmp  dta 0
wp_mask dta 0
wp_had  dta 0
.endp

; ============================================
; PICKUP TRIGGER - check if collected pickup has a linked action
; Converts pickup pixel pos to tile col/row, looks up in sw_col/sw_row
; ============================================
.proc pickup_check_trigger
        ldx update_pickups.pk_tmp
        ; tile col = pk_xhi * 16 + pk_x / 16
        lda pk_xhi,x
        asl
        asl
        asl
        asl                     ; xhi * 16
        sta pct_col
        lda pk_x,x
        lsr
        lsr
        lsr
        lsr                     ; x / 16
        ora pct_col
        sta sw_found_col
        ; tile row = (pk_y - 16) / 16  (undo the +16 snap from init)
        lda pk_y,x
        sec
        sbc #16
        lsr
        lsr
        lsr
        lsr
        sta sw_found_row
        ; Look up in switch table and execute
        jsr switch_do_target
        rts
pct_col dta 0
.endp

; ============================================
; RENDER PICKUPS - NO DIRTY (for per-frame static redraw)
; Same as render_pickups but skips mark_dirty_sprite
; ============================================
.proc render_pickups_nodirty
        lda dirty_any
        beq ?skip               ; no dirty tiles = no statics to redraw
        ldx #0
?lp     lda pk_act,x
        beq ?nx
        ; Check if pickup overlaps dirty bbox
        stx rn_idx
        ; Tile col = (pk_xhi:pk_x) >> 4
        lda pk_xhi,x
        asl
        asl
        asl
        asl
        sta rn_tc
        lda pk_x,x
        lsr
        lsr
        lsr
        lsr
        ora rn_tc
        cmp dirty_min_col
        bcc ?nx2                ; left of dirty area
        cmp dirty_max_col
        beq ?col_ok
        bcs ?nx2                ; right of dirty area
?col_ok ; Tile row = (pk_y - 16) >> 4
        lda pk_y,x
        sec
        sbc #16
        bcc ?nx2
        lsr
        lsr
        lsr
        lsr
        cmp dirty_min_row
        bcc ?nx2                ; above dirty area
        cmp dirty_max_row
        beq ?row_ok
        bcs ?nx2                ; below dirty area
?row_ok ; Inside dirty bbox - redraw
        ldx rn_idx
        lda pk_x,x
        sta zdx
        lda pk_xhi,x
        sta zdxh
        lda pk_y,x
        sec
        sbc #16
        sta zdy
        ldx rn_idx
        lda pk_type,x
        tax
        lda pk_spr_tab,x
        jsr blit_sprite
?nx2    ldx rn_idx
?nx     inx
        cpx #MAX_PICKUPS
        bne ?lp
?skip   rts
rn_idx  dta 0
rn_tc   dta 0
.endp
