;==============================================
; DOOM2D - Switches and floor triggers
; switches.asm
;==============================================

; ============================================
; SWITCH SYSTEM
; ============================================
level_complete  dta 0           ; 1 = switch activated, level done

SW_AUTO_OFF     = 150           ; auto-off timer (~2.5 sec at 60fps)

; Switch auto-off timers (per switch slot)
sw_timer        :MAX_SWITCHES dta 0

; Switch found position (saved by search routine)
sw_found_col    dta 0
sw_found_row    dta 0

; TRY USE SWITCH - check tiles around player for switch (OFF or ON)
; Called when USE pressed and no door found
.proc try_use_switch
        ; Check right side: player center X + 16
        lda zpx
        clc
        adc #16
        sta gt_px
        lda zpx_hi
        adc #0
        sta gt_px_hi
        lda zpy
        sta gt_py
        jsr get_tile_at
        cmp #TILE_SWITCH_OFF
        bne ?r1
        jmp ?found_off
?r1     cmp #TILE_SWITCH_ON
        bne ?r2
        jmp ?found_on
?r2     ; Check left side: player center X - 8
        lda zpx
        sec
        sbc #8
        sta gt_px
        lda zpx_hi
        sbc #0
        sta gt_px_hi
        lda zpy
        sta gt_py
        jsr get_tile_at
        cmp #TILE_SWITCH_OFF
        bne ?l1
        jmp ?found_off
?l1     cmp #TILE_SWITCH_ON
        bne ?l2
        jmp ?found_on
?l2     ; Check head height right
        lda zpx
        clc
        adc #16
        sta gt_px
        lda zpx_hi
        adc #0
        sta gt_px_hi
        lda zpy
        sec
        sbc #16
        sta gt_py
        jsr get_tile_at
        cmp #TILE_SWITCH_OFF
        bne ?hr1
        jmp ?found_off
?hr1    cmp #TILE_SWITCH_ON
        bne ?hr2
        jmp ?found_on
?hr2    ; Check head height left
        lda zpx
        sec
        sbc #8
        sta gt_px
        lda zpx_hi
        sbc #0
        sta gt_px_hi
        lda zpy
        sec
        sbc #16
        sta gt_py
        jsr get_tile_at
        cmp #TILE_SWITCH_OFF
        bne ?hl1
        jmp ?found_off
?hl1    cmp #TILE_SWITCH_ON
        bne ?hl2
        jmp ?found_on
?hl2    ; Check at player feet (standing on switch)
        lda zpx
        sta gt_px
        lda zpx_hi
        sta gt_px_hi
        lda zpy
        sta gt_py
        jsr get_tile_at
        cmp #TILE_SWITCH_OFF
        bne ?f1
        jmp ?found_off
?f1     cmp #TILE_SWITCH_ON
        bne ?f2
        jmp ?found_on
?f2     ; Check at player head (overlapping switch above)
        lda zpx
        sta gt_px
        lda zpx_hi
        sta gt_px_hi
        lda zpy
        sec
        sbc #16
        sta gt_py
        jsr get_tile_at
        cmp #TILE_SWITCH_OFF
        bne ?nope
        jmp ?found_off
?nope   cmp #TILE_SWITCH_ON
        bne ?oof
        jmp ?found_on
?oof    ; No switch found — play OOF
        ldx #SFX_OOF
        jsr snd_play
        rts
?found_off
        ; Toggle switch OFF -> ON
        ldy #0
        lda #TILE_SWITCH_ON
        sta (ztptr),y
        ldx #SFX_SWTCHN        ; switch ON sound
        jmp ?do_action
?found_on
        ; Toggle switch ON -> OFF
        ldy #0
        lda #TILE_SWITCH_OFF
        sta (ztptr),y
        ldx #SFX_SWTCHX        ; switch OFF sound
?do_action
        ; Save switch tile position
        lda gt_col
        sta sw_found_col
        lda gt_row
        sta sw_found_row
        ; Mark switch tile dirty
        stx sw_sfx_tmp
        jsr mark_pos_dirty
        ; Play switch sound (unlock so it's not blocked)
        lda sw_sfx_tmp
        jsr play_sfx_unlock
        lda #8
        sta snd_lock            ; lock to prevent door sound overriding
        ; Set auto-off timer for this switch
        jsr sw_set_timer
        ; Look up switch in table and execute action
        jsr switch_do_target
        rts
sw_sfx_tmp dta 0
.endp

; ============================================
; MARK TILE AT (gt_col, gt_row) DIRTY
; ============================================
.proc mark_pos_dirty
        ldy gt_row
        lda row_x20,y
        clc
        adc gt_col
        tay
        lda #1
        sta dirty_0,y
        sta dirty_1,y
        rts
.endp

; ============================================
; IS DOOR SWITCH-ONLY?
; Input: X = door index (door_col[X], door_row[X])
; Output: Z=1 if normal door, Z=0 if switch-only
; Preserves X (door index)
; ============================================
.proc is_door_sw_only
        stx idsw_door
        ldy #0
?lp     cpy num_switches
        bcs ?no
        lda sw_action,y
        cmp #SW_ACT_DOOR
        beq ?chk
        cmp #SW_ACT_DOOR_LOCK
        beq ?chk
        cmp #SW_ACT_FLOOR
        beq ?chk
        jmp ?nx
?chk    ldx idsw_door
        lda sw_tgt_col,y
        cmp door_col,x
        bne ?nx
        lda sw_tgt_row,y
        cmp door_row,x
        bne ?nx
        ; Match — always locked
        ldx idsw_door
        lda #1              ; Z=0 locked
        rts
?nx     iny
        jmp ?lp
?no     ldx idsw_door
        lda #0              ; Z=1 can open
        rts
idsw_door dta 0
.endp

; ============================================
; SWITCH TARGET LOOKUP + EXECUTE
; Find switch at (sw_found_col, sw_found_row) in table,
; then execute action at target tile.
; ============================================
.proc switch_do_target
        ldx #0
?lp     cpx num_switches
        bcs ?no_match
        lda sw_col,x
        cmp sw_found_col
        bne ?next
        lda sw_row,x
        cmp sw_found_row
        bne ?next
        ; Found match at index X
        jmp ?exec
?next   inx
        bne ?lp             ; always branches (max 4)
?no_match
        ; No linked target — just toggle (legacy behavior)
        rts
?exec
        ; Load target position into r_col/r_row
        lda sw_tgt_col,x
        sta r_col
        sta gt_col
        lda sw_tgt_row,x
        sta r_row
        sta gt_row
        ; Save action type
        lda sw_action,x
        pha
        ; Calculate map pointer to target tile
        jsr calc_map_ptr
        ; Get action type
        pla
        ; Dispatch action
        cmp #SW_ACT_DOOR
        beq ?act_door
        cmp #SW_ACT_DOOR_LOCK
        beq ?act_door
        cmp #SW_ACT_WALL
        beq ?act_wall
        ; Default / SW_ACT_ELEV: future
        rts
?act_door
        ; Find door at target position in door table and open it
        ldx #0
?dlp    cpx num_doors
        bcs ?dno        ; door not found, bail
        lda door_col,x
        cmp gt_col
        bne ?dnx
        lda door_row,x
        cmp gt_row
        bne ?dnx
        ; Found door at index X — open via door system (timer + auto-close)
        jsr open_door
        rts
?dnx    inx
        jmp ?dlp
?dno    rts
?act_wall
        ; Remove wall: set target tile to empty (0)
        ldy #0
        lda #0
        sta (ztptr),y
        ; Mark target dirty
        jsr mark_pos_dirty
        ; Play switch sound
        ldx #SFX_SWTCHX
        jsr snd_play
        rts
.endp

; ============================================
; CHECK FLOOR TRIGGERS
; Called every frame. If player moved to a new tile,
; check if that tile is a trigger (linked empty tile).
; ============================================
ft_prev_col dta $FF             ; previous player tile col
ft_prev_row dta $FF             ; previous player tile row

.proc check_floor_triggers
        ; Compute current player tile col
        jsr get_player_tile_col
        sta ft_cur_col
        ; Player feet row
        lda zpy
        lsr
        lsr
        lsr
        lsr
        sta ft_cur_row
        ; Did player move to a new tile?
        lda ft_cur_col
        cmp ft_prev_col
        bne ?moved
        lda ft_cur_row
        cmp ft_prev_row
        beq ?done           ; same tile = skip
?moved  ; Update previous position
        lda ft_cur_col
        sta ft_prev_col
        lda ft_cur_row
        sta ft_prev_row
        ; Check feet row
        lda ft_cur_col
        sta sw_found_col
        lda ft_cur_row
        sta sw_found_row
        jsr ft_check_table
        ; Also check body row (feet - 1)
        lda ft_cur_row
        beq ?done
        sec
        sbc #1
        sta sw_found_row
        lda ft_cur_col
        sta sw_found_col
        jsr ft_check_table
?done   rts
ft_cur_col dta 0
ft_cur_row dta 0
.endp

; Find floor trigger at (sw_found_col, sw_found_row) — only SW_ACT_FLOOR
.proc ft_check_table
        ldx #0
?lp     cpx num_switches
        bcs ?no
        lda sw_action,x
        cmp #SW_ACT_FLOOR
        bne ?nx
        lda sw_col,x
        cmp sw_found_col
        bne ?nx
        lda sw_row,x
        cmp sw_found_row
        bne ?nx
        ; Match — execute target action (open door)
        lda sw_tgt_col,x
        sta r_col
        sta gt_col
        lda sw_tgt_row,x
        sta r_row
        sta gt_row
        jsr calc_map_ptr
        ; Find door and open it
        ldx #0
?dlp    cpx num_doors
        bcs ?no
        lda door_col,x
        cmp gt_col
        bne ?dnx
        lda door_row,x
        cmp gt_row
        bne ?dnx
        ; Only open if closed
        lda door_state,x
        bne ?no             ; already open, skip
        jsr open_door
        rts
?dnx    inx
        jmp ?dlp
?nx     inx
        jmp ?lp
?no     rts
.endp

; ============================================
; SW_SET_TIMER - find switch at sw_found_col/row, set auto-off timer
; ============================================
.proc sw_set_timer
        ldx #0
?lp     cpx num_switches
        bcs ?done
        lda sw_col,x
        cmp sw_found_col
        bne ?nx
        lda sw_row,x
        cmp sw_found_row
        bne ?nx
        ; Found — set timer
        lda #SW_AUTO_OFF
        sta sw_timer,x
        rts
?nx     inx
        jmp ?lp
?done   rts
.endp

; ============================================
; UPDATE SWITCHES - decrement auto-off timers
; Called every frame from main loop
; ============================================
.proc update_switches
        ldx #0
?lp     cpx num_switches
        bcs ?done
        lda sw_timer,x
        beq ?nx
        dec sw_timer,x
        bne ?nx
        ; Timer expired — turn switch OFF visually
        stx us_idx
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        ldy sw_row,x
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldy sw_col,x
        lda (ztptr),y
        cmp #TILE_SWITCH_ON
        bne ?skip               ; not ON, skip
        lda #TILE_SWITCH_OFF
        sta (ztptr),y
        ; Mark dirty for redraw
        ldx us_idx
        lda sw_col,x
        sta gt_col
        lda sw_row,x
        sta gt_row
        jsr mark_pos_dirty
?skip   lda #0
        sta VBXE_BANK_SEL
        ldx us_idx
?nx     inx
        jmp ?lp
?done   rts
us_idx  dta 0
.endp
