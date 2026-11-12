;==============================================
; DOOM2D - Triggers, ported from Doom 2D Forever (g_triggers.pas): doors,
; traps, lifts, teleports, switches (PRESS/ON/OFF/ONOFF), secrets, the exit
; triggers.asm
;
; The level's triggers come from tools/d2df2map.py (trigger_block): rects in
; map cells, the door/switch panels' cells with both of their tiles (in
; VRAM_TPC), the lifts. Everything runs once per 36 Hz tick (an_now) in the
; order of g_Triggers_Update; activation (tr_activate) is ActivateTrigger.
;==============================================

TR_MAX    = 76                  ; triggers, door panels, switch panels, lifts,
PL_MAX    = 32                  ; PRESS target entries (d2df2map TR_MAX ...)
DP_MAX    = 48
SP_MAX    = 24
LF_MAX    = 12
BM_MAX    = 24                  ; BLOCKMON panels (monsters turn back at them)
VRAM_TPC  = $031000             ; panel cell lists: n, then col,row,alt,def

TT_EXIT      = 1                ; TRIGGER_* (mapdef.inc)
TT_TELEPORT  = 2
TT_OPENDOOR  = 3
TT_CLOSEDOOR = 4
TT_DOOR      = 5
TT_DOOR5     = 6
TT_CLOSETRAP = 7
TT_TRAP      = 8
TT_PRESS     = 9
TT_SECRET    = 10
TT_LIFTUP    = 11
TT_LIFTDOWN  = 12
TT_LIFT      = 13
TT_ON        = 15
TT_OFF       = 16
TT_ONOFF     = 17
TT_SOUND     = 18
TT_SPAWNITEM = 20
TT_LAST      = 20

AC_PCOLL  = 1                   ; ACTIVATE_* bits
AC_MCOLL  = 2
AC_PPRESS = 4
AC_MPRESS = 8
AC_SHOT   = 16
AC_NOMON  = 32

TF_EN     = 1                   ; tr_flag: enabled, d2d (whole door / lift
TF_D2D    = 2                   ; group), silent, ext_random, teleport
TF_SILENT = 4                   ; direction (bits 4-5: 1 left, 2 right,
TF_RAND   = 8                   ; 3 reverse)
TF_LONG   = 16                  ; PRESS..ONOFF: tr_p2 = wait / 16 (tr_dt divides)

; --- The level's trigger block, RAM part (13 sectors), copied in 5 runs to
; free RAM below the code (the gaps after the sky display lists, pages 4-8)
tr_c0     = $1246               ; rect in cells: [c0, c1) x [r0, r1)
tr_r0     = tr_c0+TR_MAX
tr_c1     = tr_r0+TR_MAX
tr_r1     = tr_c1+TR_MAX
tr_type   = tr_r1+TR_MAX
        ert tr_type+TR_MAX>$1400
tr_act    = $1646
tr_keys   = tr_act+TR_MAX       ; zpkeys bits needed
tr_flag   = tr_keys+TR_MAX
tr_tex    = tr_flag+TR_MAX      ; switch panel shown, $FF none
tr_p0     = tr_tex+TR_MAX       ; door / lift: its panel; teleport: x lo
        ert tr_p0+TR_MAX>$1800
tr_p1     = $0480               ; teleport x hi; press: target list start
tr_p2     = tr_p1+TR_MAX        ; teleport y lo; press: wait (ticks)
tr_p3     = tr_p2+TR_MAX        ; teleport y hi; press: count
tr_pl     = tr_p3+TR_MAX        ; [PL_MAX] PRESS target triggers
        ert tr_pl+PL_MAX>$0600
dp_c0     = $0700               ; door panels: rect, d2d group, state
dp_r0     = dp_c0+DP_MAX
dp_c1     = dp_r0+DP_MAX
dp_r1     = dp_c1+DP_MAX
dp_grp    = dp_r1+DP_MAX
dp_state  = dp_grp+DP_MAX       ; bit 0 closed now, bit 1 closed by default
dp_vlo    = dp_state+DP_MAX     ; cell list: VRAM_TPC + vhi:vlo
dp_vhi    = dp_vlo+DP_MAX
sp_state  = dp_vhi+DP_MAX       ; switch panels: bit 0 = shows the other one
sp_vlo    = sp_state+SP_MAX
sp_vhi    = sp_vlo+SP_MAX
        ert sp_vhi+SP_MAX>$0900
lf_c0     = $1A46               ; lifts: rect, type (0 up, 1 down), group
lf_r0     = lf_c0+LF_MAX
lf_c1     = lf_r0+LF_MAX
lf_r1     = lf_c1+LF_MAX
lf_type   = lf_r1+LF_MAX
lf_grp    = lf_type+LF_MAX
n_tr      = lf_grp+LF_MAX
n_dp      = n_tr+1
n_lf      = n_tr+3
        ert n_lf+1>$1B00
bm_n      = aw_l+MAX_ENEMIES    ; BLOCKMON panels: rect [c0, c1) x [r0, r1)
bm_c0     = bm_n+1
bm_r0     = bm_c0+BM_MAX
bm_c1     = bm_r0+BM_MAX
bm_r1     = bm_c1+BM_MAX
        ert bm_r1+BM_MAX>MEMW
TRIG_RAM  = 13*TR_MAX+PL_MAX+8*DP_MAX+3*SP_MAX+6*LF_MAX+4+1+4*BM_MAX
        ert TRIG_RAM_SECTORS*128<TRIG_RAM

; runtime state (g_triggers TimeOut, DoorTime, PressTime, PressCount;
; DoorTime/PressTime -1 = $FF)
tr_to     .ds TR_MAX
tr_dt     .ds TR_MAX
tr_pt     .ds TR_MAX
tr_pc     .ds TR_MAX
tr_who    dta 0                 ; ActivateUID: 0 player, 1+n enemy n, $FF none
level_complete dta 0            ; 1 = an EXIT trigger fired
stat_kills     dta 0            ; end-level statistics
stat_total_en  dta 0
stat_time_lo   dta 0            ; level time in seconds
stat_time_hi   dta 0
stat_frames    dta 0            ; frames of the current second
stat_secrets   dta 0            ; secrets found
stat_tsec      dta 0            ; secrets in the level (trig_load)

; ============================================
; TRIG_LOAD - after the tileset (DAUX continues): the RAM part through
; LVL_BUF to its 5 places, the panel cells to VRAM_TPC; state reset.
; Returns C=1 on an SIO error.
; ============================================
.proc trig_load
        jsr bl_reset            ; no blood from the last level (blood.asm),
        sta tp_n                ; no teleport flash (A = 0)
        ldx #TRIG_RAM_SECTORS
        jsr read_sectors        ; into LVL_BUF
        jcs ?r
        ldx #5                  ; runs, last first (load time: a plain copy)
?run    lda ?src_lo,x
        sta zsrc
        lda ?src_hi,x
        sta zsrc+1
        lda ?dst_lo,x
        sta ztptr
        lda ?dst_hi,x
        sta ztptr+1
        lda ?len_lo,x
        sta ?cnt
        lda ?len_hi,x
        sta ?cnt+1
        ldy #0
?cp     lda (zsrc),y
        sta (ztptr),y
        inc zsrc
        bne ?s
        inc zsrc+1
?s      inc ztptr
        bne ?d
        inc ztptr+1
?d      lda ?cnt
        bne ?c
        dec ?cnt+1
?c      dec ?cnt
        lda ?cnt
        ora ?cnt+1
        bne ?cp
        dex
        bpl ?run
        lda #BANK_EN+[VRAM_TPC>>12]
        sta vram_sio.vs_bank
        lda tpc_sectors         ; (>= 1, map2bin)
        clc                     ; read
        jsr vram_sio.go
        bcs ?r
        lda #0
        sta tr_shot
        sta stat_tsec
        ldx #TR_MAX-1           ; state: no timeout, DoorTime/PressTime off
?st     lda tr_act,x            ; tr_shot: every activation bit of the level
        ora tr_shot
        sta tr_shot
        lda #0
        sta tr_to,x
        sta tr_pc,x
        lda #$FF
        sta tr_dt,x
        sta tr_pt,x
        lda tr_type,x           ; the level's secrets: the stats' total
        cmp #TT_SECRET          ; (g_game.pas gSecretsCount)
        bne ?ns
        inc stat_tsec
?ns     dex
        bpl ?st
        lda #0
        sta stat_secrets
        clc
?r      rts
?R0     = 0                     ; c0..type
?R1     = 5*TR_MAX              ; act..p0
?R2     = 10*TR_MAX             ; p1..p3, pl
?R3     = 13*TR_MAX+PL_MAX      ; dp, sp
?R3LEN  = 8*DP_MAX+3*SP_MAX
?R4     = ?R3+?R3LEN            ; lf, counts
?R5     = ?R4+6*LF_MAX+4        ; bm
?src_lo dta <[LVL_BUF+?R0], <[LVL_BUF+?R1], <[LVL_BUF+?R2], <[LVL_BUF+?R3], <[LVL_BUF+?R4], <[LVL_BUF+?R5]
?src_hi dta >[LVL_BUF+?R0], >[LVL_BUF+?R1], >[LVL_BUF+?R2], >[LVL_BUF+?R3], >[LVL_BUF+?R4], >[LVL_BUF+?R5]
?dst_lo dta <tr_c0, <tr_act, <tr_p1, <dp_c0, <lf_c0, <bm_n
?dst_hi dta >tr_c0, >tr_act, >tr_p1, >dp_c0, >lf_c0, >bm_n
?len_lo dta <[5*TR_MAX], <[5*TR_MAX], <[3*TR_MAX+PL_MAX], <?R3LEN, <[6*LF_MAX+4], <[1+4*BM_MAX]
?len_hi dta >[5*TR_MAX], >[5*TR_MAX], >[3*TR_MAX+PL_MAX], >?R3LEN, >[6*LF_MAX+4], >[1+4*BM_MAX]
?cnt    dta 0,0
        ert ?R5+1+4*BM_MAX<>TRIG_RAM
.endp

; ============================================
; UPDATE_TRIGGERS - once per tick (g_Triggers_Update)
; ============================================
.proc update_triggers
        bit an_now
        bmi ?go
        rts
?go     lda tp_n                ; the teleport flash: a frame every TP_SPD ticks
        beq ?nf
        dec tp_c
        bne ?nf
        lda #TP_SPD
        sta tp_c
        dec tp_n
?nf     jsr bl_tick             ; the blood (blood.asm)
        jsr pl_cells
        bit ai_now              ; pass 1, on AI ticks (its only readers): the
        bpl ?nl                 ; awake monsters (en_act, en_state <> 0), in
        ldy #0                  ; index order, for MONSTERCOLLIDE
        ldx #0
        beq ?at                 ; (always)
?al     lda en_act,x
        beq ?an
        lda en_state,x
        beq ?an
        txa
        sta aw_l,y
        iny
?an     inx
?at     cpx num_en
        bcc ?al
        sty aw_n
?nl     ldx #0
        beq ?test               ; (always)
?lp     stx tu_i
        jsr tr_tick
        ldx tu_i
        inx
?test   cpx n_tr
        bcc ?lp
        rts
.endp
aw_n    dta 0                   ; the awake monsters this tick
aw_l    = at_tmr+AT_MAX         ; their list (LVL_BUF after the animation state)
        ert aw_l+MAX_ENEMIES>MEMW

; PL_CELLS - the player's rect (PLAYER_RECT 34x52 at half scale: 17x26 px,
; centred on zpx+PL_W/2, feet on zpy) in cells, INCLUSIVE: [pc0, pc1] x [pr0, pr1]
.proc pl_cells
        lda zpx                 ; x0 = zpx + PL_W/2 - 8
        sec
        sbc #8-PL_W/2
        tay
        lda zpx_hi
        sbc #0
        jsr cell_of             ; A = hi, Y = lo -> A = cell, C=0
        sta pc0
        lda zpx                 ; last px = x0 + 16 (C=0)
        adc #8+PL_W/2
        tay
        lda zpx_hi
        adc #0
        jsr cell_of
        sta pc1
        lda zpy                 ; y0 = zpy - 26
        sec
        sbc #26
        tay
        lda zpy_hi
        sbc #0
        jsr cell_of
        sta pr0
        lda zpy                 ; last px = zpy - 1 (C=0 from cell_of: the -1)
        sbc #0
        tay
        lda zpy_hi
        sbc #0
        jsr cell_of
        sta pr1
        rts
.endp
pc0     dta 0
pc1     dta 0
pr0     dta 0
pr1     dta 0

; CELL_OF - 16-bit px (A = hi with N from it, Y = lo; a negative one is
; cell 0) -> A = cell, C=0. hi <= 3: hi*32 = lsr + 3x ror, the bits shifted
; out last are 0 (C=0); the map with the rect offsets stays below 1024 px
.proc cell_of
        bmi ?z
        lsr
        ror
        ror
        ror
        ora div8_lut,y
        rts
?z      lda #0
        clc
        rts
        ert MAP_W*TW+32>1024 || MAP_H*TH+32>1024
.endp

; OVER_PL - C=1 if trigger X overlaps the player's cells
.proc over_pl
        lda pc0
        cmp tr_c1,x
        bcs ?no
        lda pc1                 ; tr_c0 <= pc1 (inclusive)
        cmp tr_c0,x
        bcc ?no
        lda pr0
        cmp tr_r1,x
        bcs ?no
        lda pr1                 ; C=1: tr_r0 <= pr1, they overlap
        cmp tr_r0,x
        rts
?no     clc
        rts
.endp

; MON_CELLS - enemy Y's rect (MONSTERTABLE.Rect at half scale, centred on
; en_x+8, feet on en_y) in cells: [mc0, mc1) x [mr0, mr1). Keeps X, Y.
.proc mon_cells
        stx ?x+1
        sty ?y+1
        ldx en_type,y
        lda en_x,y              ; centre = en_x + 8
        clc
        adc #8
        sta ?clo
        lda enxhi,y
        adc #0
        sta ?chi
        lda ?clo                ; x0 = centre - w/2
        sec
        sbc mon_hw,x
        tay
        lda ?chi
        sbc #0
        jsr cell_of             ; C=0
        sta mc0
        lda ?clo                ; last = centre + w/2 - 1
        adc mon_hw,x
        tay
        lda ?chi
        adc #0
        cpy #1                  ; C=0 when the low byte is 0: the borrow
        dey
        sbc #0                  ; (last: N = the high byte for cell_of)
        jsr cell_of
        adc #1                  ; C=0 (cell_of): exclusive
        sta mc1
        ldy ?y+1
        lda en_y,y              ; y0 = en_y - h
        sec
        sbc mon_h,x
        ldx ?y+1                ; X = the enemy (en_type done)
        tay
        lda en_y_hi,x
        sbc #0
        jsr cell_of
        sta mr0
        lda en_y,x              ; last = en_y - 1 (C=0 from cell_of: the -1)
        sbc #0
        tay
        lda en_y_hi,x
        sbc #0
        jsr cell_of
        adc #1
        sta mr1
?x      ldx #0                  ; (patched)
?y      ldy #0                  ; (patched)
        rts
?clo    dta 0
?chi    dta 0
.endp
mc0     dta 0
mc1     dta 0
mr0     dta 0
mr1     dta 0
; half width / height of the hit rect by en_type (zombie, imp, demon, caco,
; serg, baron, soul: MONSTERTABLE / 2)
mon_hw  dta 8, 8, 12, 15, 8, 12, 8
mon_h   dta 26, 25, 26, 28, 26, 32, 18

; OVER_MON - C=1 if trigger X overlaps the enemy cells (mon_cells)
.proc over_mon
        lda mc0
        cmp tr_c1,x
        bcs ?no
        lda tr_c0,x
        cmp mc1
        bcs ?no
        lda mr0
        cmp tr_r1,x
        bcs ?no
        lda tr_r0,x
        cmp mr1
        bcs ?no
        sec
        rts
?no     clc
        rts
.endp

; ============================================
; TR_TIMERS - tr_tick's rare part (DoorTime / PressTime running), out of
; line in front of it (in reach of its short branches); back to tr_tick.to
; ============================================
.proc tr_timers
        lda tr_dt,x
        beq ?pt
        cmp #$FF
        beq ?pt
        dec tr_dt,x
?pt     lda tr_pt,x
        beq ?trap
        cmp #$FF
        beq ?trap
        lda tr_flag,x           ; TF_LONG: one step every 16 ticks
        and #TF_LONG
        beq ?dec
        lda tr_dt,x
        bne ?trap
        lda #16
        sta tr_dt,x
?dec    dec tr_pt,x
?trap   lda tr_dt,x             ; TRAP reopens, DOOR5 closes at DoorTime 0
        bne ?press
        lda tr_type,x
        cmp #TT_TRAP
        bne ?d5
        lda #$FF
        sta tr_dt,x
        jsr door_open
        jmp ?press
?d5     cmp #TT_DOOR5
        bne ?press
        jsr door_closed         ; Z=0: already closed
        bne ?d5off
        jsr door_close
        bcc ?press              ; blocked: again next tick
?d5off  ldx tu_i
        lda #$FF
        sta tr_dt,x
?press  ldx tu_i
        lda tr_pt,x             ; PRESS/ON/OFF/ONOFF fire
        bne ?back
        lda tr_pc,x
        cmp tr_p3,x
        bcc ?back
        lda #$FF
        sta tr_pt,x
        lda tr_p3,x             ; count 0: all presses used up
        beq ?pc0
        lda tr_pc,x             ; C=1 (bcc ?back not taken)
        sbc tr_p3,x
?pc0    sta tr_pc,x
        jsr tr_fire
        ldx tu_i
?back   jmp tr_tick.to
go      jmp tr_timers           ; (tr_tick's entry: the start is out of reach)
tdec    dec tr_to,x             ; TimeOut runs: no collide checks
r       rts
.endp

; ============================================
; TR_TICK - one trigger's update (X = trigger, kept in tu_i). The common
; case (no timer, no TimeOut, enabled, no monster bit) falls through
; ============================================
.proc tr_tick
        lda tr_type,x
        beq tr_timers.r         ; none / a secret found
        lda tr_dt,x             ; DoorTime, PressTime: -1 ($FF) = off
        and tr_pt,x             ; both off (all measured): on to the TimeOut
        cmp #$FF
        bne tr_timers.go
to      lda tr_to,x             ; TimeOut: no collide checks while it runs
        bne tr_timers.tdec
        lda tr_flag,x
        lsr                     ; C = TF_EN
        bcc tr_timers.r
        lda tr_act,x            ; player inside (the rect rejects most: first)
        and #AC_PCOLL
        beq ?mon
        jsr over_pl
        bcc ?mon
        lda zphp
        beq ?mon                ; dead
        lda tr_keys,x
        and zpkeys
        cmp tr_keys,x
        bne ?mon
        lda #0
        sta tr_who
        lda #AC_PCOLL
        jsr tr_activate
        ldx tu_i
?mon    lda tr_act,x            ; no monster bit (most): done
        and #AC_MCOLL+AC_NOMON
        bne ?mb
        rts
?mb     tay                     ; Y = the monster bits
        lda tr_keys,x           ; monsters: only triggers without keys
        jne ?pcoll
        cpy #AC_MCOLL+AC_NOMON
        bne ?mc
        lda tr_act,x            ; both: once at the start, as actType 0
        and #$FF-AC_MCOLL-AC_NOMON
        sta tr_act,x
        lda #$FF
        sta tr_who
        lda #0
        jmp tr_activate
?mc     tya
        and #AC_MCOLL
        beq ?nm
        bit ai_now              ; monsters: on AI ticks, awake ones (a
        bpl ?nm                 ; sleeper does not move into a trigger)
        ldy #0                  ; the awake ones (update_triggers' list)
?mlp    cpy aw_n
        bcs ?nm
        sty ?mk+1
        lda aw_l,y
        tay
        jsr mon_cells
        jsr over_mon
        bcc ?mk
        iny
        sty tr_who
        lda #AC_MCOLL
        jsr tr_activate
        ldx tu_i
?mk     ldy #0                  ; (patched: the list index)
        iny
        bne ?mlp
?nm     lda tr_act,x            ; no monster alive inside
        and #AC_NOMON
        beq ?pcoll
        ldy #0
?nlp    cpy num_en
        bcs ?none
        lda en_act,y
        cmp #1
        bne ?nnx
        jsr mon_cells
        jsr over_mon
        bcs ?pcoll              ; one is inside
?nnx    iny
        bne ?nlp
?none   lda #$FF
        sta tr_who
        lda #AC_NOMON
        jmp tr_activate
?pcoll  rts                     ; (PlayerCollide: only SOUND/MUSIC read it)
.endp

; ============================================
; TRIG_USE - the player presses USE (SPACE): PLAYERPRESS triggers under the
; player rect (g_Triggers_PressR: TimeOut 0, keys, the bit)
; ============================================
.proc trig_use
        lda zphp
        beq ?r
        jsr pl_cells
        ldx #0
        beq ?test               ; (always)
?lp     lda tr_act,x
        and #AC_PPRESS
        beq ?nx
        lda tr_to,x
        bne ?nx
        lda tr_keys,x
        and zpkeys
        cmp tr_keys,x
        bne ?nx
        jsr over_pl
        bcc ?nx
        stx tu_i
        lda #0
        sta tr_who
        lda #AC_PPRESS
        jsr tr_activate
        ldx tu_i
?nx     inx
?test   cpx n_tr
        bcc ?lp
?r      rts
.endp

; ============================================
; TRIG_MON_PRESS - enemy X walked into a wall: MONSTERPRESS triggers under
; it (no keys). C=1 if one fired (then it waits). Keeps X.
; ============================================
.proc trig_mon_press
        stx ?y+1
        txa
        tay
        lda #0
        sta ?any+1
        jsr mon_cells
        ldx #0
        beq ?test               ; (always)
?lp     lda tr_act,x
        and #AC_MPRESS
        beq ?nx
        lda tr_to,x
        ora tr_keys,x
        bne ?nx
        jsr over_mon
        bcc ?nx
        stx tu_i
        ldy ?y+1
        iny
        sty tr_who
        lda #AC_MPRESS
        jsr tr_activate
        bcc ?nf
        inc ?any+1              ; it fired
?nf     ldx tu_i
?nx     inx
?test   cpx n_tr
        bcc ?lp
?y      ldx #0                  ; (patched)
?any    lda #0                  ; (patched)
        cmp #1                  ; C=1 if one fired
        rts
.endp

; ============================================
; TR_ACTIVATE - ActivateTrigger: trigger X, A = actType. C=1 when it did
; something (then the switch picture changes). Uses tu_i for X.
; ============================================
.proc tr_activate
        sta ta_act
        stx tu_i
        lda tr_flag,x
        lsr                     ; C = TF_EN
        bcc ?no
        lda tr_to,x
        bne ?no
        lda tr_type,x
        cmp #TT_LAST+1
        bcs ?no
        tay
        lda ?hi,y               ; dispatch: push target-1, rts
        pha
        lda ?lo,y
        pha
        rts
?no     clc
        rts
?lo     dta <[?no-1], <[t_exit-1], <[t_tele-1], <[t_open-1], <[t_close-1]
        dta <[t_door-1], <[t_door-1], <[t_trap-1], <[t_trap-1], <[t_press-1]
        dta <[t_secret-1], <[t_lift-1], <[t_lift-1], <[t_lift-1], <[?no-1]
        dta <[t_press-1], <[t_press-1], <[t_press-1], <[t_sound-1], <[?no-1]
        dta <[t_spawn-1]
?hi     dta >[?no-1], >[t_exit-1], >[t_tele-1], >[t_open-1], >[t_close-1]
        dta >[t_door-1], >[t_door-1], >[t_trap-1], >[t_trap-1], >[t_press-1]
        dta >[t_secret-1], >[t_lift-1], >[t_lift-1], >[t_lift-1], >[?no-1]
        dta >[t_press-1], >[t_press-1], >[t_press-1], >[t_sound-1], >[?no-1]
        dta >[t_spawn-1]
.endp
ta_act  dta 0
tr_shot dta 0                   ; OR of the level's tr_act (AC_SHOT: any shot trigger)


; done: C=1 - the switch picture (texture_panel) shows its other texture
.proc tr_done
        ldx tu_i
        ldy tr_tex,x
        iny
        beq ?r                  ; $FF: none
        dey
        lda sp_state,y
        eor #1
        sta sp_state,y
        lsr                     ; C = shows the other one
        lda sp_vlo,y
        ldx sp_vhi,y
        jsr panel_tiles         ; C=1: alt tiles
        ldx tu_i
?r      sec
        rts
.endp

; EXIT: the switch sound, the level ends (no picture change)
.proc t_exit
        lda #18
        sta tr_to,x
        lda #1
        sta level_complete
        ldx #SFX_SWTCHN
        jsr snd_play
        sec
        rts
.endp

; TELEPORT: the activator to the target foot point (velocity kept);
; direction 1 left, 2 right, 3 reverse
.proc t_tele
        lda tr_flag,x
        lsr
        lsr
        lsr
        lsr
        and #3
        sta ?d+1
        ldy tr_who
        beq ?pl
        iny
        bne ?en
        clc                     ; $FF: nobody
        rts
?en     dey
        dey                     ; Y = enemy
        lda en_x,y              ; the flash where it stood (en_x = centre - 8)
        sta tp_x
        lda enxhi,y
        sta tp_x+1
        lda en_y,y
        sta tp_y
        lda en_y_hi,y
        sta tp_y+1
        jsr tp_go
        lda tr_p0,x             ; en_x = x - 8, en_y = y
        sec
        sbc #8
        sta en_x,y
        lda tr_p1,x
        sbc #0
        sta enxhi,y
        lda tr_p2,x
        sta en_y,y
        lda tr_p3,x
        sta en_y_hi,y
        lda en_dir,y
        jsr ?dir
        sta en_dir,y
        jmp tr_done
?pl     lda zpx                 ; the flash where the player stood: centre - 8
        sec                     ; = zpx + PL_W/2 - 8
        sbc #8-PL_W/2
        sta tp_x
        lda zpx_hi
        sbc #0
        sta tp_x+1
        lda zpy
        sta tp_y
        lda zpy_hi
        sta tp_y+1
        jsr tp_go
        lda tr_p0,x             ; zpx = x - PL_W/2, zpy = y
        sec
        sbc #PL_W/2
        sta zpx
        lda tr_p1,x
        sbc #0
        sta zpx_hi
        lda tr_p2,x
        sta zpy
        lda tr_p3,x
        sta zpy_hi
        lda zpdir
        jsr ?dir
        sta zpdir
        lda #$FF                ; the camera jumps: rebuild the canvas, snap Y
        sta last_cam_tcol
        sta cam_vsnap
        jmp tr_done
?dir                            ; A = dir (0 right, 1 left) -> the new one
?d      ldx #0                  ; (patched: 1 left, 2 right, 3 reverse)
        beq ?keep
        dex
        beq ?left
        dex
        beq ?right
        eor #1
?keep   ldx tu_i
        rts
?left   lda #1
        bne ?keep
?right  lda #0
        beq ?keep
        ert PL_W>16
.endp

; TP_GO - trigger X teleports: the flash at tp_x/tp_y unless it is silent
; (tr_flag bit 2, tgcSilent). Keeps X, Y.
.proc tp_go
        lda tr_flag,x
        and #4
        bne ?r
        lda #TP_FR
        sta tp_n
        lda #TP_SPD
        sta tp_c
?r      rts
.endp

; RENDER_TELE - the teleport flash (g_player.pas TeleportTo: FRAMES_TELEPORT
; at the old place, TAnimation speed 3): frame TELE0 + TP_FR - tp_n at tp_x
; (centre - 8) / tp_y (feet), 16-bit, never mirrored
.proc render_tele
        lda tp_n
        beq ?r
        lda #TELE0+TP_FR
        sec
        sbc tp_n
        tax                     ; X = the frame (blit_frame)
        lda mf_ox,x             ; zdxh:zdx = tp_x + signed offset
        clc
        adc tp_x
        sta zdx
        lda mf_ox,x             ; the offset's sign as the high byte
        and #$80
        beq ?xp
        lda #$FF
?xp     adc tp_x+1
        sta zdxh
        lda mf_oy,x             ; zdy_hi:zdy = tp_y + signed offset
        clc
        adc tp_y
        sta zdy
        lda mf_oy,x
        and #$80
        beq ?yp
        lda #$FF
?yp     adc tp_y+1
        sta zdy_hi
        lda #0
        sta bf_mir
        jmp blit_frame
?r      rts
.endp
TP_FR   = 10                    ; frames
TP_SPD  = 3                     ; animation ticks a frame (update_triggers)
tp_n    dta 0                   ; frames left (0: no flash)
tp_c    dta 0                   ; ticks left of this frame
tp_x    dta 0,0
tp_y    dta 0,0

.proc t_open
        jsr door_open
        jcs tr_done
        rts
.endp

.proc t_close
        jsr door_close
        jcs tr_done
        rts
.endp

; DOOR / DOOR5: open a closed door (DOOR5: closes again after 5 s), close an
; open one; TimeOut 18 when it changed
.proc t_door
        jsr door_closed
        beq ?close
        jsr door_open
        bcc ?r
        ldx tu_i
        lda tr_type,x
        cmp #TT_DOOR5
        bne ?ok
        lda #180
        sta tr_dt,x
        bne ?ok                 ; (always)
?close  jsr door_close
        bcc ?r
?ok     ldx tu_i
        lda #18
        sta tr_to,x
        jmp tr_done
?r      rts
.endp

; TRAP / CLOSETRAP: close the door at once, killing whoever is inside; TRAP
; opens it again after 40 ticks (TimeOut 76)
.proc t_trap
        jsr door_closed
        bne ?shut
        lda tr_flag,x
        and #TF_SILENT
        bne ?shut
        ldx #SFX_SWTCHX
        jsr snd_play
?shut   jsr door_trap
        ldx tu_i
        lda tr_type,x
        cmp #TT_TRAP
        bne ?ct
        lda #40
        sta tr_dt,x
        lda #76
        sta tr_to,x
        jmp tr_done
?ct     lda #$FF
        sta tr_dt,x
        jmp tr_done
.endp

; PRESS / ON / OFF / ONOFF: count the press, start the wait (fires in
; tr_tick); TimeOut 18 unless activated by another trigger
.proc t_press
        lda tr_pc,x             ; PressCount + 1 (stops at 255)
        cmp #$FF
        beq ?c
        inc tr_pc,x
?c      lda tr_pt,x
        cmp #$FF
        bne ?w
        lda tr_p2,x
        sta tr_pt,x
        lda tr_flag,x
        and #TF_LONG
        beq ?w
        lda #16                 ; the first 16-tick step
        sta tr_dt,x
?w      lda ta_act
        beq ?t0
        lda #18
?t0     sta tr_to,x
        jmp tr_done
.endp

; SECRET: a player finds it once
.proc t_secret
        lda tr_who
        bne ?r
        lda tr_flag,x
        and #$FF-TF_EN
        sta tr_flag,x
        lda #0
        sta tr_type,x           ; TRIGGER_SECRET_FOUND: inert
        inc stat_secrets
        ldx #SFX_SECRET         ; g_player.pas GetSecret: SOUND_GAME_SECRET
        jsr snd_play            ; and the message
        jsr msg_on
        jmp tr_done
?r      clc
        rts
.endp

; LIFTUP / LIFTDOWN / LIFT (toggle): the lift (d2d: its group); TimeOut 18
; for LIFT when it changed; switch sound
.proc t_lift
        lda tr_type,x
        sec
        sbc #TT_LIFTUP          ; 0 up, 1 down, 2 toggle
        sta ?m+1
        lda #0
        sta ?ch+1
        ldy tr_p0,x
        cpy #$FF
        beq ?r
        lda lf_grp,y
        sta ?g+1
        ldy #0
?lp     cpy n_lf
        bcs ?end
        lda tr_flag,x           ; d2d: the whole group, else just p0
        and #TF_D2D
        bne ?grp
        tya
        cmp tr_p0,x
        bne ?nx
        beq ?set
?grp    lda lf_grp,y
?g      cmp #0                  ; (patched)
        bne ?nx
?set
?m      lda #0                  ; (patched: mode)
        cmp #2
        bcc ?put
        lda lf_type,y
        eor #1
?put    cmp lf_type,y
        beq ?nx
        sta lf_type,y
        lda #1
        sta ?ch+1
?nx     iny
        bne ?lp
?end
?ch     lda #0                  ; (patched: changed)
        beq ?r
        lda tr_type,x
        cmp #TT_LIFT
        bne ?snd
        lda #18
        sta tr_to,x
?snd    lda tr_flag,x
        and #TF_SILENT
        bne ?d
        ldx #SFX_SWTCHN
        jsr snd_play
?d      jmp tr_done
?r      clc
        rts
.endp

; TR_FIRE - PRESS/ON/OFF/ONOFF trigger X fires on its target list
.proc tr_fire
        lda tr_p0,x             ; list start .. +count
        sta ?i+1
        clc
        adc tr_p1,x
        sta ?e+1
        lda tr_type,x
        sta ?t+1
        lda tr_who
        sta ?w+1
?lp
?i      ldy #0                  ; (patched)
?e      cpy #0                  ; (patched)
        bcs ?r
        inc ?i+1
        ldx tr_pl,y             ; X = target
?t      lda #0                  ; (patched: the firing type)
        cmp #TT_PRESS
        bne ?on
?w      lda #0                  ; (patched: ActivateUID copied)
        sta tr_who
        lda tu_i
        pha
        lda #0
        jsr tr_activate
        pla
        sta tu_i
        jmp ?lp
?on     cmp #TT_ON
        bne ?off
        lda tr_flag,x
        ora #TF_EN
        bne ?st                 ; (always)
?off    cmp #TT_OFF
        beq ?dis
        lda tr_flag,x           ; ONOFF: toggle
        lsr
        bcs ?dis
        sec                     ; off: (flag >> 1) << 1 | TF_EN
        rol
        bne ?st                 ; (always: bit 0 set)
        ert TF_EN<>1
?dis    lda #0
        sta tr_to,x
        lda tr_flag,x
        and #$FF-TF_EN
?st     sta tr_flag,x
        jmp ?lp
?r      ldx tu_i
        rts
.endp

; ============================================
; DOORS - the door panel of trigger tu_i (tr_p0), with its whole d2d group
; when TF_D2D. door_closed: Z=0 if that panel is closed.
; ============================================
.proc door_closed
        ldx tu_i
        ldy tr_p0,x
        lda dp_state,y
        and #1
        rts
.endp

; DOOR_OPEN - every closed panel of the set opens; C=1 if one did (+ sound)
.proc door_open
        lda #0
        sta dr_chg
        sta dr_k
?lp     jsr dr_next             ; Y = next panel of the set, C=1 at the end
        bcs ?end
        lda dp_state,y
        lsr
        bcc ?lp                 ; already open
        jsr dr_set_open
        jmp ?lp
?end    lda #SFX_DOOROPN
        bne dr_snd              ; (always: the ert at dr_snd)
.endp

; DOOR_CLOSE - nothing when a player or a live monster stands in a panel of
; the set; else every open panel closes; C=1 if one did (+ sound)
.proc door_close
        jsr dr_blocked
        bcs ?no
        lda #0
        sta dr_chg
        sta dr_k
?lp     jsr dr_next
        bcs ?end
        lda dp_state,y
        lsr
        bcs ?lp                 ; already closed
        jsr dr_set_closed
        jmp ?lp
?end    lda #SFX_DOORCLS
        bne dr_snd              ; (always: the ert at dr_snd)
?no     clc
        rts
.endp

; DOOR_TRAP - kill whoever is in a panel of the set, then close it all
.proc door_trap
        lda #0
        sta dr_k
?lp     jsr dr_next
        bcs ?close
        jsr dp_kill             ; (dr_next reloads Y from dr_k)
        jmp ?lp
?close  lda #0
        sta dr_k
?l2     jsr dr_next
        bcs ?r
        lda dp_state,y
        lsr
        bcs ?l2
        jsr dr_set_closed
        jmp ?l2
?r      rts
.endp

; DR_SND - A = sound if a panel changed and the trigger is not silent; C=1
; if a panel changed
        ert SFX_DOOROPN=0 .or SFX_DOORCLS=0     ; (its callers' bne after lda #)
.proc dr_snd
        ldy dr_chg
        beq ?no
        ldx tu_i
        tay
        lda tr_flag,x
        and #TF_SILENT
        bne ?yes
        tya
        tax
        jsr snd_play
?yes    sec
        rts
?no     clc
        rts
.endp

; DR_NEXT - Y = the next door panel of trigger tu_i's set (dr_k walks
; 0..n_dp-1; start with dr_k = 0); C=1 when done
.proc dr_next
        ldx tu_i
?lp     ldy dr_k
        cpy n_dp
        bcs ?r
        inc dr_k
        lda tr_flag,x
        and #TF_D2D
        bne ?grp
        tya
        cmp tr_p0,x
        bne ?lp
        clc
        rts
?grp    sty ?y+1
        ldy tr_p0,x
        lda dp_grp,y
?y      ldy #0                  ; (patched)
        cmp dp_grp,y
        bne ?lp
        clc
?r      rts
.endp
dr_k    dta 0
dr_chg  dta 0

; DR_BLOCKED - C=1 if the live player or a live monster overlaps a panel of
; the set
.proc dr_blocked
        lda #0
        sta dr_k
        jsr pl_cells
?lp     jsr dr_next
        bcs ?free
        lda zphp
        beq ?mon
        lda pc0                 ; the player
        cmp dp_c1,y
        bcs ?mon
        lda pc1                 ; (pc1, pr1 inclusive)
        cmp dp_c0,y
        bcc ?mon
        lda pr0
        cmp dp_r1,y
        bcs ?mon
        lda pr1
        cmp dp_r0,y
        bcs ?yes
?mon    sty ?p+1
        ldy #0
?mlp    cpy num_en
        bcs ?mnx
        lda en_act,y
        cmp #1
        bne ?mn
        jsr mon_cells
        sty ?e+1
?p      ldy #0                  ; (patched: panel)
        lda mc0
        cmp dp_c1,y
        bcs ?mo
        lda dp_c0,y
        cmp mc1
        bcs ?mo
        lda mr0
        cmp dp_r1,y
        bcs ?mo
        lda dp_r0,y
        cmp mr1
        bcc ?yes
?mo
?e      ldy #0                  ; (patched: enemy)
?mn     iny
        bne ?mlp
?mnx    jmp ?lp
?free   clc
        rts
?yes    sec
        rts
.endp

; DP_KILL - door panel Y: TRAP_DAMAGE to the player and live monsters in it
.proc dp_kill
        sty ?p+1
        jsr pl_cells
?p      ldy #0                  ; (patched)
        lda zphp
        beq ?mon
        lda pc0
        cmp dp_c1,y
        bcs ?mon
        lda pc1                 ; (pc1, pr1 inclusive)
        cmp dp_c0,y
        bcc ?mon
        lda pr0
        cmp dp_r1,y
        bcs ?mon
        lda pr1
        cmp dp_r0,y
        bcc ?mon
        lda #0                  ; TRAP_DAMAGE 1000: dead whatever the armor
        sta zparmor
        lda #255
        jsr player_take_damage
?mon    ldx #0
?mlp    cpx num_en
        bcs ?r
        lda en_act,x
        cmp #1
        bne ?mn
        txa
        tay
        jsr mon_cells
        ldy ?p+1
        lda mc0
        cmp dp_c1,y
        bcs ?mn
        lda dp_c0,y
        cmp mc1
        bcs ?mn
        lda mr0
        cmp dp_r1,y
        bcs ?mn
        lda dp_r0,y
        cmp mr1
        bcs ?mn
        lda #0
        sta en_hp,x
        jsr start_enemy_death   ; keeps X
        stx ?x+1
        jsr play_enemy_death    ; (clobbers X)
?x      ldx #0                  ; (patched)
?mn     inx
        bne ?mlp
?r      rts
.endp

; DR_SET_OPEN / DR_SET_CLOSED - door panel Y to that state: its cells get
; the tile of the state (alt when it differs from the default). Keeps Y.
.proc dr_set_open
        lda dp_state,y
        and #$FE
        bpl dr_set              ; (always)
.endp
.proc dr_set_closed
        lda dp_state,y
        ora #1
        ert *<>dr_set
.endp
.proc dr_set
        sta dp_state,y          ; alt = (closed now) xor (closed by default)
        sty ?y+1
        lsr                     ; C = closed now, A = closed by default
        sta ?s+1
        lda #0
        rol                     ; A = closed now
?s      eor #0                  ; (patched: closed by default)
        lsr                     ; C = alt
        inc dr_chg              ; <> 0: a panel changed (0 before each open /
                                ; close, <= DP_MAX of them: no wrap)
        lda dp_vlo,y
        ldx dp_vhi,y
        jsr panel_tiles
?y      ldy #0                  ; (patched)
        rts
.endp

; PANEL_TILES - the cell list at VRAM_TPC + X:A into the map, alt tiles if
; C=1 else the default ones; every changed cell is queued for a canvas patch
.proc panel_tiles
        ldy #3                  ; column 3 = def, 2 = alt
        bcc ?d
        dey
?d      sty ?which+1
        sta ztptr
        txa
        and #$0F
        ora #>MEMW
        sta ztptr+1
        txa
        lsr
        lsr
        lsr
        lsr
        clc
        adc #BANK_EN+[VRAM_TPC>>12]
        sta ?bank+1
        sta VBXE_BANK_SEL
        ldy #0
        lda (ztptr),y           ; n cells
        beq ?r
        sta ?n
        inc ztptr               ; the list is in one bank (d2df2map)
        bne ?lp
        inc ztptr+1
?lp
?bank   lda #0                  ; (patched)
        sta VBXE_BANK_SEL
        ldy #0
        lda (ztptr),y
        sta r_col
        iny
        lda (ztptr),y
        sta r_row
?which  ldy #0                  ; (patched: 2 alt, 3 def)
        lda (ztptr),y
        sta ?t+1
        lda ztptr
        clc
        adc #4
        sta ztptr
        bcc ?w
        inc ztptr+1
?w      pha                     ; calc_map_ptr uses ztptr: park ours (A = lo)
        lda ztptr+1
        pha
        jsr calc_map_ptr        ; map bank on, ztptr = the cell
        ldy #0
?t      lda #0                  ; (patched: the tile)
        sta (ztptr),y
        lda #0
        sta VBXE_BANK_SEL
        lda r_col
        ldy r_row
        jsr canvas_mark_tile
        pla
        sta ztptr+1
        pla
        sta ztptr
        dec ?n                  ; cells left
        bne ?lp
?r      lda #0
        sta VBXE_BANK_SEL
        jmp pk_wake             ; a door opened under an item: it falls
?n      dta 0                   ; cells left
.endp

; ============================================
; LIFT_PLAYER - C=1 if the player stands in a lift: A = 0 up, 1 down
; (g_Obj_Move: CollideLift on the object's rect)
; ============================================
.proc lift_player
        ldy n_lf
        beq ?no
        jsr pl_cells            ; (ends on tay: Y is not n_lf any more)
        ldy n_lf
        dey
?lp     lda pc0
        cmp lf_c1,y
        bcs ?nx
        lda pc1                 ; (pc1, pr1 inclusive)
        cmp lf_c0,y
        bcc ?nx
        lda pr0
        cmp lf_r1,y
        bcs ?nx
        lda pr1
        cmp lf_r0,y
        bcc ?nx
        lda lf_type,y           ; C=1 (bcc not taken)
        rts
?nx     dey
        bpl ?lp
?no     clc
        rts
.endp
