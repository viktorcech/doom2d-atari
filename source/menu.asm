;==============================================
; DOOM2D - Title screen & menu system
; menu.asm
;
; Unified menu: both title and pause use same loop/drawing.
; Items: NEW GAME, SETTINGS, SAVE, LOAD, CREDITS
;==============================================

txt_ptr = $84               ; 2b pointer for text rendering

; ============================================
; CONSTANTS & STATE
; ============================================
MENU_BKP_VRAM = $070000
MENU_X      = 112
MENU_Y      = 80
MENU_SPACE  = 16
MENU_ITEMS  = 5

menu_sel    dta 0
menu_prev   dta 0
draw_mode   dta 0           ; 0=draw_menu, 1=draw_settings
menu_result dta 0           ; 0=new game, 2=load game, $FF=ESC
menu_mode   dta 0           ; 0=title screen, 1=pause (has SAVE)

; ============================================
; OPEN MENU — init state, backup screen, draw
; ============================================
.proc menu_open
        lda #0
        sta menu_sel
        sta menu_prev
        sta draw_mode
        jsr backup_menu_area
        jsr redraw_both
        rts
.endp

; ============================================
; CLOSE MENU — restore screen on both buffers
; ============================================
.proc menu_close
        jsr restore_menu_area
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        jsr restore_menu_area
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        rts
.endp

; ============================================
; TITLE SCREEN (called from main)
; Returns when user picks NEW GAME or LOAD GAME
; menu_result: 0=new game, 2=load
; ============================================
.proc menu_title_screen
?wait_release
        lda PORTA
        eor #$FF
        and #$0F
        bne ?wait_release
        lda TRIG0
        beq ?wait_release
        lda #$FF
        sta $02FC
        ldx #10
?dly    lda RTCLOK3
?dly2   cmp RTCLOK3
        beq ?dly2
        dex
        bne ?dly
        lda #$FF
        sta $02FC
?wait_key
        lda RTCLOK3
?wk_vs  cmp RTCLOK3
        beq ?wk_vs
        lda $02FC
        cmp #$FF
        beq ?chk_joy
        jmp ?got_input
?chk_joy
        lda PORTA
        eor #$FF
        and #$0F
        bne ?got_input
        lda TRIG0
        beq ?got_input
        jmp ?wait_key
?got_input
        lda #$FF
        sta $02FC
        lda #0
        sta menu_mode           ; title mode (no SAVE)
        ldx #SFX_SWTCHN
        jsr snd_play
        jsr menu_open

        jsr menu_common_loop
        lda menu_result
        cmp #$FF
        bne ?done
        ; ESC on title: close menu, go back to wait
        ldx #SFX_SWTCHX
        jsr snd_play
        jsr menu_close
        jmp ?wait_release
?done   rts
.endp

; ============================================
; PAUSE MENU (called from game loop)
; Returns: A = 0 resume, 1 new game, 2 load game
; ============================================
.proc menu_pause
        lda #0
        sta snd_active
        sta snd_lock
        sta AUDC4
        lda #1
        sta menu_mode           ; pause mode (has SAVE)
        ldx #SFX_SWTCHN
        jsr snd_play
        jsr menu_open

        jsr menu_common_loop
        lda menu_result
        cmp #$FF
        beq ?resume
        cmp #0
        beq ?new_game
        rts                     ; A=2 load game
?new_game
        lda #1
        rts
?resume
        ldx #SFX_SWTCHX
        jsr snd_play
        jsr menu_close
        lda #0
        rts
.endp

; ============================================
; COMMON MENU LOOP — shared input/selection handling
; Sets menu_result: 0=new game, 2=load, $FF=ESC
; ============================================
.proc menu_common_loop
?loop   jsr update_menu
        lda menu_sel
        cmp menu_prev
        beq ?no_redraw
        ldx #SFX_PISTOL
        jsr snd_play
        jsr redraw_both
        lda menu_sel
        sta menu_prev
?no_redraw
        lda RTCLOK3
?vs     cmp RTCLOK3
        beq ?vs

        ; ESC
        lda $02FC
        cmp #$1C
        bne ?no_esc
        lda #$FF
        sta $02FC
        sta menu_result
        rts
?no_esc
        ; RETURN
        cmp #$0C
        bne ?chk_fire
        lda #$FF
        sta $02FC
        jmp ?handle_sel
?chk_fire
        lda TRIG0
        bne ?loop
?fr_rel lda TRIG0
        beq ?fr_rel

?handle_sel
        lda #$FF
        sta $02FC
        ldx #SFX_PISTOL
        jsr snd_play

        lda menu_sel
        ; 0 = NEW GAME
        cmp #0
        bne ?not_ng
        sta menu_result
        rts
?not_ng
        ; 1 = SETTINGS
        cmp #1
        bne ?not_set
        jsr menu_settings
        jsr redraw_both
        jmp ?loop
?not_set
        ; 2 = SAVE (pause) or LOAD (title)
        cmp #2
        bne ?not_2
        lda menu_mode
        beq ?title_load         ; title mode: sel 2 = LOAD
        ; Pause: sel 2 = SAVE
        jsr save_game_menu
        jsr redraw_both
        jmp ?loop
?title_load
        jsr load_game_menu
        cmp #0
        bne ?tl_fail
        lda #2
        sta menu_result
        rts
?tl_fail jsr redraw_both
        jmp ?loop
?not_2
        ; 3 = LOAD (pause) or CREDITS (title)
        cmp #3
        bne ?not_3
        lda menu_mode
        beq ?title_credits      ; title mode: sel 3 = CREDITS
        ; Pause: sel 3 = LOAD
        jsr load_game_menu
        cmp #0
        bne ?pl_fail
        lda #2
        sta menu_result
        rts
?pl_fail jsr redraw_both
        jmp ?loop
?title_credits
        jmp ?loop               ; credits (TODO)
?not_3
        ; 4 = CREDITS (pause only)
        jmp ?loop
.endp

; ============================================
; SETTINGS
; ============================================
.proc menu_settings
        lda #1
        sta draw_mode
        jsr redraw_both
?loop   lda RTCLOK3
?vs     cmp RTCLOK3
        beq ?vs
        lda $02FC
        cmp #$0C
        bne ?chk_esc
        lda #$FF
        sta $02FC
        jsr toggle_sound
        jsr redraw_both
?chk_esc
        lda $02FC
        cmp #$1C
        bne ?loop
        lda #$FF
        sta $02FC
        ldx #SFX_SWTCHX
        jsr snd_play
        lda #0
        sta draw_mode
        rts
.endp

; ============================================
; TOGGLE SOUND
; ============================================
.proc toggle_sound
        lda snd_enabled
        eor #1
        sta snd_enabled
        bne ?done
        lda #0
        sta snd_active
        sta AUDC4
?done   rts
.endp
