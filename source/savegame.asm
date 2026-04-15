;==============================================
; DOOM2D - Save/Load game (SIO sector write/read)
; savegame.asm
;
; 3 save slots, each SAVE_SECTORS sectors on ATR.
; Slot submenu shown before save/load.
;==============================================

SAVE_MAGIC1     = $44           ; 'D'
SAVE_MAGIC2     = $32           ; '2'
SAVE_SECTORS    = 11            ; sectors per slot
NUM_SLOTS       = 3
SLOT_MENU_Y     = 80
SLOT_MENU_X     = 104

; Slot info (read from disk headers)
slot_level  dta 0,0,0           ; level number per slot (0-based)
slot_valid  dta 0,0,0           ; 1=has save, 0=empty
slot_sel    dta 0               ; current slot selection (0-2)
slot_prev   dta 0               ; previous selection (for redraw)
slot_mode   dta 0               ; 0=save, 1=load

;==============================================
; SAVE GAME MENU — show slot submenu, save to chosen slot
; Returns: nothing (stays in pause menu after)
;==============================================
.proc save_game_menu
        lda #0
        sta slot_mode           ; mode=save
        jsr read_slot_headers
        jsr slot_submenu
        bcs ?cancel             ; C=1: user cancelled
        ; Save to selected slot
        jsr save_game
?cancel rts
.endp

;==============================================
; LOAD GAME MENU — show slot submenu, load from chosen slot
; Returns: A=0 success, A=1 cancel/error
;==============================================
.proc load_game_menu
        lda #1
        sta slot_mode           ; mode=load
        jsr read_slot_headers
        jsr slot_submenu
        bcs ?cancel             ; C=1: user cancelled
        ; Load from selected slot
        jsr load_game
        rts                     ; A=0 on success
?cancel lda #1
        rts
.endp

;==============================================
; SLOT SUBMENU — joystick/keyboard slot selection
; Returns: C=0 slot chosen (slot_sel), C=1 cancelled
;==============================================
.proc slot_submenu
        lda #0
        sta slot_sel
        sta slot_prev
        sta $02FC               ; clear keyboard
        ; Play enter sound (after SIO in read_slot_headers)
        ldx #SFX_PISTOL
        jsr snd_play
        ; Draw on both buffers
        jsr slot_draw_both

?loop   lda RTCLOK3
?vs     cmp RTCLOK3
        beq ?vs

        ; ESC = cancel
        lda $02FC
        cmp #$1C
        bne ?no_esc
        jmp ?esc
?no_esc
        ; RETURN = confirm
        cmp #$0C
        bne ?no_ret
        lda #$FF
        sta $02FC
        jmp ?confirm
?no_ret
        ; Keyboard up/down
        cmp #$0E
        beq ?kup
        cmp #$8E
        beq ?kup
        cmp #$0F
        beq ?kdn
        cmp #$8F
        beq ?kdn

        ; Joystick
        lda PORTA
        eor #$FF
        sta sm_joy
        and #J_UP
        beq ?no_jup
        lda sm_prev
        and #J_UP
        bne ?no_jup
        lda slot_sel
        beq ?no_jup
        dec slot_sel
?no_jup lda sm_joy
        and #J_DOWN
        beq ?no_jdn
        lda sm_prev
        and #J_DOWN
        bne ?no_jdn
        lda slot_sel
        cmp #NUM_SLOTS-1
        bcs ?no_jdn
        inc slot_sel
?no_jdn lda sm_joy
        sta sm_prev

        ; Fire = confirm
        lda TRIG0
        bne ?no_fire
        ; wait release
?fr_rel lda TRIG0
        beq ?fr_rel
        jmp ?confirm
?no_fire
        ; Redraw if selection changed
        lda slot_sel
        cmp slot_prev
        beq ?loop
        ldx #SFX_PISTOL
        jsr snd_play
        jsr slot_draw_both
        lda slot_sel
        sta slot_prev
        jmp ?loop

?kup    lda #$FF
        sta $02FC
        lda slot_sel
        bne ?do_kup
        jmp ?loop
?do_kup dec slot_sel
        jmp ?loop
?kdn    lda #$FF
        sta $02FC
        lda slot_sel
        cmp #NUM_SLOTS-1
        bcc ?do_kdn
        jmp ?loop
?do_kdn inc slot_sel
        jmp ?loop

?confirm
        ; In load mode, check if selected slot is valid
        lda slot_mode
        beq ?ok                 ; save mode: any slot is fine
        ldx slot_sel
        lda slot_valid,x
        bne ?ok
        jmp ?loop               ; empty slot, can't load — stay in menu
?ok     ldx #SFX_PISTOL
        jsr snd_play
        clc                     ; C=0 = confirmed
        rts

?esc    lda #$FF
        sta $02FC
        ldx #SFX_SWTCHX
        jsr snd_play
        sec                     ; C=1 = cancelled
        rts

sm_joy  dta 0
sm_prev dta 0
.endp

;==============================================
; DRAW SLOT MENU ON BOTH BUFFERS
;==============================================
.proc slot_draw_both
        jsr clear_menu_area
        jsr slot_draw
        jsr wait_blit
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        jsr clear_menu_area
        jsr slot_draw
        jsr wait_blit
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        rts
.endp

;==============================================
; DRAW SLOT MENU (title + 3 slot lines + cursor)
;==============================================
.proc slot_draw
        ; Title: "SAVE" or "LOAD"
        lda slot_mode
        bne ?load_title
        lda #<txt_save_title
        sta txt_ptr
        lda #>txt_save_title
        jmp ?draw_title
?load_title
        lda #<txt_load_title
        sta txt_ptr
        lda #>txt_load_title
?draw_title
        sta txt_ptr+1
        lda #SLOT_MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #SLOT_MENU_Y
        sta zdy
        jsr draw_text

        ; 3 slot lines
        ldx #0
?slot_lp
        stx sd_idx
        ; Y position = SLOT_MENU_Y + 16 + idx*16
        txa
        asl
        asl
        asl
        asl
        clc
        adc #SLOT_MENU_Y+16
        sta zdy

        ; Cursor for selected slot
        lda sd_idx
        cmp slot_sel
        bne ?no_cursor
        lda #SLOT_MENU_X-16
        sta zdx
        lda #0
        sta zdxh
        lda #11                 ; cursor char '>'
        jsr blit_hud_char
?no_cursor

        ; Slot number: "1 " / "2 " / "3 "
        lda sd_idx
        clc
        adc #'1'
        sta sd_numbuf
        lda #<sd_numbuf
        sta txt_ptr
        lda #>sd_numbuf
        sta txt_ptr+1
        lda #SLOT_MENU_X
        sta zdx
        lda #0
        sta zdxh
        jsr draw_text

        ; Slot status: "EMPTY" or "MAP X"
        ldx sd_idx
        lda slot_valid,x
        beq ?empty
        ; Valid save: "MAP " + digit
        lda slot_level,x
        clc
        adc #'1'                ; level 0 = "MAP 1"
        sta sd_mapnum
        lda #<sd_mapstr
        sta txt_ptr
        lda #>sd_mapstr
        jmp ?draw_status
?empty  lda #<txt_empty_slot
        sta txt_ptr
        lda #>txt_empty_slot
?draw_status
        sta txt_ptr+1
        lda #SLOT_MENU_X+24
        sta zdx
        lda #0
        sta zdxh
        jsr draw_text

        ldx sd_idx
        inx
        cpx #NUM_SLOTS
        bcs ?slots_done
        jmp ?slot_lp
?slots_done
        rts

sd_idx    dta 0
sd_numbuf dta '1',' ',0
sd_mapstr dta 'MAP '
sd_mapnum dta '1',0
.endp

;==============================================
; READ SLOT HEADERS — read first sector of each slot, check magic
;==============================================
.proc read_slot_headers
        ; Disable sound IRQ for SIO
        lda #0
        sta snd_active
        sta AUDC4
        lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN

        ldx #0
?slot_lp
        stx rsh_idx
        ; Calculate sector for slot X: SAVE_SEC1 + X * SAVE_SECTORS
        lda #<SAVE_SEC1
        sta DAUX1
        lda #>SAVE_SEC1
        sta DAUX2
        cpx #0
        beq ?sec_ok
?add_lp lda DAUX1
        clc
        adc #SAVE_SECTORS
        sta DAUX1
        bcc ?no_hi
        inc DAUX2
?no_hi  dex
        bne ?add_lp
?sec_ok
        ; Read 1 sector into LVL_BUF
        lda #<LVL_BUF
        sta DBUFLO
        lda #>LVL_BUF
        sta DBUFHI
        lda #$31
        sta DDEVIC
        lda #$01
        sta DUNIT
        lda #$52
        sta DCOMND
        lda #$40
        sta DSTATS
        lda #128
        sta DBYTLO
        lda #0
        sta DBYTHI
        lda #$07
        sta DTIMLO
        jsr SIOV
        bpl ?rd_ok
        ; SIO error: mark slot as empty
        ldx rsh_idx
        lda #0
        sta slot_valid,x
        jmp ?next
?rd_ok
        ; Check magic
        ldx rsh_idx
        lda LVL_BUF
        cmp #SAVE_MAGIC1
        bne ?inv
        lda LVL_BUF+1
        cmp #SAVE_MAGIC2
        bne ?inv
        ; Valid save
        lda #1
        sta slot_valid,x
        lda LVL_BUF+2
        sta slot_level,x
        jmp ?next
?inv    lda #0
        sta slot_valid,x
?next   ldx rsh_idx
        inx
        cpx #NUM_SLOTS
        bcs ?rsh_done
        jmp ?slot_lp
?rsh_done
        ; Re-enable sound IRQ
        lda POKMSK
        ora #$01
        sta POKMSK
        sta IRQEN
        rts

rsh_idx dta 0
.endp

;==============================================
; SAVE GAME — serialize state to LVL_BUF, write to selected slot
; Returns: A=0 success, A=1 error
;==============================================
.proc save_game
        ; --- Disable display and sound for clean SIO ---
        lda #0
        sta SDMCTL
        sta VBXE_VCTL
        sta snd_active
        sta AUDC4
        lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN

        ; --- Serialize state to LVL_BUF ---
        lda #<LVL_BUF
        sta zsrc
        lda #>LVL_BUF
        sta zsrc+1

        ; Header: magic + level
        ldy #0
        lda #SAVE_MAGIC1
        sta (zsrc),y
        iny
        lda #SAVE_MAGIC2
        sta (zsrc),y
        iny
        lda current_level
        sta (zsrc),y
        iny

        ; Player zero-page vars (13 bytes)
        lda zpx
        sta (zsrc),y
        iny
        lda zpx_hi
        sta (zsrc),y
        iny
        lda zpy
        sta (zsrc),y
        iny
        lda zpvx
        sta (zsrc),y
        iny
        lda zpvy
        sta (zsrc),y
        iny
        lda zpdir
        sta (zsrc),y
        iny
        lda zpst
        sta (zsrc),y
        iny
        lda zpan
        sta (zsrc),y
        iny
        lda zphp
        sta (zsrc),y
        iny
        lda zpammo
        sta (zsrc),y
        iny
        lda zpgnd
        sta (zsrc),y
        iny
        lda zparmor
        sta (zsrc),y
        iny
        lda zpkeys
        sta (zsrc),y
        iny

        ; Weapons (6 bytes)
        lda zpweap
        sta (zsrc),y
        iny
        lda zpshells
        sta (zsrc),y
        iny
        lda zprockets
        sta (zsrc),y
        iny
        lda zpcells
        sta (zsrc),y
        iny
        lda zpwcur
        sta (zsrc),y
        iny
        lda zpwcool
        sta (zsrc),y
        iny

        ; Player timers (2 bytes)
        lda pl_dead_timer
        sta (zsrc),y
        iny
        lda pl_pain_timer
        sta (zsrc),y
        iny

        ; Entity counts (4 bytes)
        lda num_en
        sta (zsrc),y
        iny
        lda num_pk
        sta (zsrc),y
        iny
        lda num_dc
        sta (zsrc),y
        iny
        lda num_doors
        sta (zsrc),y
        iny

        ; num_switches + level_complete (2 bytes)
        lda num_switches
        sta (zsrc),y
        iny
        lda level_complete
        sta (zsrc),y
        iny
        sty sv_off
        lda #0
        sta sv_off+1

        ; --- Copy arrays via loop helper ---
        ; Enemy arrays: 17 arrays × MAX_ENEMIES
        ldx #MAX_ENEMIES
        lda #<en_x
        ldy #>en_x
        jsr sv_copy_array
        lda #<enxhi
        ldy #>enxhi
        jsr sv_copy_array
        lda #<en_y
        ldy #>en_y
        jsr sv_copy_array
        lda #<en_dir
        ldy #>en_dir
        jsr sv_copy_array
        lda #<en_act
        ldy #>en_act
        jsr sv_copy_array
        lda #<en_hp
        ldy #>en_hp
        jsr sv_copy_array
        lda #<en_xmin
        ldy #>en_xmin
        jsr sv_copy_array
        lda #<en_xmax
        ldy #>en_xmax
        jsr sv_copy_array
        lda #<en_type
        ldy #>en_type
        jsr sv_copy_array
        lda #<en_cooldown
        ldy #>en_cooldown
        jsr sv_copy_array
        lda #<en_dtimer
        ldy #>en_dtimer
        jsr sv_copy_array
        lda #<envely
        ldy #>envely
        jsr sv_copy_array
        lda #<en_gib
        ldy #>en_gib
        jsr sv_copy_array
        lda #<envelx
        ldy #>envelx
        jsr sv_copy_array
        lda #<en_atk
        ldy #>en_atk
        jsr sv_copy_array
        lda #<en_tcnt
        ldy #>en_tcnt
        jsr sv_copy_array
        lda #<en_pain_tmr
        ldy #>en_pain_tmr
        jsr sv_copy_array

        ; Pickup arrays: 5 × MAX_PICKUPS(12)
        ldx #12
        lda #<pk_act
        ldy #>pk_act
        jsr sv_copy_array
        lda #<pk_x
        ldy #>pk_x
        jsr sv_copy_array
        lda #<pk_xhi
        ldy #>pk_xhi
        jsr sv_copy_array
        lda #<pk_y
        ldy #>pk_y
        jsr sv_copy_array
        lda #<pk_type
        ldy #>pk_type
        jsr sv_copy_array

        ; Door arrays: 6 × MAX_DOORS(8)
        ldx #8
        lda #<door_col
        ldy #>door_col
        jsr sv_copy_array
        lda #<door_row
        ldy #>door_row
        jsr sv_copy_array
        lda #<door_state
        ldy #>door_state
        jsr sv_copy_array
        lda #<door_timer
        ldy #>door_timer
        jsr sv_copy_array
        lda #<door_key
        ldy #>door_key
        jsr sv_copy_array
        lda #<door_tile
        ldy #>door_tile
        jsr sv_copy_array

        ; Decoration arrays: 8 × MAX_DECOR(8)
        ldx #8
        lda #<dc_act
        ldy #>dc_act
        jsr sv_copy_array
        lda #<dc_x
        ldy #>dc_x
        jsr sv_copy_array
        lda #<dc_xhi
        ldy #>dc_xhi
        jsr sv_copy_array
        lda #<dc_orig_tile
        ldy #>dc_orig_tile
        jsr sv_copy_array
        lda #<dc_y
        ldy #>dc_y
        jsr sv_copy_array
        lda #<dc_type
        ldy #>dc_type
        jsr sv_copy_array
        lda #<dc_hp
        ldy #>dc_hp
        jsr sv_copy_array
        lda #<dc_timer
        ldy #>dc_timer
        jsr sv_copy_array

        ; Switch arrays: 6 × MAX_SWITCHES(4)
        ldx #4
        lda #<sw_col
        ldy #>sw_col
        jsr sv_copy_array
        lda #<sw_row
        ldy #>sw_row
        jsr sv_copy_array
        lda #<sw_tgt_col
        ldy #>sw_tgt_col
        jsr sv_copy_array
        lda #<sw_tgt_row
        ldy #>sw_tgt_row
        jsr sv_copy_array
        lda #<sw_action
        ldy #>sw_action
        jsr sv_copy_array
        lda #<sw_timer
        ldy #>sw_timer
        jsr sv_copy_array

        ; --- Copy map data from VRAM (1024 bytes) ---
        jsr sv_copy_map_from_vram

        ; --- Calculate starting sector for selected slot ---
        jsr calc_slot_sector

        ; --- Write to disk via SIO ---
        lda #<LVL_BUF
        sta DBUFLO
        lda #>LVL_BUF
        sta DBUFHI
        ldx #SAVE_SECTORS
?wr_lp  stx sv_cnt
        lda #$31
        sta DDEVIC
        lda #$01
        sta DUNIT
        lda #$50            ; PUT (write without verify)
        sta DCOMND
        lda #$80            ; send data
        sta DSTATS
        lda #128
        sta DBYTLO
        lda #0
        sta DBYTHI
        lda #$07
        sta DTIMLO
        jsr SIOV
        bpl ?wr_ok
        jmp ?err
?wr_ok  lda DBUFLO
        clc
        adc #128
        sta DBUFLO
        bcc ?no_inc
        inc DBUFHI
?no_inc inc DAUX1
        bne ?no_aux
        inc DAUX2
?no_aux ldx sv_cnt
        dex
        bne ?wr_lp

        ; Success
        lda #0
        jmp ?re_snd

?err    lda #1

?re_snd pha
        lda POKMSK
        ora #$01
        sta POKMSK
        sta IRQEN
        lda #VC_XDL_ON+VC_NO_TRANS
        sta VBXE_VCTL
        pla
        rts
.endp

;==============================================
; LOAD GAME — read from selected slot, deserialize state
; Returns: A=0 success, A=1 error/no save
;==============================================
.proc load_game
        ; --- Disable display and sound for clean SIO ---
        lda #0
        sta SDMCTL
        sta VBXE_VCTL
        sta snd_active
        sta AUDC4
        lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN

        ; --- Calculate starting sector for selected slot ---
        jsr calc_slot_sector

        ; --- Read save sectors from disk ---
        lda #<LVL_BUF
        sta DBUFLO
        lda #>LVL_BUF
        sta DBUFHI
        ldx #SAVE_SECTORS
?rd_lp  stx sv_cnt
        lda #$31
        sta DDEVIC
        lda #$01
        sta DUNIT
        lda #$52            ; READ
        sta DCOMND
        lda #$40            ; receive data
        sta DSTATS
        lda #128
        sta DBYTLO
        lda #0
        sta DBYTHI
        lda #$07
        sta DTIMLO
        jsr SIOV
        bpl ?rd_ok
        jmp ?err
?rd_ok  lda DBUFLO
        clc
        adc #128
        sta DBUFLO
        bcc ?no_inc
        inc DBUFHI
?no_inc inc DAUX1
        bne ?no_aux
        inc DAUX2
?no_aux ldx sv_cnt
        dex
        bne ?rd_lp

        ; --- Check magic ---
        lda LVL_BUF
        cmp #SAVE_MAGIC1
        beq ?m1ok
        jmp ?err
?m1ok   lda LVL_BUF+1
        cmp #SAVE_MAGIC2
        beq ?m2ok
        jmp ?err
?m2ok

        ; --- Deserialize state from LVL_BUF ---
        lda #<LVL_BUF
        sta zsrc
        lda #>LVL_BUF
        sta zsrc+1

        ldy #2
        lda (zsrc),y
        sta current_level
        iny

        ; Player zero-page vars
        lda (zsrc),y
        sta zpx
        iny
        lda (zsrc),y
        sta zpx_hi
        iny
        lda (zsrc),y
        sta zpy
        iny
        lda (zsrc),y
        sta zpvx
        iny
        lda (zsrc),y
        sta zpvy
        iny
        lda (zsrc),y
        sta zpdir
        iny
        lda (zsrc),y
        sta zpst
        iny
        lda (zsrc),y
        sta zpan
        iny
        lda (zsrc),y
        sta zphp
        iny
        lda (zsrc),y
        sta zpammo
        iny
        lda (zsrc),y
        sta zpgnd
        iny
        lda (zsrc),y
        sta zparmor
        iny
        lda (zsrc),y
        sta zpkeys
        iny

        ; Weapons
        lda (zsrc),y
        sta zpweap
        iny
        lda (zsrc),y
        sta zpshells
        iny
        lda (zsrc),y
        sta zprockets
        iny
        lda (zsrc),y
        sta zpcells
        iny
        lda (zsrc),y
        sta zpwcur
        iny
        lda (zsrc),y
        sta zpwcool
        iny

        ; Player timers
        lda (zsrc),y
        sta pl_dead_timer
        iny
        lda (zsrc),y
        sta pl_pain_timer
        iny

        ; Entity counts
        lda (zsrc),y
        sta num_en
        iny
        lda (zsrc),y
        sta num_pk
        iny
        lda (zsrc),y
        sta num_dc
        iny
        lda (zsrc),y
        sta num_doors
        iny

        ; Switches + level_complete
        lda (zsrc),y
        sta num_switches
        iny
        lda (zsrc),y
        sta level_complete
        iny
        sty sv_off
        lda #0
        sta sv_off+1

        ; --- Restore arrays ---
        ldx #MAX_ENEMIES
        lda #<en_x
        ldy #>en_x
        jsr ld_copy_array
        lda #<enxhi
        ldy #>enxhi
        jsr ld_copy_array
        lda #<en_y
        ldy #>en_y
        jsr ld_copy_array
        lda #<en_dir
        ldy #>en_dir
        jsr ld_copy_array
        lda #<en_act
        ldy #>en_act
        jsr ld_copy_array
        lda #<en_hp
        ldy #>en_hp
        jsr ld_copy_array
        lda #<en_xmin
        ldy #>en_xmin
        jsr ld_copy_array
        lda #<en_xmax
        ldy #>en_xmax
        jsr ld_copy_array
        lda #<en_type
        ldy #>en_type
        jsr ld_copy_array
        lda #<en_cooldown
        ldy #>en_cooldown
        jsr ld_copy_array
        lda #<en_dtimer
        ldy #>en_dtimer
        jsr ld_copy_array
        lda #<envely
        ldy #>envely
        jsr ld_copy_array
        lda #<en_gib
        ldy #>en_gib
        jsr ld_copy_array
        lda #<envelx
        ldy #>envelx
        jsr ld_copy_array
        lda #<en_atk
        ldy #>en_atk
        jsr ld_copy_array
        lda #<en_tcnt
        ldy #>en_tcnt
        jsr ld_copy_array
        lda #<en_pain_tmr
        ldy #>en_pain_tmr
        jsr ld_copy_array

        ldx #12
        lda #<pk_act
        ldy #>pk_act
        jsr ld_copy_array
        lda #<pk_x
        ldy #>pk_x
        jsr ld_copy_array
        lda #<pk_xhi
        ldy #>pk_xhi
        jsr ld_copy_array
        lda #<pk_y
        ldy #>pk_y
        jsr ld_copy_array
        lda #<pk_type
        ldy #>pk_type
        jsr ld_copy_array

        ldx #8
        lda #<door_col
        ldy #>door_col
        jsr ld_copy_array
        lda #<door_row
        ldy #>door_row
        jsr ld_copy_array
        lda #<door_state
        ldy #>door_state
        jsr ld_copy_array
        lda #<door_timer
        ldy #>door_timer
        jsr ld_copy_array
        lda #<door_key
        ldy #>door_key
        jsr ld_copy_array
        lda #<door_tile
        ldy #>door_tile
        jsr ld_copy_array

        ldx #8
        lda #<dc_act
        ldy #>dc_act
        jsr ld_copy_array
        lda #<dc_x
        ldy #>dc_x
        jsr ld_copy_array
        lda #<dc_xhi
        ldy #>dc_xhi
        jsr ld_copy_array
        lda #<dc_orig_tile
        ldy #>dc_orig_tile
        jsr ld_copy_array
        lda #<dc_y
        ldy #>dc_y
        jsr ld_copy_array
        lda #<dc_type
        ldy #>dc_type
        jsr ld_copy_array
        lda #<dc_hp
        ldy #>dc_hp
        jsr ld_copy_array
        lda #<dc_timer
        ldy #>dc_timer
        jsr ld_copy_array

        ldx #4
        lda #<sw_col
        ldy #>sw_col
        jsr ld_copy_array
        lda #<sw_row
        ldy #>sw_row
        jsr ld_copy_array
        lda #<sw_tgt_col
        ldy #>sw_tgt_col
        jsr ld_copy_array
        lda #<sw_tgt_row
        ldy #>sw_tgt_row
        jsr ld_copy_array
        lda #<sw_action
        ldy #>sw_action
        jsr ld_copy_array
        lda #<sw_timer
        ldy #>sw_timer
        jsr ld_copy_array

        ; --- Restore map to VRAM ---
        jsr sv_copy_map_to_vram

        ; --- Clear projectiles ---
        ldx #MAX_PROJ-1
?clr_p  lda #0
        sta proj_a,x
        dex
        bpl ?clr_p
        ldx #MAX_EPROJ-1
?clr_e  lda #0
        sta eproj_a,x
        dex
        bpl ?clr_e

        ; Success
        lda #0
        jmp ?re_snd

?err    lda #1

?re_snd pha
        lda POKMSK
        ora #$01
        sta POKMSK
        sta IRQEN
        lda #VC_XDL_ON+VC_NO_TRANS
        sta VBXE_VCTL
        pla
        rts
.endp

;==============================================
; Calculate sector number for selected slot → DAUX1/DAUX2
; Sector = SAVE_SEC1 + slot_sel * SAVE_SECTORS
;==============================================
.proc calc_slot_sector
        lda #<SAVE_SEC1
        sta DAUX1
        lda #>SAVE_SEC1
        sta DAUX2
        ldx slot_sel
        beq ?done
?add_lp lda DAUX1
        clc
        adc #SAVE_SECTORS
        sta DAUX1
        bcc ?no_hi
        inc DAUX2
?no_hi  dex
        bne ?add_lp
?done   rts
.endp

;==============================================
; HELPERS (unchanged)
;==============================================
.proc sv_copy_array
        sta ztptr
        sty ztptr+1
        stx sv_len
        lda #<LVL_BUF
        clc
        adc sv_off
        sta zsrc
        lda #>LVL_BUF
        adc sv_off+1
        sta zsrc+1
        ldy #0
?lp     lda (ztptr),y
        sta (zsrc),y
        iny
        cpy sv_len
        bne ?lp
        lda sv_off
        clc
        adc sv_len
        sta sv_off
        lda sv_off+1
        adc #0
        sta sv_off+1
        rts
.endp

.proc ld_copy_array
        sta ztptr
        sty ztptr+1
        stx sv_len
        lda #<LVL_BUF
        clc
        adc sv_off
        sta zsrc
        lda #>LVL_BUF
        adc sv_off+1
        sta zsrc+1
        ldy #0
?lp     lda (zsrc),y
        sta (ztptr),y
        iny
        cpy sv_len
        bne ?lp
        lda sv_off
        clc
        adc sv_len
        sta sv_off
        lda sv_off+1
        adc #0
        sta sv_off+1
        rts
.endp

.proc sv_copy_map_from_vram
        lda #$90+MC_CPU
        sta VBXE_MEMAC_CTRL
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        lda #<LVL_BUF
        clc
        adc sv_off
        sta ztptr
        lda #>LVL_BUF
        adc sv_off+1
        sta ztptr+1
        lda #>MEMW
        sta ?rd+2
        ldx #4
?pg     ldy #0
?rd     lda MEMW,y
        sta (ztptr),y
        iny
        bne ?rd
        inc ztptr+1
        inc ?rd+2
        dex
        bne ?pg
        lda #>MEMW
        sta ?rd+2
        lda #0
        sta VBXE_BANK_SEL
        lda sv_off
        clc
        adc #<1024
        sta sv_off
        lda sv_off+1
        adc #>1024
        sta sv_off+1
        rts
.endp

.proc sv_copy_map_to_vram
        lda #$90+MC_CPU
        sta VBXE_MEMAC_CTRL
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        lda #<LVL_BUF
        clc
        adc sv_off
        sta ztptr
        lda #>LVL_BUF
        adc sv_off+1
        sta ztptr+1
        lda #>MEMW
        sta ?wr+2
        ldx #4
?pg     ldy #0
?lp     lda (ztptr),y
?wr     sta MEMW,y
        iny
        bne ?lp
        inc ztptr+1
        inc ?wr+2
        dex
        bne ?pg
        lda #>MEMW
        sta ?wr+2
        lda #0
        sta VBXE_BANK_SEL
        lda sv_off
        clc
        adc #<1024
        sta sv_off
        lda sv_off+1
        adc #>1024
        sta sv_off+1
        rts
.endp

;==============================================
; Text data
;==============================================
txt_save_title  dta c'SAVE    ',0
txt_load_title  dta c'LOAD    ',0
txt_empty_slot  dta c'EMPTY',0

;==============================================
; Shared temp vars
;==============================================
sv_off  dta a(0)
sv_cnt  dta 0
sv_len  dta 0
