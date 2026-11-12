;==============================================
; DOOM2D - Pickups (health, ammo, armor, keys, weapons, powerups)
; pickups.asm
;==============================================

; Pickup arrays: in LVL_BUF after the enemies' (free once the level is
; loaded; init_pickups fills them after every load)
pk_act  = en_tick+MAX_ENEMIES   ; active flag
pk_x    = pk_act+MAX_PICKUPS    ; X position (lo)
pk_xhi  = pk_x+MAX_PICKUPS      ; X position (hi)
pk_y    = pk_xhi+MAX_PICKUPS    ; Y position (low byte)
pk_y_hi = pk_y+MAX_PICKUPS      ; Y position (high byte, 16-bit for tall maps)
pk_type = pk_y_hi+MAX_PICKUPS   ; type (PK_xxx constants)
pk_col  = pk_type+MAX_PICKUPS   ; tile column of pk_x (cheap rejects)
pk_row  = pk_col+MAX_PICKUPS    ; tile row of pk_y (moves with pk_y)
        ert pk_row+MAX_PICKUPS>MEMW


; PK_SET_TILE - pk_col/pk_row of slot Y from its 16-bit X/Y (spawn only,
; cold: shifts, no index register needed). Preserves X, Y.
.proc pk_set_tile
        lda pk_x,y
        lsr
        lsr
        lsr
        sta ?t+1
        lda pk_xhi,y
        asl
        asl
        asl
        asl
        asl
?t      ora #0                  ; (patched: lo/8)
        sta pk_col,y
        lda pk_y,y
        lsr
        lsr
        lsr
        sta ?u+1
        lda pk_y_hi,y
        asl
        asl
        asl
        asl
        asl
?u      ora #0                  ; (patched: lo/8)
        sta pk_row,y
        rts
.endp

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
        dta $80                 ; PK_SAW:         weapon bit7 (WP_SAW)
        dta 0                   ; PK_OXYGEN
        dta 0                   ; PK_BACKPACK

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
        dta 5                   ; PK_SAW (weapon class)
        dta 9                   ; PK_OXYGEN (air)
        dta 10                  ; PK_BACKPACK

; init_pickups is in the overlay segment (end of main.asm)

; ============================================
; UPDATE PICKUPS (collision with player)
; ============================================
.proc update_pickups
        lda pf_n                ; falling items (rare: a door opened under one)
        beq ?nf
        jsr pk_falls
?nf     ; Skip all pickup checks if player is dead
        lda zphp
        bne ?go
?ret    rts
?go     ; Cheap reject first: a pickup within 12 px / 16 px of the player has
        ; |pk_col - player col| <= 2 and |pk_row - player row| <= 2 (8 px
        ; cells), i.e. pk_col - (col-2) and pk_row - (row-2) in 0..4
        jsr get_player_tile_col ; the bounds negated, added with C=0:
        eor #$FF                ; 2 - col (C=1: ~col + 3)
        sec
        adc #2
        sta ?c+1
        lda #2*TH               ; row of zpy - 16 = player row - 2
        jsr get_player_row
        eor #$FF                ; -(row - 2) (C=1: ~A + 1)
        sec
        adc #0
        sta ?r+1
        ldx #0
        clc
        bcc ?lp                 ; (always) enter at the loop head
?nx     inx
        cpx pk_end
        bcs ?ret
?lp     lda pk_act,x            ; (slot 0 with pk_end = 0: inactive, exits above)
        beq ?nx                 ; C=0 here: clc above, or bcs ?ret not taken
        lda pk_col,x
?c      adc #0                  ; (patched: 2 - player col)
        cmp #5
        bcs ?nx
        lda pk_row,x            ; C=0 (bcs not taken)
?r      adc #0                  ; (patched: 2 - player row)
        cmp #5
        bcs ?nx
        ; Check X distance: 16-bit |pk_x - zpx| < 12.
        ; (Was an 8-bit test guarded by "pk_xhi == zpx_hi", which made every
        ;  pickup uncollectable across the x=256 page line - same bug the
        ;  barrel blast had.)
        lda pk_x,x
        sec
        sbc zpx
        sta abs16.ab_lo
        lda pk_xhi,x
        sbc zpx_hi
        jsr abs16               ; preserves X
        bcc ?nx                 ; further than 255 px
        cmp #12
        bcs ?nx
        ; Check Y distance: 16-bit |pk_y - zpy| < 16
        lda pk_y,x
        sec
        sbc zpy
        sta abs16.ab_lo
        lda pk_y_hi,x
        sbc zpy_hi
        jsr abs16
        bcc ?nx
        cmp #16
        bcs ?nx
        ; Pickup collected! Route by class 0..10 (rts dispatch; Y = pk_type
        ; and X = the slot in every handler). wp_had = 1 for non-weapons, so
        ; the shared ?wtail plays ITEMUP for them.
        stx pk_tmp
        lda #1
        sta wp_had
        ldy pk_type,x
        ldx pk_class,y
        lda ?jh,x
        pha
        lda ?jl,x
        pha
        ldx pk_tmp
        rts
?jl     dta <[?health-1], <[?ammo-1], <[?armor-1], <[?key-1], <[?soul-1], <[?weapon-1]
        dta <[?rockets-1], <[?cells-1], <[?armbonus-1], <[?oxygen-1], <[?backpack-1]
?jh     dta >[?health-1], >[?ammo-1], >[?armor-1], >[?key-1], >[?soul-1], >[?weapon-1]
        dta >[?rockets-1], >[?cells-1], >[?armbonus-1], >[?oxygen-1], >[?backpack-1]
        ; ?addc below: zp[X] = min(zp[X] + A, Y); ldy #cap (<> 0) -> bne
?health lda pk_amount,y
        ldx #zphp
        ldy #100
        bne ?addc
?ammo   ; Check if shells (PK_SHELLS) or bullets (PK_AMMO)
        lda pk_amount,y
        cpy #PK_SHELLS
        beq ?ashell
        ldy #AM_BUL             ; Bullets
        bpl ?amt                ; (always)
?ashell ldy #AM_SHL
?amt    jsr ?am                 ; D2DF: a full counter leaves the item
        bcs ?skip
        jmp ?sfx_ammo           ; = ?wtail with wp_had = 1
?soul   lda pk_amount,y
        ldx #zphp
        ldy #200
        bne ?addc
?rockets lda pk_amount,y
        ldy #AM_RKT
        bpl ?amt                ; (always)
?armor  ; Set armor to value if current is less (DOOM behavior)
        lda pk_amount,y
        cmp zparmor
        bcc ?skip               ; already have more armor
        beq ?skip
        sta zparmor
        bcs ?sfx_ammo           ; (always: C=1, the bcc not taken)
?armbonus ; +1 armor (max 200, always picks up)
        lda zparmor
        cmp #200
        bcs ?skip
        inc zparmor
        bcc ?sfx_ammo           ; (always: C=0, the bcs not taken)
?skip   ldx pk_tmp              ; don't pick up (X: the slot; ?am clobbers it)
        jmp ?nx
?oxygen lda pl_air+1            ; D2DF: only while air < AIR_MAX
        bmi ?ox
        cmp #>AIR_MAX
        bcc ?ox
        bne ?skip
        lda pl_air
        cmp #<AIR_MAX
        bcs ?skip
?ox     lda #<AIR_MAX
        sta pl_air
        lda #>AIR_MAX
        sta pl_air+1
        bne ?sfx_ammo           ; (always: >AIR_MAX <> 0)
?key    lda pk_amount,y         ; D2DF: only a key not owned yet
        and zpkeys
        bne ?skip
        lda pk_amount,y
        ora zpkeys
        sta zpkeys
        bne ?sfx_ammo           ; (always: key amounts are 1/2/4)
?cells  lda pk_amount,y
        ldy #AM_CEL
        bpl ?amt                ; (always)
?addc   sty ?cap+1              ; SMC: the cap (both compares)
        sty ?cp0+1
        sta ?ha+1               ; the amount
        lda 0,x                 ; D2DF PickItem: only below the cap (FHealth <
?cp0    cmp #0                  ; PLAYER_HP_SOFT / _LIMIT), else the item stays
        bcs ?skip
?ha     adc #0                  ; (patched; C=0: the bcs not taken) zp + amount,
        bcs ?full               ; at most the cap (past 255: the cap too)
?cap    cmp #0
        bcc ?ok
?full   tya
?ok     sta 0,x
?wtail  lda wp_had              ; new weapon: WPNUP, else ITEMUP
        bne ?sfx_ammo
        ldx #SFX_WPNUP
        dta $2C                 ; bit $01A2 (stack page, no I/O): skips ldx #SFX_ITEMUP
        ert SFX_ITEMUP>=$C0
?sfx_ammo
        ldx #SFX_ITEMUP
?sfx    jsr snd_play
        ldx pk_tmp
        lda #0
        sta pk_act,x
        beq ?skip               ; (always) -> ?nx
?weapon lda zpweap              ; weapon bitmask: pk_amount (no copy)
        tax                     ; X = owned before
        ora pk_amount,y         ; add to owned weapons
        sta zpweap
        txa
        and pk_amount,y
        sta wp_had              ; non-zero = already had this weapon
        ; Auto-switch ONLY if weapon is NEW (class 5 = these six types)
        bne ?wown
        lda ?wp_id-PK_SHOTGUN,y
        sta zpwcur
?wown   cpy #PK_SAW
        bne ?wam0
        lda wp_had              ; the saw: no ammo; D2DF: only if not owned
        bne ?skip2
        beq ?wtail              ; (always)
?wam0
        cpy #PK_SHOTGUN
        beq ?wshot
        cpy #PK_ROCKETL
        beq ?wrock
        cpy #PK_PISTOL
        beq ?wbul
        cpy #PK_CHAINGUN
        bne ?wcell              ; plasma gun / BFG
?wbul   lda #20                 ; pistol / chaingun: +20 bullets
        ldy #AM_BUL
        bpl ?wam                ; (always)
?wrock  lda #2
        ldy #AM_RKT
        bpl ?wam                ; (always)
?wcell  lda #40
        ldy #AM_CEL
?wam    jsr ?am
        jsr ?wfull              ; owned and its ammo full: it stays
        jmp ?wtail
?wshot  lda #8
        ldy #AM_SHL
        jsr ?am
        jsr ?wfull
        ldx #SFX_SGCOCK
        bne ?sfx                ; (always: SFX_SGCOCK <> 0, see the ert)
; ?WFULL - after ?am (C=1: full): D2DF picks a weapon up only when it is not
; owned or its ammo is below the limit; else back to the loop (the item
; stays, nothing changed: zpweap / zpwcur only move for a new one)
?wfull  bcc ?wf
        lda wp_had
        beq ?wf
        pla                     ; drop the jsr's return: the item stays
        pla
?skip2  jmp ?skip
?wf     rts
?backpack                       ; D2DF: the second limits, then +10 bullets,
        lda #0                  ; +4 shells, +1 rocket, +40 cells - only when
        sta ?bnew               ; not owned yet or some ammo below its limit
        ldx #7
?bc     lda am_cap1,x
        cmp pl_capl,x
        beq ?bs                 ; (a new limit: the first backpack)
        inc ?bnew
?bs     sta pl_capl,x
        dex
        bpl ?bc
        ldy #AM_CEL
?ba     lda ?badd,y
        jsr ?am                 ; keeps Y
        bcs ?bf
        inc ?bnew               ; something added
?bf     dey
        bpl ?ba
        lda ?bnew
        jeq ?skip               ; nothing new: the item stays
        jmp ?sfx_ammo
?badd   dta 10, 4, 1, 40
?bnew   dta 0
        ; ?am: counter Y (AM_*) += A, clamped to its limit; C=1 = was full
        ; (nothing added). Keeps Y.
?am     sta ?ad+1               ; SMC: the amount
        ldx am_zp,y
        lda 0,x
        cmp pl_capl,y
        lda am_hi,y
        sbc pl_caph,y
        bcs ?amr                ; >= limit: C=1
        lda 0,x                 ; C=0: the bcs not taken
?ad     adc #0
        sta 0,x
        lda am_hi,y
        adc #0
        sta am_hi,y
        lda pl_capl,y           ; limit - new: C=1 = within the limit
        cmp 0,x
        lda pl_caph,y
        sbc am_hi,y
        bcs ?amok
        lda pl_capl,y
        sta 0,x
        lda pl_caph,y
        sta am_hi,y
?amok   clc
?amr    rts
?wp_id  dta WP_SHOTGUN,0,WP_PISTOL,WP_CHAINGUN,WP_ROCKET,0,WP_PLASMA,0,WP_BFG,0,0,0,WP_SAW
pk_tmp  dta 0
wp_had  dta 0
.endp
        ert SFX_SGCOCK=0
        ert PK_SAW<>PK_SHOTGUN+12
        ert PK_SHELLS<>PK_SHOTGUN+1 || PK_PISTOL<>PK_SHOTGUN+2 || PK_CHAINGUN<>PK_SHOTGUN+3 || PK_ROCKETL<>PK_SHOTGUN+4 || PK_PLASMAGUN<>PK_SHOTGUN+6 || PK_BFG<>PK_SHOTGUN+8

; ============================================
; PK_WAKE - every active pickup with no floor under its feet (pk_x+8,
; pk_y) starts to fall, as D2DF items do (g_Obj_Move, Fallable): level start
; and after a panel change (a door opening under one).
; ============================================
.proc pk_wake
        ldx pk_end
?lp     dex
        bmi ?r
        lda pk_act,x
        beq ?lp
        jsr pk_floor            ; keeps X
        bne ?lp                 ; standing
        ldy #PF_MAX             ; already falling?
?in     dey
        bmi ?add
        txa
        cmp pf_i,y
        bne ?in
        beq ?lp                 ; (always)
?add    ldy #PF_MAX             ; a free slot ($FF), last first
?fr     dey
        bmi ?lp                 ; all busy: it waits for the next wake
        lda pf_i,y
        bpl ?fr
        txa
        sta pf_i,y
        lda #0
        sta pf_vy,y
        sta pf_vyf,y
        sta pf_yf,y
        inc pf_n
        bne ?lp                 ; (always: pf_n <= PF_MAX)
?r      rts
.endp

; PK_FLOOR - A <> 0 (Z=0): solid or platform under pickup X's feet. Keeps X.
.proc pk_floor
        lda pk_x,x
        clc
        adc #8
        sta gt_px
        lda pk_xhi,x
        adc #0
        sta gt_px_hi
        lda pk_y,x
        sta gt_py
        lda pk_y_hi,x
        sta gt_py_hi
        jmp check_solid_or_platform16
.endp

; ============================================
; PK_FALLS - the falling pickups: v += PL_GRAV (at most PL_MAXFALL px a
; frame, less than a cell: none passes a floor), y += v; on a floor the feet
; snap to its top and the slot frees.
; ============================================
.proc pk_falls
        ldy #PF_MAX
?lp     dey
        bmi ?r
        ldx pf_i,y
        bmi ?lp                 ; free slot
        lda pf_vyf,y            ; gravity (8.8), capped
        clc
        adc #PL_GRAV
        sta pf_vyf,y
        lda pf_vy,y
        adc #0
        cmp #PL_MAXFALL
        bcc ?v
        lda #0
        sta pf_vyf,y
        lda #PL_MAXFALL
?v      sta pf_vy,y
        lda pf_yf,y             ; y += v
        clc
        adc pf_vyf,y
        sta pf_yf,y
        lda pf_vy,y
        adc pk_y,x
        sta pk_y,x
        bcc ?nc
        inc pk_y_hi,x
?nc     sty ?y+1
        jsr pk_floor            ; keeps X
?y      ldy #0                  ; (patched: the slot)
        cmp #0                  ; (the ldy changed Z: A = the floor test)
        beq ?mv                 ; still in the air
        lda pk_y,x              ; landed: feet on the tile's top
        and #$100-TH
        sta pk_y,x
        lda #$FF
        sta pf_i,y
        dec pf_n
?mv     txa
        tay
        jsr pk_set_tile         ; the cell the cheap reject uses
        ldy ?y+1
        bpl ?lp                 ; (always: a slot < PF_MAX)
?r      rts
.endp

PF_MAX  = 4                     ; pickups falling at once
pf_i    :PF_MAX dta $FF         ; pickup index ($FF = free slot)
pf_vy   :PF_MAX dta 0           ; v (whole px / frame)
pf_vyf  :PF_MAX dta 0           ; v fraction
pf_yf   :PF_MAX dta 0           ; y fraction
pf_n    dta 0                   ; slots in use

; (render_pickups_nodirty deleted 2026-06-10: dead since the dirty-tile
;  system was retired - render_static draws all pickups every frame)
