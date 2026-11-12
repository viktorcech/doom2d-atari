;==============================================
; DOOM2D - Enemy AI + physics, ported from Doom 2D Forever (g_monsters.pas
; TMonster.Update / g_phys.pas g_Obj_Move) at half scale, 50 frames/s.
; enemies_ai.asm
;
; The original moves every game tick (36/s) and thinks every 2nd (18/s):
; here en_move runs every frame and en_think on AI frames (ai_acc carry,
; 18/50 of the frames). Speeds are the original's /2 x 0.72 in 8.8 px/frame.
; States (en_state): SLEEP, GO, RUN, CLIMB, ATTACK, PAIN - TMonster's
; MONSTATE_SLEEP/GO/RUN/CLIMB/ATTACK+SHOOT/PAIN; timers count AI ticks.
;==============================================

ES_SLEEP  = 0
ES_GO     = 1
ES_RUN    = 2
ES_CLIMB  = 3
ES_ATTACK = 4
ES_PAIN   = 5
ES_RUNOUT = 6                   ; MONSTATE_RUNOUT: back out of a BLOCKMON panel

AI_STEP   = 92                  ; 256*18/50: AI ticks per frame, 8-bit fraction
AN_STEP   = 184                 ; 256*36/50: animation ticks per frame

ANIM_SLEEP  = 0                 ; g_monsters.pas ANIM_*: mon_frames.asm ma_*
ANIM_GO     = 1
ANIM_DIE    = 2
ANIM_MESS   = 3
ANIM_ATTACK = 4
ANIM_PAIN   = 6
EN_NEAR   = 20                  ; |sx| < 40 px (original) -> random run
EN_ABOVE  = 20                  ; target 40 px (original) above -> jump
EN_FLY_DZ = 4                   ; flyers hold height within 8 px (original)

; per-enemy state (indexed by X): RAM past the foreground code (main.asm
; guards it), out of the main segment
en_state  = EN_AI_RAM
en_sleep  = en_state+MAX_ENEMIES ; FSleep: AI-tick counter of the state
en_ammo   = en_sleep+MAX_ENEMIES ; FAmmo: < 0 = may not shoot (counts up)
en_pain   = en_ammo+MAX_ENEMIES ; FPain
en_vx     = en_pain+MAX_ENEMIES ; walk velocity 8.8, whole part (signed)
en_vxf    = en_vx+MAX_ENEMIES
en_vyf    = en_vxf+MAX_ENEMIES  ; envely = whole part of the vertical velocity
en_xf     = en_vyf+MAX_ENEMIES  ; position fractions
en_yf     = en_xf+MAX_ENEMIES
en_hit    = en_yf+MAX_ENEMIES   ; this frame's move: bit 7 wall, bit 6 floor
en_tick   = en_hit+MAX_ENEMIES  ; ATTACK: AI ticks since the attack began
        ert en_tick+MAX_ENEMIES>MEMW    ; LVL_BUF up to the MEMAC window
en_tgt    = pk_row+MAX_PICKUPS  ; FTargetUID: 0 the player, 1+n monster n
        ert en_tgt+MAX_ENEMIES>ANIM_RAM
en_ttm    = bm_r1+BM_MAX        ; FTargetTime (AI ticks)
        ert en_ttm+MAX_ENEMIES>MEMW
MAX_ATM   = 89                  ; g_monsters.pas: ticks before a new prey
ai_acc    dta 0
an_acc    dta 0
an_now    dta 0                 ; bit 7 = this step is an animation tick
an_cnt    dta 0                 ; animation ticks of this frame's logic steps

; per-type tables: zombie, imp, pinky (DEMON), caco, shotgun (SERG), baron, soul
en_run_lo  dta $14, $14, $85, $70, $14, $14, $70   ; RunVel/2 x 0.72
en_run_hi  dta $01, $01, $02, $01, $01, $01, $01   ; (3,3,7,4,3,3,4)
en_minpain dta 0, 0, 10, 0, 0, 30, 0
en_maxpain dta 10, 15, 20, 10, 10, 40, 10
en_flyer   dta 0, 0, 0, 1, 0, 0, 1
en_gate    dta 15, 15, 0, 15, 15, 7, 15                ; Random(16) / (8); 0 = never
en_fire_t  dta 3, 3, 3, 6, 3, 2, 0                     ; AI tick of the hit/shot
en_end_t   dta 6, 9, 9, 12, 6, 6, 0                    ; AI tick back to GO

; ============================================
; EN_AI_FRAME - once per frame before the enemy loop: AI tick or not
; ============================================
.proc en_ai_frame
        lda ai_acc
        clc
        adc #AI_STEP
        sta ai_acc
        ror ai_now              ; bit 7 = C: an AI tick (18/50 of the frames)
        lda an_acc
        clc
        adc #AN_STEP
        sta an_acc
        ror an_now              ; bit 7 = C: an animation tick (36/50)
        bpl ?r
        inc an_cnt              ; the frame's animation ticks (drawn once)
?r      rts
.endp

; ============================================
; EN_ANIMATE - TMonster.SetState's animation for the state, reset on a change,
; stepped once per AI tick (TAnimation.update; ma_spd counts those ticks). A non-looping DIE/MESS
; that has played turns the enemy into a corpse (a lost soul vanishes).
; X = enemy (preserved).
; ============================================
.proc en_animate
        lda en_act,x
        cmp #2
        beq ?die
alive   ldy en_state,x          ; (entry for an enemy known alive, en_act 1)
        lda st_anim,y
        bpl ?set                ; (always: ANIM_* < $80)
?die    lda en_gib,x            ; gibbed (1): MESS, else (0) DIE
        adc #ANIM_DIE-1         ; C=1 from the cmp #2 that branched here
        ert ANIM_MESS<>ANIM_DIE+1
?set    cmp en_anim,x
        beq ?step
        sta en_anim,x
        lda #0
        sta en_afr,x
        sta en_acnt,x
?step   bit ai_now          ; TMonster.Update steps it on AI ticks only (18 Hz)
        bpl ?r
        lda en_type,x           ; Y = type*8 + anim
        asl
        asl
        asl
        ora en_anim,x
        tay
        inc en_acnt,x
        lda en_acnt,x
        cmp ma_spd,y
        bcc ?r
        lda #0
        sta en_acnt,x
        inc en_afr,x
        lda en_afr,x
        cmp ma_n,y
        bcc ?r
        lda ma_flg,y            ; played: bit 0 = loop
        lsr
        bcc ?last
        lda #0
        sta en_afr,x
?r      rts
?last   dec en_afr,x            ; stays on the last frame
        lda en_act,x
        cmp #2
        bne ?r
        lda en_type,x           ; dying done: corpse (TMonster.Draw: no soul)
        cmp #EN_LOSTSOUL
        beq ?gone
        lda #3
        dta $2C                 ; bit abs: skips lda #0
?gone   lda #0
        sta en_act,x
        rts
st_anim dta ANIM_SLEEP, ANIM_GO, ANIM_GO, ANIM_GO, ANIM_ATTACK, ANIM_PAIN, ANIM_GO
        ert ES_SLEEP<>0 .or ES_GO<>1 .or ES_RUN<>2 .or ES_CLIMB<>3 .or ES_ATTACK<>4 .or ES_PAIN<>5
        ert ES_RUNOUT<>6
.endp

; ============================================
; EN_HURT - enemy X takes A damage (already off en_hp by the caller) from
; the player: TMonster.Damage pain build-up and wake-up; the hitter is its
; target now (BehaviourDamage). .mon: from monster en_by-1 (A = en_by,
; dm+1 = the damage). Preserves X, Y.
; ============================================
.proc en_hurt
        sta dm+1
        lda #0                  ; the player
mon     sta en_tgt,x
        lda #0
        sta en_ttm,x
        lda dm+1                ; (A was 0 here: no blood, or 256 droplets)
        jsr bl_hit              ; the blood: A = the damage (keeps X, Y)
        lda en_pain,x           ; if FPain = 0 then FPain := 3; FPain += damage
        bne ?add
        lda #3
?add    clc
dm      adc #0                  ; (patched: damage)
        bcc ?ok
        lda #$FF
?ok     sta en_pain,x
        lda en_state,x
        cmp #ES_PAIN
        beq ?r
        sta ?s+1                ; the state it had (0: asleep)
        sty ?y+1
        ldy en_type,x
        lda en_pain,x
        cmp en_minpain,y
?y      ldy #0                  ; (patched: Y back; ldy keeps C)
        bcc ?wake               ; FPain < MinPain: no pain
        lda #ES_PAIN
        sta en_state,x
        bne ?s                  ; (always: ES_PAIN <> 0)
?wake   lda en_state,x          ; a sleeper wakes up into GO
        bne ?r
        lda #ES_GO
        sta en_state,x
?s      lda #0                  ; (patched: the state it had) asleep: woken by
        bne ?r                  ; the hit, it calls as when it sees you
        jsr play_enemy_sight    ; keeps X
        ldy ?y+1                ; Y back
?r      rts
.endp

; ============================================
; EN_MOVE - every frame: velocity -> position with the map (8.8), gravity
; for walkers (as the player: g_Obj_Move), walls stop the walk. X = enemy.
; Sets en_hit (bit 7 wall, bit 6 on the floor).
; ============================================
.proc en_move
        lda #0
        sta en_hit,x
        ; --- horizontal: (en_vx:en_vxf) + knockback envelx ---
        lda en_xf,x
        clc
        adc en_vxf,x
        sta en_xf,x
        lda en_vx,x
        adc envelx,x
        beq ?vert               ; no whole pixel this frame
        sta ?dx+1
        bmi ?left
        lda en_x,x              ; probe: leading edge x+15
        clc
        adc #15
        jsr ?probe
        bne ?wall
        lda en_x,x
        clc
?dx     adc #0                  ; (patched: dx)
        sta en_x,x
        bcc ?vert
        inc enxhi,x
        bcs ?vert               ; (always)
?left   lda en_x,x              ; probe: leading edge x-1
        sec
        sbc #1
        jsr ?probe_l
        bne ?wall
        lda en_x,x
        clc
        adc ?dx+1
        sta en_x,x
        bcs ?vert               ; adding a negative: C=1 = no borrow
        dec enxhi,x
        bpl ?vert
        lda #0                  ; past the left edge: stop at 0
        sta en_x,x
        sta enxhi,x
?wall   lda #$80
        sta en_hit,x
        lda #0
        sta en_vx,x
        sta en_vxf,x
        sta envelx,x
?vert   ; --- vertical: walkers fall (PL_GRAV), flyers keep the AI's vy ---
        ldy en_type,x
        lda en_flyer,y
        bne ?vel
        lda en_vyf,x
        clc
        adc #PL_GRAV
        sta en_vyf,x
        lda envely,x
        adc #0
        bmi ?vy_ok
        cmp #>PL_MAXV           ; D2DF MAX_YV (2 floor probes below)
        bcc ?vy_ok
        bne ?vcap
        ldy en_vyf,x            ; whole = 10: the fraction decides (A kept)
        cpy #<PL_MAXV
        bcc ?vy_ok
?vcap   lda #<PL_MAXV
        sta en_vyf,x
        lda #>PL_MAXV
?vy_ok  sta envely,x
?vel    lda en_yf,x
        clc
        adc en_vyf,x
        sta en_yf,x
        lda envely,x
        adc #0                  ; carries out only on $FF+1 = 0: C=0 below
        beq ?floor              ; no whole pixel: still test the floor
        bmi ?up
        adc en_y,x              ; down: feet y += dy
        sta en_y,x
        bcc ?floor
        inc en_y_hi,x
?floor  lda en_x,x              ; floor probe at the feet (x+8, y)
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
        lda envely,x            ; a step of 8+ px may pass a whole cell:
        cmp #TH                 ; the cell 8 px higher first (rare)
        bcc ?f0
        bmi ?f0                 ; (rising)
        lda gt_py
        sec
        sbc #TH
        sta gt_py
        bcs ?f8a
        dec gt_py_hi
?f8a    jsr check_solid_or_platform16
        beq ?f8n
        lda gt_py               ; land on that cell's top
        sta en_y,x
        lda gt_py_hi
        sta en_y_hi,x
        jmp ?land
?f8n    lda en_y,x
        sta gt_py
        lda en_y_hi,x
        sta gt_py_hi
?f0     jsr check_solid_or_platform16
        beq ?r
        lda envely,x            ; moving up through a platform: ignore it
        bmi ?r
?land   lda en_y,x              ; landed: snap to the cell top, stop falling
        and #$100-TH
        sta en_y,x
        lda #0
        sta envely,x
        sta en_vyf,x
        sta en_yf,x
        lda en_hit,x
        ora #$40
        sta en_hit,x
?r      rts
?up     adc en_y,x              ; up: head probe first (y + dy - 24), C=0
        tay                     ; (Y = en_type no longer needed)
        lda en_y_hi,x
        adc #$FF
        sta gt_py_hi
        tya
        sec
        sbc #24
        sta gt_py
        bcs ?u1
        dec gt_py_hi
?u1     lda en_x,x
        clc
        adc #8
        sta gt_px
        lda enxhi,x
        adc #0
        sta gt_px_hi
        jsr check_solid16
        bne ?ceil
        lda envely,x            ; free: move up
        clc
        adc en_y,x
        sta en_y,x
        bcs ?r
        dec en_y_hi,x
        rts
?ceil   lda #0                  ; ceiling: stop rising
        sta envely,x
        sta en_vyf,x
?pr_r   rts
; ?probe: A = probe x lo (C = carry into hi): wall at chest (y-12) or knee
; (y-4)? Z=0 = blocked. ?probe_l: same after a subtract (C = no borrow).
?probe_l
        sta gt_px
        lda enxhi,x
        sbc #0
        jmp ?pr
?probe  sta gt_px
        lda enxhi,x
        adc #0
?pr     sta gt_px_hi
        lda en_y,x
        sec
        sbc #4
        sta gt_py
        lda en_y_hi,x
        sbc #0
        sta gt_py_hi
        jsr check_solid16
        bne ?pr_r
        lda gt_py
        sec
        sbc #8
        sta gt_py
        bcs ?pr2
        dec gt_py_hi
?pr2    jmp check_solid16
.endp

; ============================================
; EN_THINK - an AI tick for enemy X (TMonster.Update state machine).
; ============================================
.proc en_think
        lda en_ammo,x           ; if FAmmo < 0 then FAmmo += 1
        bpl ?am
        inc en_ammo,x
?am     lda envelx,x            ; knockback (Accel) decays by 1 toward 0
        beq ?st
        bmi ?an
        dec envelx,x
        bpl ?st                 ; (always: was > 0)
?an     inc envelx,x
?st     ldy en_state,x
        beq ?sl                 ; SLEEP: it looks for the player only
        inc en_ttm,x            ; FTargetTime += 1 (GO checks it within 58
        jsr tg_set              ; ticks of any state: no wrap)
        ldy en_state,x
?sl     lda ?lo,y
        sta ?j+1
        lda ?hi,y
        sta ?j+2
?j      jmp $FFFF               ; (patched: the state's handler)
?lo     dta <th_sleep, <th_go, <th_run, <th_climb, <th_attack, <th_pain, <th_runout
?hi     dta >th_sleep, >th_go, >th_run, >th_climb, >th_attack, >th_pain, >th_runout
.endp

; EN_BLOCKED - g_phys Blocked (MOVE_BLOCK): C=1 if enemy X's rect, 1 px
; ahead the way it moves (Vel + Accel), overlaps a BLOCKMON panel. Keeps X.
.proc en_blocked
        lda bm_n                ; most levels have few, some none: first
        beq ?no
        lda en_vx,x
        clc
        adc envelx,x            ; whole px: N = left; 0 = right if a fraction
        bmi ?l
        bne ?r
        lda en_vxf,x
        beq ?no                 ; standing: no step, no test
?r      inc en_x,x              ; 1 px right
        bne ?c
        inc enxhi,x
?c      txa
        tay
        jsr mon_cells           ; keeps X, Y
        lda en_x,x              ; back
        bne ?r1
        dec enxhi,x
?r1     dec en_x,x
        jmp ?test
?l      lda en_x,x              ; 1 px left
        bne ?l1
        dec enxhi,x
?l1     dec en_x,x
        txa
        tay
        jsr mon_cells
        inc en_x,x              ; back
        bne ?test
        inc enxhi,x
?test   ldy bm_n
?lp     dey
        bmi ?no
        lda mc0                 ; [mc0, mc1) x [mr0, mr1) against the panel
        cmp bm_c1,y
        bcs ?lp
        lda bm_c0,y
        cmp mc1
        bcs ?lp
        lda mr0
        cmp bm_r1,y
        bcs ?lp
        lda bm_r0,y
        cmp mr1
        bcs ?lp
        sec                     ; overlaps (C=0 from the cmp)
        rts
?no     clc
        rts
.endp

; EN_TO_RUNOUT - GO/RUN at a BLOCKMON panel: Turn, FSleep 40, RUNOUT
.proc en_to_runout
        lda en_dir,x
        eor #1
        sta en_dir,x
        lda #40
        sta en_sleep,x
        lda #ES_RUNOUT
        sta en_state,x
        rts
.endp

; RUNOUT: out of the panel FSleep drops to 0, then to -18: GO (turning at
; a wall or a panel); walk at RunVel meanwhile
.proc th_runout
        jsr en_blocked
        ror ?blk                ; bit 7 = MOVE_BLOCK
        lda en_sleep,x
        bit ?blk
        bmi ?dec                ; still in it: FSleep counts on
        cmp #1
        bmi ?dec                ; FSleep <= 0 (40 .. -18: signed in a byte)
        lda #0
?dec    sec
        sbc #1
        sta en_sleep,x
        cmp #$100-18
        jne en_walk
        lda #0
        sta en_sleep,x
        lda #ES_GO
        sta en_state,x
        lda en_hit,x            ; N = wall
        jmi en_turn
        bit ?blk
        jmi en_turn
        jmp en_walk
?blk    dta 0
.endp

; SLEEP: look every 18 AI ticks (1 s), only the way it faces (g_Look)
.proc th_sleep
        inc en_sleep,x
        lda en_sleep,x
        cmp #18
        bcc ?r
        lda #0
        sta en_sleep,x
        jsr tg_player           ; (its target: 0, the player)
        jsr en_faces
        bcc ?r
        jsr en_look
        bcc ?r
        lda #ES_GO
        sta en_state,x
        jmp play_enemy_sight    ; preserves X
?r      rts
.endp

; GO: face the target, shoot at random, run around when close, jump at
; walls and up towards a target above, walk at RunVel
.proc th_go
        jsr en_blocked          ; at a BLOCKMON panel: turn, RUNOUT
        jcs en_to_runout
        lda en_ttm,x            ; the target gone or FTargetTime > MAX_ATM:
        cmp #MAX_ATM+1          ; findNewPrey
        bcs ?prey
        lda tg_ok
        bne ?tg
?prey   jsr en_prey
?tg     jsr en_overlap          ; hitboxes touch: kick (melee / point blank)
        bcc ?nokick
        lda #0                  ; FTargetTime := 0
        sta en_ttm,x
        jsr en_kick
        lda en_state,x
        cmp #ES_GO
        jne ?r
?nokick jsr en_face_target      ; A = |sx| (cut to a byte)
        sta ?ax+1
        ldy en_type,x           ; shoot: random gate, |sx| > |sy|
        lda en_gate,y
        beq ?noshot
        and RANDOM
        bne ?noshot
        lda en_ammo,x
        bmi ?noshot
        jsr en_dist_y           ; A = |sy| (cut)
?ax     cmp #0                  ; (patched: |sx|)
        bcs ?noshot
        jsr en_look
        jcs en_start_attack
?noshot lda ?ax+1               ; |sx| < 40 (original): random run, 15 ticks
        cmp #EN_NEAR
        bcs ?far
        lda #15
        sta en_sleep,x
        lda #ES_RUN
        sta en_state,x
        lda RANDOM
        and #1
        sta en_dir,x
        jmp en_walk
?far    lda en_hit,x            ; wall: press triggers there (MONSTERPRESS),
        bpl ?nowall             ; if one fires wait; else walkers on the floor
        jsr trig_mon_press      ; jump into CLIMB
        bcs ?r
        ldy en_type,x
        lda en_flyer,y
        bne ?fly
        lda en_hit,x
        and #$40
        beq ?wk                 ; bit 6: on the floor
        lda #ES_CLIMB
        sta en_state,x
        bne ?jmp                ; (always: A = ES_CLIMB)
?nowall ldy en_type,x
        lda en_flyer,y
        beq ?walker
?fly    jsr en_fly_vy           ; flyers: vy toward the target height
        jmp en_walk
?walker lda en_hit,x            ; target 40 px above and on the floor: 1/4
        and #$40
        beq ?wk
        jsr en_target_above
        bcc ?wk
        lda RANDOM
        and #3
        bne ?wk
?jmp    jsr en_jump
?wk     jmp en_walk
?r      rts
.endp

; ATTACK (and SHOOT): slow down, hit/shoot at en_fire_t, GO at en_end_t.
; Lost soul: a charge - bites (15) while touching, GO on a hit or a wall.
.proc th_attack
        lda en_type,x
        cmp #EN_LOSTSOUL
        bne ?brake
        lda #15                 ; g_Weapon_Hit: whatever touches; a hit: GO
        jsr en_bite
        bcc ?ls_w
?go     lda #0
        sta en_atk,x            ; walk sprite again
        sta envely,x            ; (a charging soul stops)
        sta en_vyf,x
        lda #ES_GO
        sta en_state,x
        rts
?ls_w   lda en_hit,x            ; N = wall
        bmi ?go
        rts
?brake  lda en_vx,x             ; Vel.X := z_dec(Vel.X, 1): brake 0.36 px
        bmi ?neg                ; (vx < 0 is not zero: no zero test)
        ora en_vxf,x
        beq ?t
        lda en_vxf,x
        sec
        sbc #$5C
        sta en_vxf,x
        lda en_vx,x
        sbc #0
        bpl ?sv
        bmi ?z
?neg    lda en_vxf,x
        clc
        adc #$5C
        sta en_vxf,x
        lda en_vx,x
        adc #0
        bmi ?sv
?z      lda #0
        sta en_vxf,x
?sv     sta en_vx,x
?t      inc en_tick,x
        ldy en_type,x
        lda en_tick,x
        cmp en_fire_t,y
        bne ?end
        jsr en_fire             ; the hit / the shot (X kept)
        ldy en_type,x
        lda en_tick,x
?end    cmp en_end_t,y
        bcs ?go
        rts
.endp

; PAIN: FPain decays by 5 a tick; at MinPain: GO, no shot for 9 ticks
.proc th_pain
        ldy en_type,x
        lda en_pain,x
        cmp en_maxpain,y
        bcc ?dec
        lda en_maxpain,y
?dec    sec
        sbc #5
        bcs ?st
        lda #0
?st     sta en_pain,x
        cmp en_minpain,y
        beq ?out
        bcs ?r
?out    lda #0
        sta en_pain,x
        lda #$F7                ; FAmmo := -9
        sta en_ammo,x
        lda #ES_GO
        sta en_state,x
?r      rts
.endp

; ============================================
; Helpers (X = enemy, preserved). sx/sy = target - enemy (tg_set: both
; measured at x and at the feet).
; ============================================

; EN_SX - A = hi, en_t0 = lo of sx (16-bit), N = sign
.proc en_sx
        lda tg_x
        sec
        sbc en_x,x
        sta en_t0
        lda tg_xh
        sbc enxhi,x
        rts
.endp

; EN_SY - A = hi, en_t0 = lo of sy (16-bit), N = sign
.proc en_sy
        lda tg_y
        sec
        sbc en_y,x
        sta en_t0
        lda tg_yh
        sbc en_y_hi,x
        rts
.endp

; EN_ABS - |(A:en_t0)| cut to a byte -> A (255 = far). Keeps X, Y.
.proc en_abs
        bpl ?pos
        cmp #$FF
        bne ?far
        lda en_t0
        beq ?far                ; -256
        eor #$FF
        adc #0                  ; +1: C=1 from the cmp #$FF that matched
        rts
?pos    bne ?far
        lda en_t0
        rts
?far    lda #$FF
        rts
.endp

; EN_FACE_TARGET - face the target; A = |sx| (byte). Clobbers Y.
.proc en_face_target
        jsr en_sx
        tay                     ; hi of sx (en_t0 = lo stays)
        asl @                   ; C = sign: player left
        lda #0
        rol @                   ; dir 1 = left
        sta en_dir,x
        tya                     ; N = sign for en_abs
        jmp en_abs
.endp

; EN_DIST_Y - A = |sy| (byte)
.proc en_dist_y
        jsr en_sy
        jmp en_abs
.endp

; EN_FACES - C=1 if the enemy faces the target (g_Look's side test)
.proc en_faces
        jsr en_sx               ; N = target left
        bmi ?l
        lda #0                  ; target right (or same x): C = (dir = 0)
        cmp en_dir,x
        rts
?l      lda en_dir,x            ; target left: C = (dir <> 0)
        cmp #1
        rts
.endp

; EN_OVERLAP - C=1 if the hitboxes touch: |sx| < 16 and |sy| < 24
.proc en_overlap
        lda tg_ok               ; a dead target is none (D2DF GetPos: not
        beq ?no                 ; alive): no kick
        jsr en_sx
        jsr en_abs
        cmp #16
        bcs ?no
        jsr en_sy
        jsr en_abs
        eor #$FF                ; C = (A < 24) = (~A >= 256-24)
        cmp #256-24
        rts
?no     clc
        rts
.endp

; EN_TARGET_ABOVE - C=1 if the target stands more than EN_ABOVE px higher
.proc en_target_above
        jsr en_sy               ; sy < -EN_ABOVE
        bpl ?no
        cmp #$FF
        bne ?yes                ; < -256
        lda en_t0
        cmp #256-EN_ABOVE       ; C=0: lo < 256-EN_ABOVE = sy < -EN_ABOVE
        bcs ?no
?yes    sec
        rts
?no     clc
        rts
.endp

; CLIMB: after a wall jump; at the top (vy >= 0) back to GO, still at the
; wall: turn and run
.proc th_climb
        lda envely,x
        bmi en_walk
        lda #ES_GO
        sta en_state,x
        lda en_hit,x            ; N = wall
        bmi ?t
        jsr en_blocked          ; or a BLOCKMON panel
        bcc en_walk
?t      lda #15
        sta en_sleep,x
        lda #ES_RUN
        sta en_state,x
        bne en_turn             ; (always: A = ES_RUN)
.endp

; RUN: a random dash; back to GO after en_sleep ticks or at a wall
.proc th_run
        jsr en_blocked          ; at a BLOCKMON panel: turn, RUNOUT
        jcs en_to_runout
        dec en_sleep,x
        beq ?go
        lda en_hit,x            ; N = wall
        bpl en_walk
        lda envely,x
        bne en_walk
?go     lda #ES_GO
        sta en_state,x
        lda en_hit,x
        bpl en_walk
.endp
        ert *<>en_turn          ; at a wall: falls into en_turn, then en_walk

; EN_TURN - the other way, then walk (falls into en_walk)
.proc en_turn
        lda en_dir,x
        eor #1
        sta en_dir,x
.endp
        ert *<>en_walk

; EN_WALK - Vel.X := +-RunVel by en_dir (GO, RUN, CLIMB)
.proc en_walk
        ldy en_type,x
        lda en_dir,x
        bne ?l
        lda en_run_lo,y
        sta en_vxf,x
        lda en_run_hi,y
        sta en_vx,x
        rts
?l      lda #0                  ; -(run): 16-bit negate
        sec
        sbc en_run_lo,y
        sta en_vxf,x
        lda #0
        sbc en_run_hi,y
        sta en_vx,x
        rts
.endp

; EN_JUMP - Vel.Y := -Jump (10, as the player's jump)
.proc en_jump
        lda #<[-PL_JUMPV]
        sta en_vyf,x
        lda #<[[-PL_JUMPV]>>8]
        sta envely,x
        rts
.endp

; EN_FLY_VY - flyers: Vel.Y := Sign(sy)*4 (1.44 px/frame) outside +-8 px
.proc en_fly_vy
        jsr en_dist_y
        cmp #EN_FLY_DZ+1
        bcs ?sgn
        lda #0
        sta en_vyf,x
        sta envely,x
        rts
?sgn    jsr en_sy               ; N = sign
        bmi ?up
        lda #$70                ; +$0170
        sta en_vyf,x
        lda #$01
        sta envely,x
        rts
?up     lda #$90                ; -$0170 = $FE90
        sta en_vyf,x
        lda #$FE
        sta envely,x
        rts
.endp

; EN_KICK - hitboxes touch in GO (TMonster.kick): pinky and imp bite/claw
; (ATTACK), baron and caco shoot point blank, the rest nothing
.proc en_kick
        lda en_type,x
        cmp #EN_PINKY
        beq ?melee
        cmp #EN_IMP
        beq ?melee
        cmp #EN_BARON
        beq ?shoot
        cmp #EN_CACO
        bne ?r
?shoot  lda en_ammo,x
        bmi ?r
        jsr en_look
        bcc ?r
        bcs en_start_attack     ; (always)
?melee  lda #11                 ; en_atk 11 = melee (en_fire), shoot sprite
        bne en_start_attack.atk ; (always)
?r      rts
.endp

; EN_START_ATTACK - enter ATTACK (shoot sprite); .atk: A = en_atk (10 shot,
; 11 melee). A lost soul charges at 16 px/tick (5.76) along its main axis.
.proc en_start_attack
        lda #10
atk     sta en_atk,x
        lda #0
        sta en_tick,x
        lda #ES_ATTACK
        sta en_state,x
        lda en_type,x
        cmp #EN_LOSTSOUL
        bne ?r
        lda en_dir,x            ; charge 5.76 px/frame toward the player
        beq ?rt                 ; (clobbers Y: every caller reloads it)
        ldy #$FA                ; -$05C3 = $FA3D
        lda #$3D
        bne ?vx                 ; (always: A = $3D)
?rt     ldy #$05
        lda #$C3
?vx     sta en_vxf,x
        tya
        sta en_vx,x
        jmp en_fly_vy
?r      rts
.endp

; EN_FIRE - the hit or the shot of an attack (X kept)
.proc en_fire
        lda en_atk,x
        cmp #11
        beq ?melee
        lda en_type,x
        cmp #EN_ZOMBIE
        beq ?gun
        cmp #EN_SHOTGUN
        beq ?gun
        cmp #EN_PINKY
        beq ?melee
        jsr spawn_eproj         ; imp, caco, baron fire balls (clobbers X)
        ldx zzidx
        lda #SFX_FIRSHT
        jmp play_sfx            ; preserves X
?gun    jsr en_look             ; one gun shot / ten pellets of 3 at the
        bcc ?r                  ; target
        ldy en_type,x
        lda en_gun_dmg,y
        jsr en_gun
        bcs ?snd                ; (always: en_gun ends C=1)
?melee  lda #15                 ; g_Weapon_Hit: whatever touches, 15
        jsr en_bite
        bcc ?r
?snd    ldy en_type,x
        lda en_atk_sfx,y
        jmp play_sfx
?r      rts
.endp
en_gun_dmg dta 3, 0, 0, 0, 30, 0, 0          ; zombie 1x3, shotgun guy 10x3
en_atk_sfx dta SFX_PISTOL, SFX_CLAW, SFX_SGTATK, SFX_FIRSHT, SFX_SHOTGUN, SFX_FIRSHT, SFX_SKLATK
en_t0   dta 0

; EN_DXY - A = |en_x,y - en_x,x| cut to a byte (en_abs). Keeps X, Y.
.proc en_dxy
        lda en_x,y
        sec
        sbc en_x,x
        sta en_t0
        lda enxhi,y
        sbc enxhi,x
        jmp en_abs
.endp

; EN_DYY - A = |en_y,y - en_y,x| cut to a byte. Keeps X, Y.
.proc en_dyy
        lda en_y,y
        sec
        sbc en_y,x
        sta en_t0
        lda en_y_hi,y
        sbc en_y_hi,x
        jmp en_abs
.endp

; The infighting (D2DF targets) in the RAM the ANTIC sky's last display list
; had, past the triggers' tr_p0 run (trig_load copies up to there)
fight_save = *
        org tr_p0+TR_MAX
; ============================================
; Targets (X = enemy = zzidx, update_enemies; X kept). en_tgt 0: the player
; ============================================

en_by   dta 0                   ; the hitting monster + 1 (en_hurt.mon)
pr_t    dta 0                   ; en_prey: the sum, the nearest so far
pr_bl   dta 0
pr_bh   dta 0

; EN_PREY - findNewPrey (BH_NORMAL, one player): the player while alive,
; else the nearest alive monster that is no friend (|dx| + |dy|, each cut to
; 255); none: the dead player, FTargetTime = MAX_ATM. Sets tg_* (falls
; into tg_set).
.proc en_prey
        lda #0
        sta en_ttm,x
        sta en_tgt,x
        lda zphp
        bne ?f                  ; alive: the player (tg_set)
        lda #$FF
        sta pr_bh
        ldy num_en
?lp     dey
        bmi ?end
        lda en_act,y
        cmp #1
        bne ?lp
        cpy zzidx               ; itself
        beq ?lp
        jsr en_friend
        bcs ?lp
        jsr en_dxy              ; |dx| (cut)
        sta pr_t
        jsr en_dyy
        clc
        adc pr_t
        sta pr_t
        lda #0
        rol @                   ; the sum's bit 8
        cmp pr_bh
        bcc ?new
        bne ?lp
        lda pr_t
        cmp pr_bl
        bcs ?lp
        lda pr_bh               ; (the same bit 8)
?new    sta pr_bh
        lda pr_t
        sta pr_bl
        iny                     ; the target: 1+n
        tya
        sta en_tgt,x
        dey
        bpl ?lp                 ; (always: Y < 66)
?end    lda en_tgt,x
        bne ?f
        lda #MAX_ATM            ; none: FTargetTime = MAX_ATM
        sta en_ttm,x
?f
.endp
        ert *<>tg_set           ; falls into tg_set

; TG_SET - the target's x, y into tg_*, tg_ok <> 0 if alive. Clobbers Y.
.proc tg_set
        ldy en_tgt,x
        beq tg_player
        lda en_x-1,y
        sta tg_x
        lda enxhi-1,y
        sta tg_xh
        lda en_y-1,y
        sta tg_y
        lda en_y_hi-1,y
        sta tg_yh
        lda en_act-1,y          ; alive: 1
        cmp #1
        beq ?ok
        lda #0
?ok     sta tg_ok
        rts
.endp

; TG_PLAYER - the player as the target (tg_ok = its health)
.proc tg_player
        lda zpx
        sta tg_x
        lda zpx_hi
        sta tg_xh
        lda zpy
        sta tg_y
        lda zpy_hi
        sta tg_yh
        lda zphp
        sta tg_ok
        rts
.endp

; EN_FRIEND - C=1 if monsters X and Y spare each other (IsFriend: the same
; type, not zombies or sergeants). Keeps X, Y.
.proc en_friend
        lda en_type,y
        cmp en_type,x
        bne ?no
        and #3                  ; zombie 0, sergeant 4: the only types & 3 = 0
        cmp #1                  ; C = (type & 3 <> 0)
        rts
?no     clc
        rts
.endp
        ert EN_ZOMBIE<>0 .or EN_SHOTGUN<>4 .or EN_IMP<>1 .or EN_PINKY<>2
        ert EN_CACO<>3 .or EN_BARON<>5 .or EN_LOSTSOUL<>6

; EN_MDMG - monster en_by-1 hits monster X for A (TMonster.Damage): the
; kill, or pain / wake-up with the hitter as its target. Keeps X.
.proc en_mdmg
        sta en_hurt.dm+1
d       lda en_hp,x             ; (entry: the damage in en_hurt.dm+1)
        sec
        sbc en_hurt.dm+1
        bcs ?h
        lda #0
?h      sta en_hp,x
        jeq hs_damage_enemy.kill        ; the death (keeps X)
        jsr bl_mway             ; the blood away from the hitter
        lda en_by
        jmp en_hurt.mon
.endp

; EN_BITE - g_Weapon_Hit(@FObj, A): the first alive monster touching X
; (|dx| < 16, |dy| < 24) that is no friend takes A, else the player if it
; touches. C=1: a hit.
.proc en_bite
        sta ?d
        ldy num_en
?lp     dey
        bmi ?pl
        lda en_act,y
        cmp #1
        bne ?lp
        cpy zzidx               ; itself
        beq ?lp
        jsr en_dxy
        cmp #16
        bcs ?lp
        jsr en_dyy
        cmp #24
        bcs ?lp
        jsr en_friend
        bcs ?lp
        tya                     ; the victim
        tax
        lda ?d
        jmp en_hit_by
?pl     jsr tg_player
        jsr en_overlap
        bcc ?r
        jsr bl_pfrom            ; the blood away from the biter
        lda ?d
        jsr player_take_damage  ; preserves X, Y
        sec
?r      rts
?d      dta 0
.endp

; EN_HIT_BY - X (the victim) takes A from monster zzidx; X = zzidx, C=1
.proc en_hit_by
        ldy zzidx
        iny
        sty en_by
        jsr en_mdmg
        ldx zzidx
        sec
        rts
.endp

; EP_MON - enemy projectile X against the monsters: the first alive one
; whose box (mon_hw, mon_h) the shot's 8x8 meets, not its owner nor a
; friend of it, takes the hit and targets the owner. C=1: a hit; C=0: Z=1
; if the player is dead.
.proc ep_mon
        ldy num_en
        bpl ?lp                 ; (always: num_en <= MAX_ENEMIES)
?no     lda zphp                ; C=0, Z: the player is dead
        clc
        rts
?lp     dey
        bmi ?no
        lda en_act,y
        cmp #1
        bne ?lp
        lda eproj_x,x           ; dx = shot - monster, a signed byte
        sec
        sbc en_x,y
        sta en_t0
        lda eproj_xh,x
        sbc enxhi,y
        beq ?xp
        cmp #$FF
        bne ?lp
        lda en_t0
        bpl ?lp
        bmi ?xc                 ; (always)
?xp     lda en_t0
        bmi ?lp
?xc     sta ?dx
        clc                     ; |dx| < 40 (the widest box: caco), first
        adc #40
        cmp #80
        bcs ?lp
        lda eproj_y,x           ; dy = shot - feet, a signed byte
        sec
        sbc en_y,y
        sta en_t0
        lda eproj_y_hi,x
        sbc en_y_hi,y
        beq ?yp
        cmp #$FF
        bne ?lp
        lda en_t0
        bpl ?lp
        bmi ?yc                 ; (always)
?yp     lda en_t0
        bmi ?lp
?yc     sta ?dy
        jsr ?box
        bcc ?lp
        tya
        cmp eproj_own,x
        beq ?lp                 ; its owner
        stx ?x+1
        lda eproj_own,x         ; (no ldx abs,x on a 6502)
        tax
        jsr en_friend           ; keeps X, Y
?x      ldx #0                  ; (patched: the shot)
        bcs ?lp                 ; a friend: it flies through
        lda eproj_own,x
        adc #1                  ; (C=0: the bcs not taken)
        sta en_by
        lda eproj_dmg,x
        sta en_hurt.dm+1
        stx ?x2+1
        tya
        tax
        jsr en_mdmg.d
?x2     ldx #0                  ; (patched: the shot)
        sec
        rts
; ?BOX - C=1 if the shot (x..x+7, y-4..y+3) meets monster Y's box (centre
; en_x+8 +-hw, feet-h..feet-1): dx + hw - 1 <= 2hw + 6, dy + h + 3 <= h + 6
?box    stx ?xr+1               ; X = the monster's type
        ldx en_type,y
        lda ?dx
        clc
        adc mon_hw,x
        sec
        sbc #1
        sta ?t
        lda mon_hw,x
        asl @                   ; (C=0: hw < 128)
        adc #6
        cmp ?t
        bcc ?xr                 ; apart (C=0)
        lda ?dy
        clc
        adc mon_h,x
        clc
        adc #3
        sta ?t
        lda mon_h,x
        clc
        adc #6
        cmp ?t                  ; C = the boxes meet
?xr     ldx #0                  ; (patched: the shot)
        rts
?dx     dta 0
?dy     dta 0
?t      dta 0
.endp

; Spawn enemy projectile
; Input: X = enemy index (en_x/enxhi/en_y/en_dir used for position)
.proc spawn_eproj
        txa                    ; Y = enemy index (the search below uses A, X)
        tay
        ; Find free slot
        ldx #0
?f      lda eproj_a,x
        beq ?ok
        inx
        cpx #MAX_EPROJ
        bne ?f
        rts                    ; no free slot
?ok     lda #1
        sta eproj_a,x
        tya
        sta eproj_own,x
        ; Position from enemy + offset in fire direction
        lda en_dir,y
        bne ?sp_left
        ; Facing right: X + 12
        lda en_x,y
        clc
        adc #12
        sta eproj_x,x
        lda enxhi,y
        adc #0
        sta eproj_xh,x
        lda #6                 ; velocity right: 16 px/tick /2 x 0.72 = 5.76
        bne ?sp_vx             ; (always: A = 6)
?sp_left
        ; Facing left: X - 4
        lda en_x,y
        sec
        sbc #4
        sta eproj_x,x
        lda enxhi,y
        sbc #0
        sta eproj_xh,x
        lda #$FA               ; velocity left (-6)
?sp_vx  sta eproj_vx,x
        lda en_y,y
        sec
        sbc #14                ; chest height
        sta eproj_y,x
        lda en_y_hi,y
        sbc #0                 ; 16-bit Y
        sta eproj_y_hi,x
        ; Damage and sprite by type (Y = enemy still). Only imp (1), caco (3)
        ; and baron (5) fire (en_fire): type/2 = 0, 1, 2.
        lda en_type,y
        lsr
        tay
        lda ep_dmg_tab,y
        sta eproj_dmg,x
        lda ep_spr_tab,y
        sta eproj_spr,x
        rts
        ert EN_IMP/2<>0 .or EN_CACO/2<>1 .or EN_BARON/2<>2
ep_dmg_tab dta 5, 20, 40       ; imp, caco, baron (g_weapons.pas)
ep_spr_tab dta SPR_IMP_FIRE1, SPR_CACO_FIRE1, SPR_BARON_FIRE1
.endp
        ert *>lf_c0
        org bl_lo_end                   ; the third display list's RAM, after
                                        ; blood.asm's hit entries
; EN_GUN - g_Weapon_gun at the target, the line clear (en_look): the
; nearest alive monster on the way that is no friend takes A (x on the
; target's side and nearer, feet inside the line's y span +-14), else the
; target. Ends C=1.
.proc en_gun
        sta ?d
        jsr en_sx               ; the target's side and distance
        sta ?sd                 ; bit 7: left
        jsr en_abs
        sta ?b                  ; the nearest so far: the target (cut)
        lda #0
        sta ?v                  ; the victim + 1, 0: the target
        lda en_y,x              ; the y span: min - 14 .. max + 14
        cmp tg_y
        lda en_y_hi,x
        sbc tg_yh
        bcs ?sl                 ; the shooter's y is the max
        lda en_y,x
        ldy en_y_hi,x
        jsr ?lo
        lda tg_y
        ldy tg_yh
        jsr ?hi
        jmp ?go
?sl     lda tg_y
        ldy tg_yh
        jsr ?lo
        lda en_y,x
        ldy en_y_hi,x
        jsr ?hi
?go     ldy num_en
?lp     dey
        bmi ?hit
        lda en_act,y
        cmp #1
        bne ?lp
        cpy zzidx               ; itself
        beq ?lp
        lda en_x,y              ; dx = monster - shooter
        sec
        sbc en_x,x
        sta en_t0
        lda enxhi,y
        sbc enxhi,x
        eor ?sd                 ; on the target's side: the signs agree
        bmi ?lp
        eor ?sd                 ; (dx hi again, N its sign)
        jsr en_abs
        cmp ?b
        bcs ?lp                 ; not nearer
        sta ?t
        lda ?yl                 ; lo < y
        cmp en_y,y
        lda ?yl+1
        sbc en_y_hi,y
        bcs ?lp
        lda en_y,y              ; y < hi
        cmp ?yh
        lda en_y_hi,y
        sbc ?yh+1
        bcs ?lp
        jsr en_friend
        bcs ?lp
        lda ?t
        sta ?b
        iny
        sty ?v
        dey
        bpl ?lp                 ; (always: Y < MAX_ENEMIES)
?hit    lda ?d
        ldy ?v
        bne ?mon
        ldy en_tgt,x
        bne ?mon                ; the target is a monster
        jsr bl_pfrom            ; the blood away from the shooter
        lda ?d
        jsr player_take_damage  ; keeps X, Y
        sec
        rts
?mon    dey                     ; (1+n -> n; A = ?d)
        tya
        tax
        jmp en_hit_by
?lo     sec                     ; ?yl = A:Y - 14
        sbc #14
        sta ?yl
        tya
        sbc #0
        sta ?yl+1
        rts
?hi     clc                     ; ?yh = A:Y + 14
        adc #14
        sta ?yh
        tya
        adc #0
        sta ?yh+1
        rts
?d      dta 0
?sd     dta 0
?b      dta 0
?v      dta 0
?t      dta 0
?yl     dta 0,0
?yh     dta 0,0
.endp

; ============================================
; EN_LOOK - line of sight enemy -> target (g_Look's g_TraceVector): 2^k
; samples along the line between the two centres, k the least with every
; step <= 8 px (a cell: no wall or floor is jumped over), each a map lookup
; (a new cell only); C=1 clear.
; ============================================
lk_dead clc                     ; en_look's dead-target exit, out of line
        rts                     ; (2026-11-02 6502-cycles-layout.md "rare case out of line")
.proc en_look
        lda tg_ok               ; a dead target (D2DF GetPos): not seen, no
        beq lk_dead             ; wake-up, no shot
        jsr en_sx               ; dx, dy into the loop's adc operands (the
        sta ?dxh+1              ; reader's place is the producer's
        ldy en_t0               ; destination: no copy)
        sty ?dxl+1
        jsr ?q8
        sta ?q
        jsr en_sy
        sta ?dyh+1
        ldy en_t0
        sty ?dyl+1
        jsr ?q8
        ora ?q                  ; bit length k of (qx | qy) = of max(qx, qy)
        bne ?far
        sec                     ; k = 0: within a cell, nothing between
        rts
?far    ldy #0                  ; 2^k samples (lk_n = 2^k - 1 steps), the step
        sty lk_n                ; d / 2^k = d << (8-k) in 8.8: <= 8 px, a cell
        ldy #8
?b      sec
        rol lk_n
        dey
        lsr @
        bne ?b
?sh     asl ?dxl+1              ; Y = 8 - k >= 1 shifts
        rol ?dxh+1
        asl ?dyl+1
        rol ?dyh+1
        dey
        bne ?sh
        lda ?dxh+1              ; the steps' sign bytes, once (a constant of
        and #$80                ; every pass goes into the operand)
        beq ?xs
        lda #$FF
?xs     sta ?sx+1
        lda ?dyh+1
        and #$80
        beq ?ys
        lda #$FF
?ys     sta ?sy+1
        lda en_x,x              ; start at the enemy centre (x+8, y-14)
        clc
        adc #8
        sta gt_px
        lda enxhi,x
        adc #0
        sta gt_px_hi
        lda en_y,x
        sec
        sbc #14
        sta gt_py
        lda en_y_hi,x
        sbc #0
        sta gt_py_hi
        lda #$80                ; the fractions start at .5 (their own lda #)
        sta ?xf+1
        sta ?yf+1
        lda #1                  ; no cell yet (a coordinate & $F8 is never 1)
        sta ?k0+1
        sta ?k2+1
?lp
?xf     lda #0                  ; x += step (8.8, sign-extended)
        clc
?dxl    adc #0
        sta ?xf+1
        lda gt_px
?dxh    adc #0
        sta gt_px
?sx     lda #0                  ; (patched: the x step's sign)
        adc gt_px_hi
        sta gt_px_hi
?yf     lda #0                  ; y += step
        clc
?dyl    adc #0
        sta ?yf+1
        lda gt_py
?dyh    adc #0
        sta gt_py
?sy     lda #0                  ; (patched: the y step's sign)
        adc gt_py_hi
        sta gt_py_hi
        ; The sample before's map cell was clear (only a clear one goes on):
        ; no map look in it. A cell is (lo & $F8, hi); a step < 256 px (diff /
        ; 32, the map < 1024 px) changes lo & $F8 whenever it changes hi: the
        ; lo keys suffice. A new row sets the row's bank and pointer (lk_row),
        ; a new column in it is one read (lk_col): fable-skill-atari "cached
        ; by its last key".
        lda gt_py
        and #$F8
?k2     cmp #0
        beq ?rs
        sta ?k2+1
        jsr lk_row              ; C=1: off the map
        bcs ?no
        lda gt_px
        and #$F8
        bcc ?st                 ; (always)
?rs     lda gt_px
        and #$F8
?k0     cmp #0
        beq ?same
?st     sta ?k0+1
        jsr lk_col              ; Z=0: a wall (keeps X)
        bne ?no
?same   dec lk_n
        bne ?lp
        sec
        rts
?no     clc
        rts
; ?Q8 - A = hi (N), en_t0 = lo of d (|d| < 1024) -> A = (d < 0 ? ~d : d)
; >> 3 = (|d| - (d < 0)) / 8: k from it keeps every step <= 8 px
?q8     tay
        bpl ?p
        eor #$FF
        sta ?h
        lda en_t0
        eor #$FF
        jmp ?c
?p      sty ?h
        lda en_t0
?c      lsr ?h                  ; hi <= 3: its bits into A's top three
        ror @
        lsr ?h
        ror @
        lsr ?h
        ror @
        rts
?h      dta 0
?q      dta 0
lk_n    dta 0
.endp
        ert *>tr_act
        org fight_save

