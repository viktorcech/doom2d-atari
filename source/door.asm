;==============================================
; DOOM2D - Door system
; door.asm
;
; Doors are tile-based (TILE_DOOR=4).
; Open = tile becomes empty (0), Close = tile becomes TILE_DOOR (4).
; Like D2DF: instant open/close, no animation.
; Auto-close after DOOR_TIMER frames.
; Key-colored doors require matching key in zpkeys.
;==============================================

MAX_DOORS       = 8
DOOR_TIMER_INIT = 150           ; ~2.5s at 60fps before auto-close
TILE_DOOR_ID    = 4
TILE_DOOR_RED   = 25
TILE_DOOR_BLUE  = 26
TILE_DOOR_YEL   = 27

; Door arrays
door_col    .ds MAX_DOORS       ; tile column (0-63)
door_row    .ds MAX_DOORS       ; tile row (0-31)
door_state  .ds MAX_DOORS       ; 0=closed, 1=open
door_timer  .ds MAX_DOORS       ; countdown to auto-close (0=inactive)
door_key    .ds MAX_DOORS       ; required key: 0=none, 1=red, 2=blue, 4=yellow
door_tile   .ds MAX_DOORS       ; original tile type (for close_door restore)
num_doors   dta 0               ; actual door count

; init_doors is in the overlay segment (end of main.asm)

; ============================================
; UPDATE DOORS - auto-close timer + player USE
; Called every frame from main loop
; ============================================
.proc update_doors
        ldx #0
?lp     cpx num_doors
        bcs ?done

        lda door_state,x
        beq ?next               ; closed, skip timer

        ; Door is open — countdown
        lda door_timer,x
        beq ?next               ; timer already 0
        dec door_timer,x
        bne ?next               ; not yet

        ; Timer expired — try to close
        ; Check if player is in door tile
        stx door_tmp_idx
        jsr check_player_in_door
        bne ?keep_open          ; player inside, don't close
        ldx door_tmp_idx
        jsr close_door
        jmp ?next2

?keep_open
        ldx door_tmp_idx
        lda #10                 ; retry in 10 frames
        sta door_timer,x

?next   inx
        jmp ?lp
?next2  inx
        jmp ?lp
?done   rts
.endp

; ============================================
; TRY OPEN DOOR - Player pressed USE near a door
; Called from player_update when USE is pressed
; ============================================
.proc try_open_door
        ; Find nearest closed door within range
        ; Player tile col = (zpx_hi:zpx + 8) / 16
        ; Player tile row = (zpy) / 16 and (zpy-16)/16 (head)
        ldx #0
?lp     cpx num_doors
        bcs ?none

        lda door_state,x
        bne ?nx                 ; already open, skip

        ; Check if player is adjacent to this door
        stx door_tmp_idx
        jsr check_player_near_door
        beq ?nx2                ; not near

        ; Found a closed door near player!
        ldx door_tmp_idx
        ; Key check
        lda door_key,x
        beq ?open_it            ; no key needed

        ; Check if player has required key
        and zpkeys
        cmp door_key,x
        beq ?open_it            ; has the key!

        ; No key — play denied sound
        stx zt2
        ldx #SFX_OOF
        jsr snd_play
        ldx zt2
        rts                     ; can't open

?open_it
        ; Check if this door is switch-only (linked as SW_ACT_DOOR target)
        jsr is_door_sw_only
        bne ?nx3                ; switch-only door, skip
        jsr open_door
        rts

?nx     inx
        jmp ?lp
?nx2    ldx door_tmp_idx
        inx
        jmp ?lp
?nx3    ldx door_tmp_idx
        inx
        jmp ?lp
?none   ; No door found — check for switch
        jsr try_use_switch
        rts
.endp

; ============================================
; OPEN DOOR - Set door to open state
; Input: X = door index
; ============================================
.proc open_door
        lda #1
        sta door_state,x
        lda #DOOR_TIMER_INIT
        sta door_timer,x

        ; Change map tile to empty (0)
        stx od_idx
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL

        ldy door_row,x
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldx od_idx
        ldy door_col,x
        lda #0                  ; empty tile
        sta (ztptr),y

        lda #0
        sta VBXE_BANK_SEL

        ; Mark dirty for redraw
        ldx od_idx
        jsr mark_door_dirty

        ; Play open sound
        stx zt2
        ldx #SFX_DOOROPN
        jsr snd_play
        ldx zt2
        rts
od_idx  dta 0
.endp

; ============================================
; RESTART CLOSE DOORS - restore all open door tiles in map
; Called before init_doors on level restart.
; ============================================
.proc restart_close_doors
        ldx #0
?lp     cpx num_doors
        bcs ?done
        lda door_state,x
        beq ?nx
        ; Door is open: restore original tile in map
        stx rcd_idx
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        ldy door_row,x
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldx rcd_idx
        ldy door_col,x
        lda door_tile,x
        sta (ztptr),y
        lda #0
        sta VBXE_BANK_SEL
        ldx rcd_idx
?nx     inx
        jmp ?lp
?done   rts
rcd_idx dta 0
.endp

; ============================================
; CLOSE DOOR
; Input: X = door index
; ============================================
.proc close_door
        lda #0
        sta door_state,x
        sta door_timer,x

        ; Change map tile back to door
        stx cd_idx
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL

        ldy door_row,x
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldx cd_idx
        ldy door_col,x
        lda door_tile,x         ; restore original tile type (colored)
        sta (ztptr),y

        lda #0
        sta VBXE_BANK_SEL

        ; Mark dirty for redraw
        ldx cd_idx
        jsr mark_door_dirty

        ; Play close sound
        stx zt2
        ldx #SFX_DOORCLS
        jsr snd_play
        ldx zt2
        rts
cd_idx  dta 0
.endp

; ============================================
; CHECK PLAYER NEAR DOOR
; Input: door_tmp_idx = door index
; Output: A != 0 if player is adjacent
; ============================================
.proc check_player_near_door
        ; Player feet tile
        lda zpy
        lsr
        lsr
        lsr
        lsr
        sta cpn_prow            ; player row (feet)

        ; Player center col (16-bit)
        jsr get_player_center_col
        sta cpn_pcol            ; player column

        ldx door_tmp_idx
        ; Check column: player must be in same col or adjacent (±1)
        lda cpn_pcol
        sec
        sbc door_col,x
        bpl ?cp1
        eor #$FF
        clc
        adc #1
?cp1    cmp #2                  ; within 2 columns
        bcs ?no

        ; Check row: player feet or head must be at door row
        ; Head row = (zpy - 16) / 16
        lda zpy
        sec
        sbc #16
        lsr
        lsr
        lsr
        lsr
        sta cpn_hrow            ; player head row

        ldx door_tmp_idx
        lda cpn_prow
        cmp door_row,x
        beq ?yes
        lda cpn_hrow
        cmp door_row,x
        beq ?yes
        ; Also check row+1 (door might be above player)
        lda door_row,x
        clc
        adc #1
        cmp cpn_prow
        beq ?yes
?no     lda #0
        rts
?yes    lda #1
        rts
cpn_pcol dta 0
cpn_prow dta 0
cpn_hrow dta 0
.endp

; ============================================
; CHECK PLAYER IN DOOR (for close safety)
; Input: door_tmp_idx = door index
; Output: A != 0 if player occupies door tile
; ============================================
.proc check_player_in_door
        ; Player center col
        jsr get_player_center_col
        sta cpid_pcol

        ldx door_tmp_idx
        lda cpid_pcol
        cmp door_col,x
        bne ?no

        ; Same column — check Y overlap
        ; Player occupies rows from (zpy-24)/16 to zpy/16
        lda zpy
        lsr
        lsr
        lsr
        lsr
        sta cpid_frow
        lda zpy
        sec
        sbc #24
        lsr
        lsr
        lsr
        lsr
        sta cpid_hrow

        ldx door_tmp_idx
        lda door_row,x
        cmp cpid_hrow
        bcc ?no                 ; door above player head
        cmp cpid_frow
        beq ?yes
        bcc ?yes                ; door row between head and feet
?no     lda #0
        rts
?yes    lda #1
        rts
cpid_pcol dta 0
cpid_frow dta 0
cpid_hrow dta 0
.endp

; ============================================
; MARK DOOR TILE AS DIRTY
; Input: X = door index (preserved)
; ============================================
.proc mark_door_dirty
        stx mdd_idx
        ; Mark dirty in BOTH buffers (double buffering)
        ldx mdd_idx
        ldy door_row,x
        lda row_x20,y
        clc
        adc door_col,x
        tay
        lda #1
        sta dirty_0,y
        sta dirty_1,y
        ; Update scan bbox for both buffers
        sta scan_any_0
        sta scan_any_1
        ldx mdd_idx
        lda door_col,x
        cmp scan_min_col_0
        bcs ?a
        sta scan_min_col_0
?a      cmp scan_min_col_1      ; fix: conditional update for buf1 (was unconditional)
        bcs ?a2
        sta scan_min_col_1
?a2     lda door_col,x
        cmp scan_max_col_0
        bcc ?b
        sta scan_max_col_0
?b      cmp scan_max_col_1
        bcc ?c
        sta scan_max_col_1
?c      lda door_row,x
        cmp scan_min_row_0
        bcs ?d
        sta scan_min_row_0
?d      cmp scan_min_row_1
        bcs ?e
        sta scan_min_row_1
?e      lda door_row,x
        cmp scan_max_row_0
        bcc ?f
        sta scan_max_row_0
?f      cmp scan_max_row_1
        bcc ?g
        sta scan_max_row_1
?g      ldx mdd_idx
        rts
mdd_idx dta 0
.endp

; Shared temp vars for door routines
door_tmp_idx    dta 0


