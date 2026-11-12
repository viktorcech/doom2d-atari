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
; CLOSE MENU — restore screen on both buffers (title menu only: in pause
; mode the next composite_frame wipes the menu area anyway)
; ============================================
.proc menu_close
        jsr both_bufs           ; the rest runs once per buffer
        jmp restore_menu_area
.endp

; ============================================
; MENU_VSYNC - wait for the next frame (RTCLOK3 change); keeps X and Y
; ============================================
.proc menu_vsync
        lda RTCLOK3
?w      cmp RTCLOK3
        beq ?w
        rts
.endp

; MENU_ESC_SND - ESC taken: clear the key, play the back sound
.proc menu_esc_snd
        lda #$FF
        sta CH
        ldx #SFX_SWTCHX
        jmp snd_play
.endp

; ============================================
; TITLE SCREEN (called from main)
; Returns when user picks NEW GAME or LOAD GAME
; menu_result: 0=new game, 2=load
; ============================================
.proc menu_title_screen
.if AUTOPLAY=1
        lda #0
        sta menu_result         ; debug: skip straight to NEW GAME
        rts
.endif
?wait_release
        lda PORTA
        eor #$FF
        and #$0F
        bne ?wait_release
        lda TRIG0
        beq ?wait_release
        lda #$FF
        sta CH
        ldx #4                  ; debounce ~4 frames (was 10 - felt sluggish)
?dly    jsr menu_vsync          ; keeps X
        dex
        bne ?dly
        lda #$FF
        sta CH
?wait_key
        jsr menu_vsync          ; VBLANK wait
        lda CH
        cmp #$FF
        bne ?got_input
        lda PORTA
        eor #$FF
        and #$0F
        bne ?got_input
        lda TRIG0
        bne ?wait_key           ; no fire: keep waiting
?got_input
        lda #$FF
        sta CH
        lda #0
        sta menu_mode           ; title mode (no SAVE)
        jsr menu_open           ; A = menu_result: N=1 only for $FF (ESC)
        bpl ?done
        ; ESC on title: close menu, go back to wait
        jsr menu_close
        jmp ?wait_release
?done   rts
.endp

; ============================================
; PAUSE MENU (called from game loop), falls into menu_open
; Returns: A = menu_result: $FF resume (N=1), 0 new game (Z=1), 2 load game
; (resume needs no menu_close: pause mode restores nothing)
; ============================================
.proc menu_pause
        jsr wait_blit           ; the last frame's list may still run (frame.asm)
        jsr sio_quiet           ; silence, the sample IRQ off
        lda #0
        sta snd_lock
        lda #1
        sta menu_mode           ; pause mode (has SAVE)
.endp
        ert *<>menu_open

; ============================================
; OPEN MENU — open sound, init state, backup screen, draw, then the menu
; loop (falls into menu_common_loop): exit A = menu_result, N/Z from it.
; Pause mode skips the backup: the game loop recomposites rows 0-191 every
; frame, so the menu area self-heals on resume. Title mode must back up
; (the title image is static, nothing redraws it).
; Skipping the backup also keeps VRAM $070000 (overlaps the bg canvas rows)
; untouched -> no forced full canvas rebuild on resume.
; ============================================
.proc menu_open
        ldx #SFX_SWTCHN
        jsr snd_play
        lda #0
        sta menu_sel
        sta menu_prev
        sta draw_mode
        lda menu_mode
        bne ?no_bkp             ; pause: no backup needed
        jsr backup_menu_area
?no_bkp jsr redraw_both
        ert *<>menu_common_loop
.endp

; ============================================
; COMMON MENU LOOP — shared input/selection handling
; Sets menu_result: 0=new game, 2=load, $FF=ESC; exits with A = menu_result
; and N/Z from it ($FF: N=1; 0: Z=1; 2: N=Z=0) - menu_open's callers use it.
; ============================================
.proc menu_common_loop
        ; Debounce: wait for fire button release before accepting input
?debounce
        lda TRIG0
        beq ?debounce
?loop   jsr update_menu
        lda menu_sel
        cmp menu_prev
        beq ?no_redraw
        ldx #SFX_PSTOP
        jsr snd_play
        jsr move_cursor         ; cursor-only redraw (4 tiny blits, not ~74)
        lda menu_sel
        sta menu_prev
?no_redraw
        jsr menu_vsync          ; VBLANK wait

        ; ESC
        lda CH
        cmp #$1C
        bne ?no_esc
        jsr menu_esc_snd
        lda #$FF
        sta menu_result
        rts                     ; A=$FF: N=1
?no_esc
        ; RETURN (?handle_sel clears CH)
        cmp #$0C
        beq ?handle_sel
        lda TRIG0
        jne ?loop               ; fire not pressed, loop
        ; Fire pressed — wait for release first (debounce)
?fr_rel lda TRIG0
        beq ?fr_rel

?handle_sel
        lda #$FF
        sta CH
        ldx #SFX_PISTOL
        jsr snd_play

        lda menu_sel
        ; 0 = NEW GAME
        bne ?not_ng
        sta menu_result
        rts                     ; A=0: Z=1, N=0
?not_ng
        ; title has no SAVE: map its sel 1,2,3 to the pause numbering 1,3,4
        ldx menu_mode
        bne ?pause
        cmp #2
        adc #0                  ; +C: C = (sel >= 2)
?pause  tax                     ; 1 SETTINGS, 2 SAVE, 3 LOAD, 4 CREDITS
        dex
        beq ?set
        dex
        beq ?save
        dex
        bne ?cred
        jsr load_game_menu      ; A=0 ok / 1 fail, Z from A (both exits)
        bne ?redraw
        lda #2
        sta menu_result
        rts                     ; A=2: N=Z=0
?set    jsr menu_settings
        beq ?redraw             ; exits lda #0 / sta draw_mode: Z=1
?cred   jsr show_credits
        beq ?redraw             ; same exit: Z=1
?save   jsr save_game_menu
?redraw jsr redraw_both
        jmp ?loop
.endp

; ============================================
; SHOW CREDITS (wait for ESC or fire)
; ============================================
.proc show_credits
        lda #2
        sta draw_mode
        jsr redraw_both
        ; Wait for fire/key release first
?rel    lda TRIG0
        beq ?rel
?loop   jsr menu_vsync
        ; ESC only
        lda CH
        cmp #$1C
        bne ?loop
        beq menu_settings.exit  ; Z=1: same exit as SETTINGS
.endp

; ============================================
; SETTINGS
; ============================================
.proc menu_settings
        lda #1
        sta draw_mode
        jsr redraw_both
?loop   jsr menu_vsync
        lda CH
        cmp #$0C
        bne ?chk_esc
        lda #$FF
        sta CH
        lda snd_enabled         ; toggle sound
        eor #1
        sta snd_enabled
        bne ?on
        jsr sio_quiet           ; off: silence, the sample IRQ off
?on     jsr redraw_both
?chk_esc
        lda CH
        cmp #$1C
        bne ?loop
exit    jsr menu_esc_snd
        lda #0
        sta draw_mode
        rts                     ; Z=1 (menu_common_loop relies on it)
.endp
