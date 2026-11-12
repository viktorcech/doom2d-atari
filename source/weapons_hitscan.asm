;==============================================
; DOOM2D - Hitscan fire system
; weapons_hitscan.asm
;
; Instant-hit for pistol/shotgun/chaingun.
; Scans tile columns, checks enemies and barrels.
;==============================================

; ============================================
; HITSCAN FIRE - instant hit for pistol/shotgun/chaingun
; Scans tile columns from player in firing direction,
; stops at first wall or enemy hit.
; ============================================
.proc hitscan_fire
        jsr ?scan
        jsr ?trig
        lda zpwcur              ; the shotgun: its 10 pellets' sparks
        cmp #WP_SHOTGUN
        beq ?pel
        rts

        ; g_Weapon_shotgun: 10 pellets, each Random(17)-8 px off the gun's
        ; height (half scale: (r-8)>>1), each sparks at its first wall unless
        ; the shot's first enemy (hs_lim; |dy| < 18 for every pellet) is nearer.
        ; (2026-10-30 6502-idioms.md "Code size is RAM": a cold path, ?row shared)
?pel    lda #10
        sta hs_n
?pl     lda RANDOM              ; r = Random(17)
        and #31
        cmp #17
        bcs ?pl
        sbc #7                  ; C=0 (bcs not taken): r - 8 (6502-idioms.md
        ldx #0                  ; "sbc #v-1 with C known clear")
        cmp #$80                ; dy = (r-8) >> 1 = -4..4, arithmetic (65816-
        ror                     ; windows.md "cmp #$8000 / ror @", 8-bit)
        bpl ?py                 ; N = the sign: X = its extension
        dex
?py     clc
        adc hs_y0
        sta bl_cy               ; this pellet's height (bl_wall reads it)
        txa
        adc hs_y0+1
        sta bl_cy+1
        jsr ?row
        lda hs_pc
?pn     clc
        adc ?step+1             ; +1 / -1 (patched by ?scan)
        cmp #MAP_W
        bcs ?pd                 ; off the map
        cmp hs_lim
        beq ?pd                 ; the enemy hit first: no sparks
        tay                     ; (the column stays in Y)
        lda (ztptr),y
        bmi ?po                 ; background: on
        tax
        lda tile_solid,x
        beq ?po
        cpx #15
        beq ?pd                 ; a barrel (a monster in D2DF): no sparks
        tya
        jsr bl_wall
?pd     dec hs_n
        bne ?pl
        rts
?po     tya                     ; N=0: a column < MAP_W (6502-idioms.md "jmp L,
        bpl ?pn                 ; a flag is known: the branch on that flag")

?trig   ; D2DF g_Triggers_PressL: the shot's line, the gun's column to the
        ; last one scanned, fires its SHOT triggers
        lda hs_row
        sta mr0
        tax
        inx
        stx mr1
        lda hs_cur
        ldx hs_pc
        cmp hs_pc
        bcs ?o                  ; shot right: [pc, cur]
        ldx hs_cur              ; shot left: [cur, pc]
        lda hs_pc
?o      stx mc0
        clc
        adc #1
        sta mc1
        jmp trig_shot

?scan   ; Pre-compute weapon damage
        ldx zpwcur
        lda weap_dmg,x
        sta hs_dmg

        lda #$FF                ; no enemy hit yet (pellets: ?pel)
        sta hs_lim
        ; the gun's height zpy - 14 (16-bit), bl_wall's spark height too
        lda zpy
        sec
        sbc #14
        sta hs_y0
        sta bl_cy
        lda zpy_hi
        sbc #0
        sta hs_y0+1
        sta bl_cy+1
        jsr ?row

        ; Scan direction (SMC): mask 0 / $FF (zpdir 0 right / 1 left), step
        ; +1 / $FF = mask | 1
        lda #0
        sec
        sbc zpdir
        sta ?msk+1
        ora #1
        sta ?step+1

        ; Player tile column = (zpx_hi:zpx+5) / 8 = hi*32 | lo/8 (LUT)
        lda zpx
        clc
        adc #5
        tay
        lda zpx_hi
        adc #0
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,y          ; A = player tile column (0..MAP_W-1: x clamped)
        sta hs_pc
        sta hs_cur              ; (a first step off the map scans nothing)
        eor ?msk+1
        sta ?pcm+1              ; pc' = pc, mirrored when shooting left

        ; Pass 1, once a shot (2026-10-30 fable-skill-atari.md "Place each
        ; rejection by what it needs" / "Work shared by several items is done
        ; once"): the enemy hs_chk_col_next would find first in the nearest
        ; column ahead (the lowest index on a tie): ?be = its column, hs_bx
        lda #$FF
        sta ?be+1               ; none: no column matches $FF
        sta hs_bd
        ldx #$FF
?e1     inx
        cpx num_en              ; only slots 0..num_en-1 can ever be active
        bcs ?e9
        lda en_act,x
        cmp #1
        bne ?e1
        lda en_y,x              ; 16-bit |en_y - zpy| < 18
        sec
        sbc zpy
        sta abs16.ab_lo
        lda en_y_hi,x
        sbc zpy_hi
        jsr abs16
        bcc ?e1
        cmp #18
        bcs ?e1
        lda en_x,x              ; its column = (enxhi:en_x+8)/8
        clc
        adc #8
        tay
        lda enxhi,x
        adc #0
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,y
        tay                     ; Y = its column
?msk    eor #0                  ; (patched: the mask)
        clc                     ; distance - 1 = col' - pc' - 1: its own
?pcm    sbc #0                  ; column $FF, behind >= $9B (patched: pc')
        cmp hs_bd
        bcs ?e1                 ; not nearer (a tie keeps the lower index)
        sta hs_bd
        sty ?be+1
        stx hs_bx
        bcc ?e1                 ; (always: C=0)
?e9     lda hs_pc               ; C=1 (bcs ?e9): the first step from the
        bcs ?nx                 ; player's column

        ; One loop for both directions: column 0 - 1 = $FF and MAP_W both
        ; fail the cmp #MAP_W, so the old two bounds tests are one.
?lp     sta hs_cur
        tay                     ; (the column stays in Y)
        lda (ztptr),y
        bmi ?open               ; bit 7 = BG, passable
        tax
        lda tile_solid,x
        beq ?open
        cpx #15                 ; barrel invisible solid?
        beq hs_chk_barrel       ; barrel: stop either way (tail call)
        lda zpwcur              ; real wall: its sparks (blood.asm, tail call);
        cmp #WP_SHOTGUN         ; the shotgun's come from its pellets (?pel)
        beq ?r
        tya
        jmp bl_wall
?open   tya
?be     cmp #$FF                ; (patched: the enemy's column; 6502-loops-tables-
        beq ?hit                ; smc.md "a variable as the operand of cmp #")
?nx     clc
?step   adc #1                  ; operand patched above
        cmp #MAP_W
        bcc ?lp
?r      rts                     ; past the last / first column

; ?ROW - hs_row, ztptr + its map bank = the map row of height bl_cy (16-bit
; Y: on a 32-row map the high byte decides everything below y=256)
?row    ldy bl_cy
        lda bl_cy+1
        asl
        asl
        asl
        asl
        asl                     ; yhi * 32
        ora div8_lut,y          ; | lo >> 3
        sta hs_row
        tay                     ; Y = tile row
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        lda map_row_bank,y
        sta VBXE_BANK_SEL
        rts

?hit    sta hs_lim              ; A = the column: the pellets stop there
        ldx hs_bx               ; the enemy (pass 1)
        jsr hs_damage_enemy
        ; Shotgun pierce: check for second enemy in same column
        lda zpwcur
        cmp #WP_SHOTGUN
        bne ?miss
        ; Continue from next enemy index (hs_chk_col_next does the inx)
        jsr hs_chk_col_next
        bcs hs_damage_enemy     ; tail call
?miss   rts

hs_row  dta 0
hs_cur  dta 0
hs_pc   dta 0
hs_dmg  dta 0
hs_lim  dta 0                   ; column of the enemy hit ($FF: none)
hs_y0   dta 0,0                 ; the gun's height
hs_n    dta 0                   ; pellets left
hs_bd   dta 0                   ; pass 1: the nearest enemy's distance - 1
hs_bx   dta 0                   ; and its index
.endp

; ============================================
; HS_CHK_BARREL - damage barrel at tile column hs_cur
; ============================================
.proc hs_chk_barrel
        lda hitscan_fire.hs_cur ; the scan already knows WHICH tile is the
        sta gt_col              ; barrel - look up its owner instead of
        lda hitscan_fire.hs_row ; grabbing the first barrel in the column
        sta gt_row              ; (two barrels stacked hit the wrong one)
        jsr find_barrel_at      ; X = decoration index
        bcc ?ret
        lda dc_hp,x
        sbc hitscan_fire.hs_dmg ; C=1: the bcc above not taken
        bcs ?hok
        lda #0
?hok    jmp proj_hit_barrel.hp_set ; store, ignite at 0 (shared tail)
?ret    rts
.endp

; ============================================
; HS_DAMAGE_ENEMY - apply hitscan damage to enemy X
; ============================================
.proc hs_damage_enemy
        lda en_hp,x
        sec
        sbc hitscan_fire.hs_dmg
        bcs ?hok
        lda #0
?hok    sta en_hp,x
        beq kill
        jsr bl_pshot            ; the blood's way (blood.asm)
        lda hitscan_fire.hs_dmg ; pain / wake-up as TMonster.Damage
        jmp en_hurt             ; tail call (preserves X, Y)
kill                            ; (en_mdmg's kill too)
        jsr start_enemy_death   ; killed
        jmp play_enemy_death    ; tail call
.endp

; ============================================
; HS_CHK_COL_NEXT - the next enemy after X in tile column hs_cur within
; |dy| < 18 (the shotgun's pierce)
; Returns: C=1 hit (X=enemy), C=0 no hit
; ============================================
.proc hs_chk_col_next
?nx     inx                     ; increment ahead of the head: skips branch back here
        cpx num_en              ; only slots 0..num_en-1 can ever be active
        bcs ?miss
        lda en_act,x
        cmp #1
        bne ?nx
        ; Enemy tile column = (enxhi:en_x+8)/8 = hi*32 | lo/8 (LUT)
        lda en_x,x
        clc
        adc #8
        tay
        lda enxhi,x
        adc #0
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,y
        cmp hitscan_fire.hs_cur
        bne ?nx
        ; Same column! Check Y (16-bit |en_y - zpy| < 18)
        lda en_y,x
        sec
        sbc zpy
        sta abs16.ab_lo
        lda en_y_hi,x
        sbc zpy_hi
        jsr abs16
        bcc ?nx
        cmp #18
        bcs ?nx
        sec
        rts
?miss   clc
        rts
.endp
