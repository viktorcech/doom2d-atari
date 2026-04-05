;==============================================
; DOOM2D - Title screen & menu system
; menu.asm
;==============================================

txt_ptr = $84               ; 2b pointer for text rendering

; ============================================
; CONSTANTS & STATE
; ============================================
MENU_BKP_VRAM = $070000        ; backup area for title menu background
MENU_X      = 112
MENU_Y      = 80
MENU_SPACE  = 16
MENU_ITEMS  = 3

menu_sel    dta 0
menu_prev   dta 0
draw_mode   dta 0           ; 0=draw_menu, 1=draw_settings

; ============================================
; TITLE SCREEN (called from main, returns when NEW GAME selected)
; ============================================
.proc menu_title_screen
?wait_release
        ; Wait until joystick and fire are released
        lda PORTA
        eor #$FF
        and #$0F
        bne ?wait_release
        lda TRIG0
        beq ?wait_release
        lda #$FF
        sta $02FC               ; clear keyboard
        ; Small delay to debounce
        ldx #10
?dly    lda RTCLOK3
?dly2   cmp RTCLOK3
        beq ?dly2
        dex
        bne ?dly
        lda #$FF
        sta $02FC               ; clear again after delay
        ; Wait for any input
?wait_key
        lda RTCLOK3
?wk_vs  cmp RTCLOK3
        beq ?wk_vs
        ; Check keyboard
        lda $02FC
        cmp #$FF
        beq ?chk_joy
        jmp ?got_input
?chk_joy
        ; Check joystick
        lda PORTA
        eor #$FF
        and #$0F
        bne ?got_input
        ; Check fire
        lda TRIG0
        beq ?got_input
        jmp ?wait_key
?got_input
        lda #$FF
        sta $02FC

        ; Play switch sound
        ldx #SFX_SWTCHN
        jsr snd_play

        ; Init menu
        lda #0
        sta menu_sel
        sta menu_prev
        ; Backup title area before drawing menu (one buffer is enough,
        ; both have same title graphic)
        jsr backup_menu_area
        ; Clear + draw menu on both buffers
        lda #0
        sta draw_mode
        jsr redraw_both

        ; --- Menu loop ---
?menu_loop
        jsr update_menu
        ; Redraw cursor if changed
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
        ; ESC = close menu, restore title graphic on both buffers
        lda $02FC
        cmp #$1C
        bne ?no_esc
        lda #$FF
        sta $02FC
        ldx #SFX_SWTCHX
        jsr snd_play
        jsr restore_menu_area
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        jsr restore_menu_area
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        jmp ?wait_release
?no_esc
        ; RETURN = confirm
        cmp #$0C
        bne ?chk_fire
        lda #$FF
        sta $02FC
        jmp ?handle_sel
?chk_fire
        ; FIRE button = confirm
        lda TRIG0
        beq ?fire_pressed
        jmp ?menu_loop
?fire_pressed
        ; Wait for release
?fr_rel lda TRIG0
        beq ?fr_rel
        jmp ?handle_sel
?handle_sel
        lda #$FF
        sta $02FC
        ldx #SFX_PISTOL
        jsr snd_play
        lda menu_sel
        cmp #0
        bne ?not_ng
        rts                     ; NEW GAME = return to main
?not_ng cmp #1
        bne ?not_set
        jsr menu_settings
        jmp ?redraw_menu
?not_set
        ; CREDITS - TODO
        jmp ?menu_loop

?redraw_menu
        jsr redraw_both
        jmp ?menu_loop
.endp

; ============================================
; PAUSE MENU (called from game loop, returns when resume)
; ============================================
.proc menu_pause
        ; Stop current sound, reset lock, play menu open sound
        lda #0
        sta snd_active
        sta snd_lock
        sta AUDC4
        ldx #SFX_SWTCHN
        jsr snd_play
        ; Init
        lda #0
        sta menu_sel
        sta menu_prev
        ; Backup game graphics under menu area
        jsr backup_menu_area
        ; Draw on both buffers
        lda #0
        sta draw_mode
        jsr redraw_both

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
        ; ESC = resume
        lda $02FC
        cmp #$1C
        beq ?resume
        ; RETURN
        cmp #$0C
        bne ?loop
        lda #$FF
        sta $02FC
        ldx #SFX_PISTOL
        jsr snd_play
        lda menu_sel
        cmp #0
        beq ?new_game           ; NEW GAME
        cmp #1
        bne ?not_set
        jsr menu_settings
        jmp ?redraw
?not_set
        jmp ?loop
?new_game
        lda #$FF
        sta $02FC
        lda #1                  ; A=1 = new game requested
        rts
?resume lda #$FF
        sta $02FC
        ldx #SFX_SWTCHX
        jsr snd_play
        ; Restore game graphics on both buffers
        jsr restore_menu_area
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        jsr restore_menu_area
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        lda #0                  ; A=0 = resume
        rts                     ; return to game loop
?redraw jsr redraw_both
        jmp ?loop
.endp

; ============================================
; SETTINGS (from title - preserves background)
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
; TOGGLE SOUND ON/OFF
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
