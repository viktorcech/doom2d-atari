;==============================================
; DOOM2D - Enemy projectile hits + enemy projectiles
; enemies_proj.asm
;==============================================

; ============================================
; CHECK PROJECTILE HIT ON ALL ENEMIES
; Returns: C=1 if hit (enemy killed/damaged), C=0 if no hit
; Input: proj_x[zt], proj_y[zt] via X index in zt
; ============================================
.proc check_proj_enemies
        ; Y = projectile index (kept in Y throughout hot path)
        ; X = enemy index (kept in X throughout hot path)
        ldy zt                  ; Y = proj index
        ldx #0                  ; X = enemy index (slot 0 before the bound)
?lp     lda en_act,x
        cmp #1                  ; only alive enemies
        bne ?nxe
        ; --- X distance (16-bit) ---
        ; Y=proj, X=enemy — no register swapping needed
        ; |dx| < 14 <=> hi=0 and lo<14, or hi=$FF and lo>=243 (-13..-1; lo=0
        ; is -256 = far). zcp_tmph is never read, so it is not written.
        lda proj_x,y
        sec
        sbc en_x,x
        sta zcp_tmp             ; dist low
        lda proj_xh,y
        sbc enxhi,x             ; dist high (signed)
        bmi ?xneg
        bne ?nxe                ; hi != 0 -> too far
        lda zcp_tmp
        cmp #14                 ; within 14px X
        bcs ?nxe
        bcc ?ychk               ; (always)
?xneg   cmp #$FF
        bne ?nxe                ; <= -257 -> too far
        lda zcp_tmp
        cmp #243                ; within -13..-1
        bcc ?nxe
?ychk   ; --- Y distance (16-bit: player proj proj_y_hi vs enemy en_y_hi) ---
        lda proj_y,y
        sec
        sbc en_y,x
        sta abs16.ab_lo
        lda proj_y_hi,y
        sbc en_y_hi,x
        jsr abs16               ; preserves X (enemy) and Y (projectile)
        bcc ?nxe
        cmp #28                 ; within 28px Y
        bcc ?hit
?nxe    inx
        cpx num_en              ; only slots 0..num_en-1 can ever be active
        bcc ?lp
        clc                     ; no hit
        rts
?hit    ; --- HIT! ---
        ; Save Y for subroutine calls (hit path is rare; X = enemy survives
        ; every call below that needs it, so it is not parked)
        sty zcp_proj
        ; Apply damage
        lda en_hp,x
        sec
        sbc proj_dmg,y
        bcc ?kill
        beq ?kill
        sta en_hp,x
        lda proj_vx,y           ; the blood the shot's way
        jsr bl_way
        lda proj_dmg,y          ; pain / wake-up as TMonster.Damage
        jsr en_hurt             ; (preserves X, Y)
?kb     ; Knockback from hit (use proj_vx direction)
        lda proj_vx,y
        bmi ?kb_l
        lda envelx,x            ; knockback right
        clc
        adc #2
        cmp #4
        bcc ?kb_s
        lda #4
        bne ?kb_s               ; (always: A = 4)
?kb_l   ; Knockback left
        lda envelx,x
        sec
        sbc #2
        cmp #$FC
        bcs ?kb_s
        lda #$FC
?kb_s   sta envelx,x
        ; Play pain sound per enemy type (clobbers X/Y)
        ldy en_type,x
        lda en_pain_sfx,y
        jsr play_sfx
        ; Destroy projectile (shared tail; Y = proj index 0..MAX_PROJ-1: N=0)
        ldy zcp_proj
        bpl ?nosplash           ; (always)
?kill   ; Enemy killed! (X=enemy, Y=proj still valid here)
        jsr start_enemy_death   ; preserves X (= enemy), clobbers Y
        ; Knockback velocity for gib (rocket + weak enemy only)
        ldy zcp_proj
        lda proj_spr,y
        cmp #SPR_ROCKET_PROJ
        bne ?no_gib
        ; Only zombie, imp, shotgun guy can gib
        lda en_type,x
        cmp #EN_ZOMBIE
        beq ?do_gib
        cmp #EN_IMP
        beq ?do_gib
        cmp #EN_SHOTGUN
        bne ?no_gib
?do_gib lda #1
        sta en_gib,x
        lda proj_vx,y           ; Y still = proj
        bmi ?gib_l
        lda #8
        dta $2C                 ; bit $F8A9 (ROM/RAM, no I/O): skips lda #$F8
?gib_l  lda #$F8
        sta envelx,x
        lda #$F4
        sta envely,x
        ; Gib sound (clobbers regs)
        lda #SFX_SLOP
        jsr play_sfx
        jmp ?kill_done
?no_gib ; (start_enemy_death set it falling)
        ; Death sound (clobbers regs)
        jsr play_enemy_death
?kill_done
        ; Destroy projectile + splash if rocket
        ldy zcp_proj
        lda proj_spr,y
        cmp #SPR_ROCKET_PROJ
        bne ?nosplash
        jsr rocket_splash_player
        ldy zcp_proj
?nosplash
        lda #0
        sta proj_a,y
        sec                     ; hit
        rts
; zcp_proj used only in hit path (rare); zcp_tmp in the distance calc
.endp

; ============================================
; ENEMY PROJECTILES (imp fireball etc.)
; ============================================
MAX_EPROJ = 3

eproj_a   .ds MAX_EPROJ       ; 0=inactive, 1=active
eproj_x   .ds MAX_EPROJ       ; X lo
eproj_xh  .ds MAX_EPROJ       ; X hi
eproj_y   .ds MAX_EPROJ       ; Y lo
eproj_y_hi .ds MAX_EPROJ      ; Y hi (16-bit for tall maps)
eproj_vx  .ds MAX_EPROJ       ; velocity X (signed)
eproj_dmg .ds MAX_EPROJ       ; damage
eproj_spr .ds MAX_EPROJ       ; sprite index
eproj_own .ds MAX_EPROJ       ; the monster that fired it

.proc init_eproj
        ldx #MAX_EPROJ-1
?lp     lda #0
        sta eproj_a,x
        dex
        bpl ?lp
        rts
.endp

; (spawn_eproj: enemies_ai.asm, in the low RAM)

; Update enemy projectiles
.proc eproj_update
        ldx #0
        clc                     ; C = 0 at ?lp on every entry (here, and the
        beq ?lp                 ; taken bcc below); slot 0 first, order 0..2
?kill   lda #0                  ; (the loop's end up here: in reach of ?lp)
        sta eproj_a,x
?nx     inx
        cpx #MAX_EPROJ
        bcc ?lp
        rts
?lp     lda eproj_a,x
        beq ?nx
        ; (animation moved to render_eproj: FIRE2 = FIRE1+1 and all FIRE1
        ; bases are even, so the frame is pure math - no per-type chains)
        ; Update 16-bit X (C = 0, see the head)
        lda eproj_x,x
        adc eproj_vx,x
        sta eproj_x,x
        lda eproj_vx,x
        bmi ?negv
        lda eproj_xh,x
        adc #0                  ; xh <= 3 (the bounds test below) + C <= 1:
        bcc ?bounds             ; no carry out, always (N kept)
?negv   lda eproj_xh,x
        adc #$FF
?bounds sta eproj_xh,x          ; stores keep N/Z of the new hi byte
        ; Kill if off the map (the rest of the right edge: the tile test,
        ; off the map reads as solid)
        bmi ?kill
        cmp #[MAP_W*TW+255]/256
        bcs ?kill
        ; Check wall collision (C=0: bcs not taken)
        lda eproj_x,x
        adc #4
        sta gt_px
        lda eproj_xh,x
        adc #0
        sta gt_px_hi
        lda eproj_y,x
        sta gt_py
        lda eproj_y_hi,x
        sta gt_py_hi
        jsr check_solid16      ; preserves X
        bne ?kill
        jsr ep_mon             ; the monsters first (g_Weapon_Hit), X kept
        bcs ?kill
        beq ?nx                ; a dead player: the shot flies on
        ; Check player collision (8x8 vs player 10x28)
        ; X distance: true 16-bit abs (hits from BOTH sides symmetrically)
        lda eproj_x,x
        sec
        sbc zpx
        sta abs16.ab_lo
        lda eproj_xh,x
        sbc zpx_hi
        jsr abs16
        bcc ?nx
        cmp #12                ; within 12px X
        bcs ?nx
        ; Y distance (16-bit |eproj_y - zpy| < 24)
        lda eproj_y,x
        sec
        sbc zpy
        sta abs16.ab_lo
        lda eproj_y_hi,x
        sbc zpy_hi
        jsr abs16
        bcc ?nx
        cmp #24                ; within 24px Y
        bcs ?nx
        ; Hit player! (then the same slot clear)
        lda eproj_vx,x          ; the blood the ball's way
        jsr bl_way
        lda eproj_dmg,x
        jsr player_take_damage ; preserves X
        jmp ?kill
.endp

; Render enemy projectiles
.proc render_eproj
        ; Animate: sprite = FIRE1_base | (zfr>>2 & 1): FIRE2 = FIRE1+1 and
        ; FIRE1 is even (prepare_sprites.py); a baron ball flying left: +2.
        ; The frame bit is the same for every ball: once, into ora's operand
        lda zfr
        lsr
        lsr
        and #1
        sta ?fr+1
        ldx #0
?lp     lda eproj_a,x
        beq ?nx
        stx ?rx+1               ; blit_sprite clobbers X and Y (SMC: ldx #)
        lda eproj_spr,x
        cmp #SPR_BARON_FIRE1
        bne ?fr
        ldy eproj_vx,x
        bpl ?fr
        lda #SPR_BARON_FIRE1_L
?fr     ora #0
        tay                     ; Y = sprite
        lda spr_ox,y            ; zdxh:zdx = eproj_x + signed offset (centred)
        clc
        adc eproj_x,x
        sta zdx
        lda spr_ox,y            ; its sign: read from the table again, no copy
        and #$80                ; (lda / and keep C)
        beq ?xp
        lda #$FF
?xp     adc eproj_xh,x
        sta zdxh
        lda spr_oy,y
        clc
        adc eproj_y,x
        sta zdy
        lda spr_oy,y
        and #$80
        beq ?yp
        lda #$FF
?yp     adc eproj_y_hi,x
        sta zdy_hi
        tya
        jsr blit_sprite
?rx     ldx #0                  ; = slot index (patched above)
?nx     inx
        cpx #MAX_EPROJ
        bne ?lp
        rts
.endp
        ert SPR_IMP_FIRE1&1 .or SPR_CACO_FIRE1&1 .or SPR_BARON_FIRE1&1 .or SPR_BARON_FIRE1_L&1
