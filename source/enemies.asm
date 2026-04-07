;==============================================
; DOOM2D - Enemies (arrays, init, update, render)
; enemies.asm
;==============================================

; ============================================
; ENEMY ARRAYS (indexed by X = 0..MAX_ENEMIES-1)
; ============================================
en_x    .ds MAX_ENEMIES        ; X position (low byte)
enxhi   .ds MAX_ENEMIES        ; X position (high byte)
en_y    .ds MAX_ENEMIES        ; Y position
en_dir  .ds MAX_ENEMIES        ; direction 0=right, 1=left
en_act  .ds MAX_ENEMIES        ; active flag
en_hp   .ds MAX_ENEMIES        ; hit points
en_xmin .ds MAX_ENEMIES        ; patrol min X
en_xmax .ds MAX_ENEMIES        ; patrol max X
en_type .ds MAX_ENEMIES        ; 0=zombie, 1=imp, 2=pinky, 3=caco
en_cooldown .ds MAX_ENEMIES    ; attack cooldown timer
en_dtimer .ds MAX_ENEMIES      ; death animation timer (0=not dying)
envely   .ds MAX_ENEMIES        ; vertical velocity (signed, for Imp jump)
en_gib   .ds MAX_ENEMIES        ; 1=gibbed (rocket kill), 0=normal death
envelx   .ds MAX_ENEMIES        ; horizontal velocity (signed, for knockback)
en_atk   .ds MAX_ENEMIES        ; attack timer (0=ready to fire)

; en_act values: 0=inactive, 1=alive, 2=dying

; en_base_spr and en_hp_tab are in sprite_defs.asm (auto-generated)

; ============================================
; START_ENEMY_DEATH - common kill setup
; Input: X = enemy index
; Sets dying state, timer, no gib, no knockback
; ============================================
.proc start_enemy_death
        lda #2
        sta en_act,x
        lda #20
        sta en_dtimer,x
        lda #0
        sta en_gib,x
        sta envelx,x
        rts
.endp

; ============================================
; init_enemies is in the overlay segment (end of main.asm)

; ============================================
; UPDATE ALL ENEMIES
; ============================================
.proc update_enemies
        ldx #0
?lp     lda en_act,x
        bne ?active
        jmp ?nx
?active cmp #2
        bne ?alive
        ; --- Dying: count down death timer + knockback ---
        dec en_dtimer,x
        beq ?dead
        ; Apply knockback velocity if gibbed
        lda en_gib,x
        beq ?nx_jmp         ; not gibbed, skip movement
        ; Horizontal knockback (16-bit, signed velocity)
        lda en_x,x
        clc
        adc envelx,x
        sta en_x,x
        lda envelx,x
        bmi ?kb_neg
        lda enxhi,x
        adc #0              ; positive: add carry
        sta enxhi,x
        jmp ?kb_vy
?kb_neg lda enxhi,x
        adc #$FF            ; negative: sign extend ($FF + carry)
        sta enxhi,x
?kb_vy
        ; Vertical knockback (gravity applied)
        lda envely,x
        clc
        adc en_y,x
        sta en_y,x
        ; Add gravity to knockback (signed: negative = going up)
        lda envely,x
        bmi ?do_kb_grav     ; negative velocity → always add gravity
        cmp #MAXFALL
        bcs ?nx_jmp         ; positive >= MAXFALL → capped
?do_kb_grav
        inc envely,x
?nx_jmp jmp ?nx
?dead
        lda #0
        sta en_act,x        ; fully dead, deactivate
        jmp ?nx
?alive  stx zzidx
        ; --- Off-screen skip: X >= 320 (enxhi >= 2), only do gravity ---
        lda enxhi,x
        cmp #2
        bcc ?on_screen
        jmp ?grav               ; off-screen right, skip AI
?on_screen
        ; --- Pain timer decrement ---
        lda en_pain_tmr,x
        beq ?no_pdec
        dec en_pain_tmr,x
?no_pdec
        ; --- LOS check: stagger per enemy ---
        ; Alerted: every 2nd frame. Idle: every 4th frame.
        lda zfr
        eor zzidx
        sta zt
        lda en_cooldown,x
        bne ?alert_stagger
        lda zt
        and #$03              ; idle: 1 of 4 frames
        beq ?do_los
        jmp ?grav
?alert_stagger
        lda zt
        and #$01              ; alerted: 1 of 2 frames
        beq ?do_los
        jmp ?grav
?do_los
        ; If alerted and falling, skip LOS and keep chasing
        ; (prevents cycling on stairs when chest-height row changes)
        lda en_cooldown,x
        beq ?normal_los
        lda envely,x
        beq ?normal_los
        jmp ?no_attack          ; alerted + falling = keep chasing
?normal_los
        ; --- LOS (Line Of Sight) check ---
        ; Algorithm:
        ; 1. Vertical distance check: |en_y - zpy| < 48 (same platform)
        ; 2. Proximity check: |en_x - zpx| < 48 → always alert (close range)
        ; 3. Direction check: enemy must face the player (skip if alerted)
        ; 4. Horizontal tile scan: check all tiles between enemy and player
        ;    for solid blocks. If any solid tile found → LOS blocked.
        ;
        ; Step 1: Vertical distance — abs(en_y - zpy)
        lda en_y,x
        sec
        sbc zpy
        bpl ?yp                 ; positive? keep as-is
        eor #$FF               ; negate: abs = NOT(val) + 1
        clc
        adc #1
?yp     cmp #48                 ; > 48px apart vertically?
        bcc ?los_check
        jmp ?idle               ; too far vertically, don't detect
?los_check
        ; Step 2: Proximity — 16-bit abs(enxhi:en_x - zpx_hi:zpx)
        lda en_x,x
        sec
        sbc zpx
        sta los_cur             ; dist lo (may be negative)
        lda enxhi,x
        sbc zpx_hi
        bpl ?ppos
        ; Result negative → negate to get absolute value
        lda #0
        sec
        sbc los_cur
        sta los_cur
?ppos   bne ?no_prox            ; hi byte != 0 → distance > 255
        lda los_cur
        cmp #48
        bcc ?dir_ok             ; within 48px = proximity alert!
?no_prox
        ; If already alerted, skip direction check (360° awareness)
        lda en_cooldown,x
        bne ?dir_ok
        ; Direction check: enemy only sees forward (180° cone)
        lda en_dir,x
        bne ?chk_left
        ; Facing right (dir=0): player must be right of enemy
        lda enxhi,x
        cmp zpx_hi
        bcc ?dir_ok         ; enxhi < zpx_hi → right ✓
        bne ?not_right      ; enxhi > zpx_hi → left
        lda en_x,x
        cmp zpx
        bcc ?dir_ok         ; en_x < zpx → right ✓
?not_right
        jmp ?idle
?chk_left
        ; Facing left (dir=1): player must be left of enemy
        lda zpx_hi
        cmp enxhi,x
        bcc ?dir_ok         ; zpx_hi < enxhi → left ✓
        bne ?not_left       ; zpx_hi > enxhi → right
        lda zpx
        cmp en_x,x
        bcc ?dir_ok         ; zpx < en_x → left ✓
?not_left
        jmp ?idle
?dir_ok

        ; Compute map row pointer for LOS tile scan
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        lda en_y,x
        sec
        sbc #8              ; chest height
        lsr
        lsr
        lsr
        lsr                 ; A = row
        tay
        ; ztptr = map_data + row*64 (LUT)
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ; Enemy tile column = (enxhi:en_x + 8) / 16
        ; +8 = center of 16px sprite. Divide 16-bit value by 16:
        ;   result = (hi << 4) | (lo >> 4)  [same formula as mark_dirty_sprite]
        ldx zzidx
        lda en_x,x
        clc
        adc #8              ; center X
        pha
        lda enxhi,x
        adc #0              ; propagate carry
        asl                 ; hi << 4 (shift left 4 times)
        asl
        asl
        asl
        sta los_ecol
        pla
        lsr                 ; lo >> 4 (shift right 4 times)
        lsr
        lsr
        lsr
        ora los_ecol        ; combine hi and lo parts
        sta los_ecol

        ; Player tile column — same formula
        lda zpx
        clc
        adc #8
        sta los_pcol
        lda zpx_hi
        adc #0
        asl
        asl
        asl
        asl
        sta los_end
        lda los_pcol
        lsr
        lsr
        lsr
        lsr
        clc
        adc los_end
        sta los_pcol

        ; Scan tiles between player and enemy (inclusive endpoints)
        lda los_ecol
        cmp los_pcol
        beq ?h_clear        ; same column = visible
        bcc ?scan_r         ; enemy left of player

        ; Enemy right of player: scan from pcol to ecol
        lda los_pcol
        sta los_cur
        lda los_ecol
        clc
        adc #1
        jmp ?do_scan

?scan_r ; Enemy left of player: scan from ecol to pcol
        lda los_ecol
        sta los_cur
        lda los_pcol
        clc
        adc #1

?do_scan
        sta los_end
?scan   lda los_cur
        cmp los_end
        bcs ?h_clear        ; no wall found horizontally, check vertical
        tay
        lda (ztptr),y       ; tile at (column, row)
        tax
        lda tile_solid,x
        beq ?scan_nx
        jmp ?idle           ; solid tile = wall blocks LOS
?scan_nx
        inc los_cur
        jmp ?scan

?h_clear
        ; --- Vertical LOS check: solid tiles between enemy row and player row? ---
        ldx zzidx
        lda en_y,x
        sec
        sbc #8              ; enemy chest
        lsr
        lsr
        lsr
        lsr
        sta los_cur         ; enemy row
        lda zpy
        sec
        sbc #8              ; player chest
        lsr
        lsr
        lsr
        lsr
        sta los_end         ; player row
        cmp los_cur
        beq ?detected       ; same row = no vertical wall possible
        bcc ?v_up
        ; Player below enemy: scan from enemy row to player row
        jmp ?v_scan
?v_up   ; Player above enemy: swap so los_cur < los_end
        lda los_end
        pha
        lda los_cur
        sta los_end
        pla
        sta los_cur
?v_scan lda los_cur
        cmp los_end
        bcs ?detected       ; reached end = no wall found
        tay
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldy los_ecol        ; check at enemy's column
        lda (ztptr),y
        tax
        lda tile_solid,x
        bne ?v_wall         ; solid tile blocks vertical LOS
        inc los_cur
        jmp ?v_scan
?v_wall jmp ?idle           ; wall between floors = can't see

?detected
        ; Mark as alerted (stays alerted permanently)
        ldx zzidx
        lda en_cooldown,x
        bne ?already_alert      ; already alerted = no sight sound
        ; First alert! Play sight sound by enemy type
        jsr play_enemy_sight
?already_alert
        ldx zzidx
        lda #1
        sta en_cooldown,x
        jsr enemy_do_attack
?no_attack
        ldx zzidx
        ; Player visible! Chase: face player and move toward
        ; 16-bit absolute distance: |enxhi:en_x - zpx_hi:zpx|
        lda en_x,x
        sec
        sbc zpx
        sta los_cur         ; dist low
        lda enxhi,x
        sbc zpx_hi
        sta los_end         ; dist high (signed)
        bpl ?dpos
        ; Negate 16-bit (ones complement + 1)
        lda los_cur
        eor #$FF
        clc
        adc #1
        sta los_cur
        lda los_end
        eor #$FF
        adc #0
        sta los_end
?dpos   ; los_end:los_cur = absolute distance
        lda los_end
        bne ?jchase1        ; high != 0 → far, chase
        lda los_cur
        cmp #16
        bcs ?jchase1        ; > 16px, chase directly
        ; Within 16px horizontally - check Y distance
        ; If player is on different level, patrol instead of standing
        lda en_y,x
        sec
        sbc zpy
        bpl ?yd
        eor #$FF
        clc
        adc #1
?yd     cmp #32
        bcs ?patrol         ; different level (>=32px Y) = patrol
        ; Same level, within 16px: update patrol bounds to current pos
        lda en_x,x
        sec
        sbc #40
        bcs ?nb_min
        lda #0
?nb_min sta en_xmin,x
        lda en_x,x
        clc
        adc #40
        bcc ?nb_max
        lda #255
?nb_max sta en_xmax,x
        jmp ?patrol         ; patrol near player with updated bounds
?jchase1 jmp ?do_chase
        ; Different level - patrol back and forth
?patrol lda en_dir,x
        bne ?pat_l
        ; Patrol right: wall check first
        lda en_x,x
        clc
        adc #16             ; right edge of enemy
        sta gt_px
        lda enxhi,x
        adc #0
        sta gt_px_hi
        lda en_y,x
        sec
        sbc #8              ; chest height
        sta gt_py
        jsr check_solid
        pha
        ldx zzidx
        pla
        bne ?pat_turn_l     ; wall → turn around
        lda #0
        sta en_tcnt,x       ; moved → reset turn counter
        inc en_x,x
        bne ?pr1
        inc enxhi,x
?pr1    inc en_x,x
        bne ?pat_nw1
        inc enxhi,x
?pat_nw1
        lda en_type,x
        tay
        lda en_speed_tab,y
        cmp #3
        bcc ?pr_nospd
        inc en_x,x
        bne ?pr_nospd
        inc enxhi,x
?pr_nospd
        lda en_x,x
        cmp en_xmax,x
        bcc ?jgrav1
        bcs ?pat_turn_l
?jgrav1 jmp ?grav
?pat_turn_l
        ldx zzidx
        inc en_tcnt,x
        lda en_tcnt,x
        cmp #2
        bcs ?grav_jmp       ; stuck: don't flip, just stand
        lda #1
        sta en_dir,x
        jmp ?grav
?grav_jmp jmp ?grav
?pat_l  ; Patrol left: wall check first
        lda en_x,x
        sec
        sbc #1              ; left edge
        sta gt_px
        lda enxhi,x
        sbc #0
        bmi ?pat_turn_r     ; underflow past 0 → turn
        sta gt_px_hi
        lda en_y,x
        sec
        sbc #8
        sta gt_py
        jsr check_solid
        pha
        ldx zzidx
        pla
        bne ?pat_turn_r     ; wall → turn around
        lda en_x,x
        bne ?pl_ok
        lda enxhi,x
        beq ?pat_turn_r     ; at 0 → turn
        dec enxhi,x
?pl_ok  lda #0
        sta en_tcnt,x       ; moved → reset turn counter
        dec en_x,x
        lda en_x,x
        bne ?pl2
        lda enxhi,x
        beq ?jgrav2
        dec enxhi,x
?pl2    dec en_x,x
        lda en_type,x
        tay
        lda en_speed_tab,y
        cmp #3
        bcc ?pl_nospd
        lda en_x,x
        bne ?pl3
        lda enxhi,x
        beq ?pl_nospd
        dec enxhi,x
?pl3    dec en_x,x
?pl_nospd
        lda en_x,x
        cmp en_xmin,x
        bcs ?jgrav2
        jmp ?pat_turn_r
?jgrav2 jmp ?grav
?pat_turn_r
        ldx zzidx
        inc en_tcnt,x
        lda en_tcnt,x
        cmp #2
        bcs ?grav_jmp2      ; stuck: don't flip, just stand
        lda #0
        sta en_dir,x
        jmp ?grav
?grav_jmp2 jmp ?grav
?do_chase
        ; Determine direction: compare 16-bit enxhi:en_x vs zpx_hi:zpx
        ldx zzidx
        lda enxhi,x
        cmp zpx_hi
        bcc ?chase_r        ; enxhi < zpx_hi → go right
        bne ?chase_l        ; enxhi > zpx_hi → go left
        lda en_x,x
        cmp zpx
        bcc ?chase_r        ; en_x < zpx → go right
        ; Enemy right of or equal to player: face left, move left
?chase_l
        lda #1
        sta en_dir,x
        ; Wall check left (en_x - 1, chest height)
        lda en_x,x
        sec
        sbc #1
        sta gt_px
        lda enxhi,x
        sbc #0
        bpl ?cl_edge_ok
        jmp ?grav           ; past left edge
?cl_edge_ok
        sta gt_px_hi
        lda en_y,x
        sec
        sbc #8
        sta gt_py
        jsr check_solid
        pha
        ldx zzidx
        pla
        bne ?cl_wall        ; wall → don't move
        lda en_x,x
        bne ?cl_ok
        lda enxhi,x
        beq ?cl_wall        ; at 0
        bne ?cl_borrow
?cl_wall jmp ?grav
?cl_borrow
        dec enxhi,x
?cl_ok  dec en_x,x
        lda en_x,x
        bne ?cl_ok2
        lda enxhi,x
        beq ?grav
        dec enxhi,x
?cl_ok2 dec en_x,x
        lda en_type,x
        tay
        lda en_speed_tab,y
        cmp #3
        bcc ?cl_done
        lda en_x,x
        bne ?cl_ok3
        lda enxhi,x
        beq ?cl_done
        dec enxhi,x
?cl_ok3 dec en_x,x
?cl_done jmp ?grav
?chase_r
        lda #0
        sta en_dir,x
        ; Wall check right (en_x + 16, chest height)
        lda en_x,x
        clc
        adc #16
        sta gt_px
        lda enxhi,x
        adc #0
        sta gt_px_hi
        lda en_y,x
        sec
        sbc #8
        sta gt_py
        jsr check_solid
        pha
        ldx zzidx
        pla
        bne ?cr_wall        ; wall → don't move
        inc en_x,x
        bne ?cr2
        inc enxhi,x
?cr2    inc en_x,x
        bne ?cr3
        inc enxhi,x
?cr3    lda en_type,x
        tay
        lda en_speed_tab,y
        cmp #3
        bcc ?cr_wall
        inc en_x,x
        bne ?cr_wall
        inc enxhi,x
?cr_wall jmp ?grav

?idle   ldx zzidx
        ; If alerted but lost LOS, patrol instead of standing
        lda en_cooldown,x
        bne ?do_patrol
        jmp ?grav               ; not alerted = truly idle
?do_patrol
        jmp ?patrol             ; alerted = keep moving
        ; --- Enemy gravity + vertical movement ---
?grav
        ; Apply vertical velocity
        lda envely,x
        beq ?no_vy
        bmi ?jump_up        ; negative velocity = jumping up
        ; Falling down: check for overflow
        clc
        adc en_y,x
        bcs ?kill_en        ; Y overflow
        cmp #240
        bcs ?kill_en        ; below screen
        sta en_y,x
        jmp ?vy_grav
?jump_up
        ; Jumping up: add negative velocity (won't kill)
        clc
        adc en_y,x
        sta en_y,x
        jmp ?vy_grav
?kill_en
        lda #0
        sta en_act,x        ; deactivate
        jmp ?nx
?vy_grav
        ; Add gravity to velocity
        lda envely,x
        cmp #MAXFALL
        bcs ?cap_vy
        inc envely,x
        jmp ?no_vy
?cap_vy lda #MAXFALL
        sta envely,x
?no_vy
        ; Skip floor check if on ground and no velocity (every 4th frame still checks)
        lda envely,x
        bne ?do_floor          ; has velocity → must check
        lda zfr
        and #$03
        bne ?nx                ; on ground, no velocity → skip 3 of 4 frames
?do_floor
        ; Floor check: tile at (center X, feet Y)
        lda en_x,x
        clc
        adc #8
        sta gt_px
        lda enxhi,x
        adc #0
        sta gt_px_hi
        lda en_y,x
        sta gt_py
        jsr check_solid_or_platform
        pha                 ; save result (A=solid flag)
        ldx zzidx           ; restore X (clobbered by check_solid)
        pla                 ; restore A + Z flag
        bne ?on_floor       ; solid below = on floor
        ; No floor: apply gravity if not already falling
        lda envely,x
        bne ?nx             ; already has velocity
        lda #1
        sta envely,x         ; start falling
        jmp ?nx
?on_floor
        ; Snap to tile top + stop falling
        lda en_y,x
        and #$F0
        sta en_y,x
        lda #0
        sta envely,x
        ; (Imp jump removed - not practical with current level design)
?nx     inx
        cpx #MAX_ENEMIES
        bcs ?done
        jmp ?lp
?done   rts

los_ecol dta 0
los_pcol dta 0
los_cur  dta 0
los_end  dta 0
.endp


