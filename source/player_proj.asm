;==============================================
; DOOM2D - Player projectiles, death, damage
; player_proj.asm
;==============================================

; ============================================
; PROJECTILES
; ============================================
proj_a  .ds MAX_PROJ
proj_x  .ds MAX_PROJ
proj_xh .ds MAX_PROJ            ; X high byte (for positions > 255)
proj_y  .ds MAX_PROJ
proj_y_hi .ds MAX_PROJ         ; Y high byte (16-bit for tall maps)
proj_vx .ds MAX_PROJ
proj_dmg .ds MAX_PROJ           ; damage per projectile (from weapon)
proj_spr .ds MAX_PROJ           ; sprite index per projectile

.proc spawn_proj
        ldx #0
?f      lda proj_a,x
        beq ?ok
        inx
        cpx #MAX_PROJ
        bne ?f
        rts
?ok     lda #1
        sta proj_a,x
        lda zpx
        sta proj_x,x
        lda zpx_hi
        sta proj_xh,x
        lda zpy
        sec
        sbc #14             ; gun height (chest level)
        sta proj_y,x
        lda zpy_hi
        sbc #0              ; 16-bit Y
        sta proj_y_hi,x
        ; Set damage and sprite from saved weapon (auto-switch may have changed zpwcur)
        ldy player_update.fire_wcur
        lda weap_dmg,y
        sta proj_dmg,x
        lda weap_proj_spr,y
        sta proj_spr,x
        lda zpdir
        bne ?pl
        lda #3
        dta $2C                 ; bit $FDA9 (no I/O): skips lda #$FD
?pl     lda #$FD
        sta proj_vx,x
        rts
.endp

.proc proj_update
        ldx #0
?lp     lda proj_a,x
        bne ?upd
?nx     inx                  ; next slot (ascending order kept)
        cpx #MAX_PROJ
        bne ?lp
        rts
?upd    ; Update 16-bit X: proj_xh:proj_x += proj_vx (signed)
        lda proj_x,x
        clc
        adc proj_vx,x
        sta proj_x,x
        ; Sign-extend velocity to high byte
        lda proj_vx,x
        bmi ?neg
        ; Positive velocity: xh += carry
        lda proj_xh,x
        adc #0
        sta proj_xh,x        ; N,Z = new xh (from adc, binary mode)
        bpl ?xin             ; (always: a live xh is 0..3, +1 at most)
?neg    ; Negative velocity: xh += $FF + carry
        lda proj_xh,x
        adc #$FF
        sta proj_xh,x
        ; Kill if off the map; A, N, Z = proj_xh,x. Past the right edge inside
        ; the last 256 px the tile test kills it (off the map reads as solid).
        jmi ?kill            ; xh < 0: past left edge
?xin    cmp #[MAP_W*TW+255]/256
        jcs ?kill            ; xh past the map's last page
        ; One tile lookup covers walls AND barrels: a barrel IS the invisible
        ; solid tile 15 it wrote into the map, so hitting that tile means
        ; hitting the barrel. (The old code scanned all 16 decorations for
        ; every projectile every frame just to get ahead of the tile test.)
        stx zt
        lda proj_x,x
        clc
        adc #4              ; center of 8x8 sprite
        sta gt_px
        lda proj_xh,x
        adc #0
        sta gt_px_hi
        lda proj_y,x
        sta gt_py
        lda proj_y_hi,x
        sta gt_py_hi
        jsr get_tile_at16   ; preserves X; A = tile, gt_col/gt_row set
        bmi ?tile_open      ; bit7 = BG tile, passable
        cmp #15
        beq ?hit_barrel
        tay
        lda tile_solid,y
        bne ?kill
?tile_open
        lda tr_shot             ; D2DF PressR: the level's SHOT triggers
        and #AC_SHOT            ; under the flying projectile
        beq ?ns
        jsr pj_shot             ; A = 0: its cell
        ldx zt
?ns     ; Check hit against all enemies
        jsr check_proj_enemies
        bcc ?nx3            ; no hit: ldx zt and next slot (was ldx zt / jmp ?nx)
        ; Enemy hit — check if BFG for radius blast
        ldx zt
        lda proj_spr,x
        cmp #SPR_BFG_PROJ1
        bne ?nx4            ; not BFG, done (X = zt)
        jsr bfg_blast
        ldx #SFX_BFGXPL     ; (old txa/pha..pla/tax: X reloaded from zt at ?nx3)
        jsr snd_play
        beq ?nx3            ; (always: snd_play ends ldy #0 / tay of a 0)
?hit_barrel                     ; X = zt (stx zt; get_tile_at16 preserves X)
        jsr proj_hit_barrel     ; damages the barrel owning (gt_col,gt_row)
        ldx zt                  ; then die like any other wall hit, so a
                                ; rocket still gets its splash + boom and a
                                ; BFG still gets its blast
?kill   lda proj_spr,x
        cmp #SPR_ROCKET_PROJ
        bne ?chk_bfg
        jsr rocket_splash_player ; spr = rocket: it sets rs_proj = X
        ldx #SFX_BAREXP
        jsr snd_play
        lda #4                  ; D2DF PressC: rad 60 = 3.75 cells
        jsr pj_shot
        ldx rs_proj
        bpl ?no_ksnd            ; (always: a slot < MAX_PROJ)
?chk_bfg
        cmp #SPR_BFG_PROJ1
        bne ?no_ksnd
        jsr bfg_blast           ; sets bf_proj = X
        ldx #SFX_BFGXPL
        jsr snd_play
        ldx bfg_blast.bf_proj
?no_ksnd
        lda #0
        sta proj_a,x
        beq ?nx4                ; (always)
?nx3    ldx zt
?nx4    inx
        cpx #MAX_PROJ
        jne ?lp
        rts
.endp

; ============================================
; PLAYER DEAD - death animation + wait for R restart
; ============================================
pl_dead_timer dta 0
pl_pain_timer dta 0
pl_expl_iframe dta 0    ; explosion-damage immunity, ticked in player_update.
                        ; Splash has no i-frames in DOOM either, but there a
                        ; barrel chain is one blast per barrel spread over a
                        ; second; here five barrels can land five full 100-dmg
                        ; hits inside ~10 frames, which is unsurvivable.

.proc player_dead
        lda pl_dead_timer
        beq ?first
?counting                       ; A = pl_dead_timer
        ; Increment death timer (for animation), saturating at 255
        cmp #255
        beq ?wait
        adc #1                  ; C=0: cmp #255 not equal, so A < 255
        sta pl_dead_timer
?wait
        ; Auto-restart after ~3s (timer=180); A = pl_dead_timer
        cmp #180
        bcc ?done
        lda #$FF
        sta CH
        jsr sio_quiet           ; silence, the sample IRQ off
        lda #0
        sta pl_dead_timer
        jsr load_level
        jsr init_game
        jmp init_render         ; tail call (it also forces the HUD redraw)
?done   rts
?first  ; First frame of death: play sound, init timer
        lda #0
        sta snd_lock
        ldx #SFX_PLDEATH
        jsr snd_play
        lda #1
        sta pl_dead_timer
        bne ?counting           ; Z=0 from lda #1; A = 1
.endp

; ============================================
; BFG BLAST - radius damage to all enemies in range
; Input: X = projectile index
; Radius: 64px, Damage: 20 per enemy
; ============================================
BFG_RADIUS = 64
BFG_BLAST_DMG = 20

.proc bfg_blast
        stx bf_proj
        ; Check once: is proj inside a solid tile? (wall/door hit)
        lda proj_x,x
        sta gt_px
        lda proj_xh,x
        sta gt_px_hi
        lda proj_y,x
        sta gt_py
        lda proj_y_hi,x
        sta gt_py_hi
        jsr check_solid16
        sta bf_wall             ; 0 = open air, !0 = in wall
        ldy #0                  ; X = bf_proj (check_solid16 preserves X) in the loop;
?lp     sty bf_eidx             ; only the kill path clobbers it and reloads it
        lda en_act,y
        cmp #1
        jne ?nx
        ; X distance: 16-bit |proj_x - en_x|.
        ; (Was an 8-bit test guarded by "proj_xh == enxhi", so the BFG blast
        ;  had a dead zone across x=256 - the same bug as the barrel, the
        ;  pickup radius and melee.)
        lda proj_x,x
        sec
        sbc en_x,y
        sta abs16.ab_lo
        lda proj_xh,x
        sbc enxhi,y
        jsr abs16               ; preserves X (projectile) and Y (enemy)
        bcc ?nx
        cmp #BFG_RADIUS
        bcs ?nx
        ; Y distance (16-bit: player proj proj_y_hi vs enemy en_y_hi); X = bf_proj
        lda proj_y,x
        sec
        sbc en_y,y
        sta abs16.ab_lo
        lda proj_y_hi,x
        sbc en_y_hi,y
        jsr abs16               ; preserves X (projectile) and Y (enemy)
        bcc ?nx
        cmp #BFG_RADIUS
        bcs ?nx
        ; LOS: if proj hit wall, block enemies behind it
        lda bf_wall
        beq ?los_ok             ; proj in open air, blast always hits
        lda proj_vx,x           ; X = bf_proj
        bmi ?chk_left
        ; Proj going right: only hit enemies LEFT of proj (near side)
        lda en_x,y
        cmp proj_x,x
        jcs ?nx                 ; enemy X >= proj X = behind wall
        bcc ?los_ok             ; C=0 known
?chk_left
        ; Proj going left: only hit enemies RIGHT of proj (near side)
        lda proj_x,x
        cmp en_x,y
        jcs ?nx                 ; proj X >= enemy X = behind wall
?los_ok ; Y = bf_eidx on every path here (abs16 preserves Y)
        ; Hit! Apply BFG damage
        lda en_hp,y
        sec
        sbc #BFG_BLAST_DMG
        bcs ?hok
        lda #0
?hok    sta en_hp,y
        bne ?nx
        ; Killed
        lda #2
        sta en_act,y
        lda #0
        sta en_gib,y
        sta envelx,y
        lda #1                  ; falls until move_corpse lands it
        sta envely,y
        tya                    ; (bf_eidx already = Y)
        tax
        jsr play_enemy_death
        ldy bf_eidx
        ldx bf_proj             ; restore the loop's X = projectile
?nx     ; Y = bf_eidx on every path here
        iny
        cpy num_en          ; only slots 0..num_en-1 can ever be active
        jcc ?lp
        rts                 ; X = bf_proj (both callers load X next anyway)
bf_proj dta 0
bf_eidx dta 0
bf_wall dta 0
.endp

rs_proj dta 0                   ; rocket_splash_player's X (its callers reload it)

; ============================================
; ROCKET SPLASH DAMAGE + KNOCKBACK TO PLAYER
; Input: X = projectile index. Clobbers X (falls into rocket_splash_enemies).
; ============================================
.proc rocket_splash_player
        lda proj_spr,x
        cmp #SPR_ROCKET_PROJ
        bne rocket_splash_enemies.done
        stx rs_proj
        lda proj_x,x            ; blast centre = the rocket
        sta spl_x
        lda proj_xh,x
        sta spl_xhi
        lda proj_y,x
        sta spl_y
        lda proj_y_hi,x
        sta spl_yhi
        lda #ROCKET_SPLASH_RADIUS
        sta spl_radius
        lda #ROCKET_SPLASH_MAX
        sta spl_max
        lda #ROCKET_SPLASH_SCALE
        sta spl_scale
        lda #BARREL_KB_X        ; rockets throw as hard as barrels do
        sta spl_kbx
        lda #ROCKET_KB_Y
        sta spl_kby
        lda #0                  ; no LOS test: a rocket detonates ON the wall
        sta spl_los             ; it hit, which would block its own splash
        jsr explosion_splash_player
        ert *<>rocket_splash_enemies    ; falls through
.endp

; ============================================
; ROCKET_SPLASH_ENEMIES - g_Weapon_Explode (radius 60 = 30 px here): every
; live monster with its rect centre mm = max(|dx|, |dy|) < 30 px from the
; blast (spl_x/spl_y) takes (Rect.Width/4)*10*(60-2mm)/60 = mon_hw*(30-mm)/3
; ============================================
RS_RAD  = 30
.proc rocket_splash_enemies
        ldx #0
?lp     cpx num_en
        bcc ?one
done    rts
?one    lda en_act,x
        cmp #1
        jne ?nx
        ldy en_type,x
        lda en_x,x              ; dx = en_x + 8 - spl_x
        clc
        adc #8
        sta ?t
        lda enxhi,x
        adc #0
        sta ?t+1
        lda ?t
        sec
        sbc spl_x
        sta abs16.ab_lo
        lda ?t+1
        sbc spl_xhi
        jsr abs16               ; C=0: >= 256 (keeps X, Y)
        jcc ?nx
        cmp #RS_RAD
        jcs ?nx
        sta ?mm
        lda mon_h,y             ; dy = en_y - h/2 - spl_y
        lsr
        sta ?t
        lda en_y,x
        sec
        sbc ?t
        sta ?t
        lda en_y_hi,x
        sbc #0
        sta ?t+1
        lda ?t
        sec
        sbc spl_y
        sta abs16.ab_lo
        lda ?t+1
        sbc spl_yhi
        jsr abs16
        bcc ?nx
        cmp #RS_RAD
        bcs ?nx
        cmp ?mm
        bcc ?m
        sta ?mm                 ; mm = the larger one
?m      lda #RS_RAD             ; dmg = hw * (30 - mm) / 3
        sec
        sbc ?mm
        sta ?f
        lda mon_hw,y
        tay
        lda #0                  ; p = hw * f: lo in A, hi in ?ph
        sta ?ph
?mul    clc
        adc ?f
        bcc ?mn
        inc ?ph
?mn     dey
        bne ?mul
        ldy #0                  ; Y = p / 3 by subtraction (p <= 15*30: ?ph <= 1)
?div    sec
        sbc #3
        bcs ?nb
        dec ?ph                 ; the borrow: 0 -> $FF is below 0
        bmi ?dq                 ; below 0: Y is the quotient
?nb     iny
        bne ?div                ; (always: Y <= 150)
?dq     tya
        beq ?nx
        sta ?d
        lda en_hp,x
        sec
        sbc ?d
        bcc ?kill
        beq ?kill
        sta en_hp,x
        lda ?d
        jsr en_hurt             ; pain / wake-up (keeps X, Y)
        jmp ?nx
?kill   lda #0
        sta en_hp,x
        jsr start_enemy_death   ; keeps X
        stx ?x+1
        jsr play_enemy_death    ; (clobbers X)
?x      ldx #0                  ; (patched)
?nx     inx
        jmp ?lp
?t      dta 0,0
?mm     dta 0
?f      dta 0
?ph     dta 0
?d      dta 0
.endp

; ============================================
; PLAYER TAKE DAMAGE (with armor absorption)
; Input: A = damage amount
; Armor absorbs 75% damage, HP takes 25%
; ============================================
.proc player_take_damage
        sta ptd_dmg
        lda zphp                ; dead: nothing hits him any more (D2DF: only
        beq ?god                ; an alive player is hit)
        jsr bl_pl               ; the blood (blood.asm; keeps X, Y)
        lda pl_god              ; god mode (G key): the hit draws blood only
        bne ?god
        lda zparmor
        beq ?no_armor
        ; armor_hit = damage * 3/4
        lda ptd_dmg
        lsr
        lsr                     ; damage/4 (HP portion)
        bne ?calc
        lda #1                  ; minimum 1 HP damage
?calc   sta ptd_hp
        clc                     ; ~hit = hp - damage - 1 (hit = damage - damage/4)
        sbc ptd_dmg
        ; Reduce armor: zparmor + ~hit + 1 = zparmor - hit, C = (zparmor >= hit)
        ; exactly as sec / sbc hit gave it
        sec
        adc zparmor
        bcs ?ar_ok
        lda #0
?ar_ok  sta zparmor
        ; Apply HP portion
        lda zphp
        sec
        sbc ptd_hp
        bcs ?hp_ok
        lda #0
        beq ?hp_ok              ; Z=1 from lda #0
?no_armor
        ; No armor: full damage to HP
        lda zphp
        sec
        sbc ptd_dmg
        bcs ?hp_ok
        lda #0
?hp_ok  sta zphp
        lda #12                ; pain sprite for 12 frames (~0.2s)
        sta pl_pain_timer
?god    rts
ptd_dmg dta 0
ptd_hp  dta 0
.endp
pl_god  dta 0                   ; 1: god mode (main.asm G key), no damage
