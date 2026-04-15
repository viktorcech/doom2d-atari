;==============================================
; DOOM2D - Menu rendering & input
; menu_draw.asm
;==============================================

; ============================================
; BACKUP MENU AREA (184x80 from screen to VRAM $070000)
; ============================================
.proc backup_menu_area
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #80
        sta zdx
        lda #0
        sta zdxh
        lda #72
        sta zdy
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+0
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+2
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+3
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+4
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5   ; step mode 1 = use explicit step
        ; Dest = VRAM $070000
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+6
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda #$07
        sta MEMW+[VRAM_BCB&$FFF]+8
        lda #184
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11
        lda #183
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #87
        sta MEMW+[VRAM_BCB&$FFF]+14
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+20
        jsr run_blit
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        rts
.endp

; ============================================
; RESTORE MENU AREA (VRAM $070000 back to screen)
; ============================================
.proc restore_menu_area
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        ; Source = VRAM $070000, step=184
        lda #$00
        sta MEMW+[VRAM_BCB&$FFF]+0
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda #$07
        sta MEMW+[VRAM_BCB&$FFF]+2
        lda #184
        sta MEMW+[VRAM_BCB&$FFF]+3
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+4
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5   ; src step mode
        ; Dest = screen (80,72), step=320
        lda #80
        sta zdx
        lda #0
        sta zdxh
        lda #72
        sta zdy
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9   ; dst step = 320
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11  ; dst step mode
        ; Size 184x64, mode 0
        lda #183
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #87
        sta MEMW+[VRAM_BCB&$FFF]+14
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode 0 (copy)
        jsr run_blit
        jsr wait_blit
        ; Restore normal BCB
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        rts
.endp

; ============================================
; REDRAW BOTH BUFFERS (clear + draw on both screens)
; Set draw_mode before calling: 0=menu, 1=settings
; ============================================
.proc redraw_both
        jsr clear_menu_area
        lda draw_mode
        beq ?menu
        cmp #2
        beq ?cred
        jsr draw_settings
        jmp ?buf2
?cred   jsr draw_credits
        jmp ?buf2
?menu   jsr draw_menu
?buf2   jsr wait_blit
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        jsr clear_menu_area
        lda draw_mode
        beq ?menu2
        cmp #2
        beq ?cred2
        jsr draw_settings
        jmp ?done
?cred2  jsr draw_credits
        jmp ?done
?menu2  jsr draw_menu
?done   jsr wait_blit
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        rts
.endp

; ============================================
; DRAW TEXT STRING
; ============================================
.proc draw_text
        ldy #0
?lp     lda (txt_ptr),y
        beq ?done
        sty dt_y
        cmp #' '
        beq ?space
        cmp #'0'
        bcc ?space
        cmp #':'
        bcc ?digit
        sec
        sbc #'A'-12
        jmp ?draw
?digit  sec
        sbc #'0'
        jmp ?draw
?space  jmp ?adv                ; space = skip (transparent)
?draw   jsr blit_hud_char
?adv    lda zdx
        clc
        adc #8
        sta zdx
        lda zdxh
        adc #0
        sta zdxh
        ldy dt_y
        iny
        jmp ?lp
?done   rts
dt_y    dta 0
.endp

; ============================================
; DRAW MENU (cursor + 3 items)
; ============================================
.proc draw_menu
        ; Cursor
        lda menu_sel
        asl
        asl
        asl
        asl
        clc
        adc #MENU_Y
        sta zdy
        lda #MENU_X-16
        sta zdx
        lda #0
        sta zdxh
        lda #11
        jsr blit_hud_char
        ; Item 0: NEW GAME
        lda #<txt_newgame
        sta txt_ptr
        lda #>txt_newgame
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y
        sta zdy
        jsr draw_text
        ; Item 1: SETTINGS
        lda #<txt_settings
        sta txt_ptr
        lda #>txt_settings
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y+MENU_SPACE
        sta zdy
        jsr draw_text
        ; Item 2: SAVE (pause only) or LOAD (title)
        lda menu_mode
        beq ?title_skip_save
        ; Pause: draw SAVE at slot 2
        lda #<txt_save
        sta txt_ptr
        lda #>txt_save
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y+MENU_SPACE*2
        sta zdy
        jsr draw_text
        ; Pause: LOAD at slot 3
        lda #<txt_load
        sta txt_ptr
        lda #>txt_load
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y+MENU_SPACE*3
        sta zdy
        jsr draw_text
        jmp ?draw_credits
?title_skip_save
        ; Title: LOAD at slot 2 (no SAVE)
        lda #<txt_load
        sta txt_ptr
        lda #>txt_load
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y+MENU_SPACE*2
        sta zdy
        jsr draw_text
?draw_credits
        ; Item: CREDITS
        lda #<txt_credits
        sta txt_ptr
        lda #>txt_credits
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda menu_mode
        bne ?cr_pause
        lda #MENU_Y+MENU_SPACE*3   ; title: slot 3
        jmp ?cr_draw
?cr_pause
        lda #MENU_Y+MENU_SPACE*4   ; pause: slot 4
?cr_draw
        sta zdy
        jsr draw_text
        rts
.endp

; ============================================
; DRAW SETTINGS
; ============================================
.proc draw_settings
        lda #<txt_snd_lbl
        sta txt_ptr
        lda #>txt_snd_lbl
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y
        sta zdy
        jsr draw_text
        lda snd_enabled
        bne ?on
        lda #<txt_off
        sta txt_ptr
        lda #>txt_off
        jmp ?dr
?on     lda #<txt_on
        sta txt_ptr
        lda #>txt_on
?dr     sta txt_ptr+1
        lda #MENU_X+56
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y
        sta zdy
        jsr draw_text
        ; Row 2: empty (clear old SETTINGS text)
        lda #<txt_empty
        sta txt_ptr
        lda #>txt_empty
        sta txt_ptr+1
        lda #MENU_X
        sta zdx
        lda #0
        sta zdxh
        lda #MENU_Y+MENU_SPACE
        sta zdy
        jsr draw_text
        rts
.endp

; ============================================
; DRAW CREDITS
; ============================================
.proc draw_credits
        lda #<txt_cr1
        sta txt_ptr
        lda #>txt_cr1
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #74
        sta zdy
        jsr draw_text

        lda #<txt_cr2
        sta txt_ptr
        lda #>txt_cr2
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #84
        sta zdy
        jsr draw_text

        lda #<txt_cr3
        sta txt_ptr
        lda #>txt_cr3
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #94
        sta zdy
        jsr draw_text

        lda #<txt_cr4
        sta txt_ptr
        lda #>txt_cr4
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #108
        sta zdy
        jsr draw_text

        lda #<txt_cr5
        sta txt_ptr
        lda #>txt_cr5
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #118
        sta zdy
        jsr draw_text

        lda #<txt_cr6
        sta txt_ptr
        lda #>txt_cr6
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #132
        sta zdy
        jsr draw_text

        lda #<txt_cr7
        sta txt_ptr
        lda #>txt_cr7
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #142
        sta zdy
        jsr draw_text

        lda #<txt_cr8
        sta txt_ptr
        lda #>txt_cr8
        sta txt_ptr+1
        lda #88
        sta zdx
        lda #0
        sta zdxh
        lda #152
        sta zdy
        jsr draw_text
        rts
.endp

; ============================================
; UPDATE MENU (joystick + keyboard)
; ============================================
.proc update_menu
        lda PORTA
        eor #$FF
        sta um_joy
        and #J_UP
        beq ?no_jup
        lda um_prev
        and #J_UP
        bne ?no_jup
        lda menu_sel
        beq ?no_jup
        dec menu_sel
?no_jup lda um_joy
        and #J_DOWN
        beq ?no_jdn
        lda um_prev
        and #J_DOWN
        bne ?no_jdn
        lda menu_mode
        bne ?max5
        lda menu_sel
        cmp #MENU_ITEMS-2       ; title: 4 items (0-3)
        bcs ?no_jdn
        inc menu_sel
        jmp ?no_jdn
?max5   lda menu_sel
        cmp #MENU_ITEMS-1       ; pause: 5 items (0-4)
        bcs ?no_jdn
        inc menu_sel
?no_jdn lda um_joy
        sta um_prev
        lda $02FC
        cmp #$FF
        beq ?done
        cmp #$06
        beq ?kup
        cmp #$0E
        beq ?kup
        cmp #$86
        beq ?kup
        cmp #$8E
        beq ?kup
        cmp #$07
        beq ?kdn
        cmp #$0F
        beq ?kdn
        cmp #$87
        beq ?kdn
        cmp #$8F
        beq ?kdn
        jmp ?done
?kup    lda #$FF
        sta $02FC
        lda menu_sel
        beq ?done
        dec menu_sel
        jmp ?done
?kdn    lda #$FF
        sta $02FC
        lda menu_mode
        bne ?kmax5
        lda menu_sel
        cmp #MENU_ITEMS-2
        bcs ?done
        inc menu_sel
        jmp ?done
?kmax5  lda menu_sel
        cmp #MENU_ITEMS-1
        bcs ?done
        inc menu_sel
?done   rts
um_joy  dta 0
um_prev dta 0
.endp

; Clear menu area with black (VBXE constant fill: AND=0, XOR=0)
.proc clear_menu_area
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+0
        sta MEMW+[VRAM_BCB&$FFF]+1
        sta MEMW+[VRAM_BCB&$FFF]+2
        sta MEMW+[VRAM_BCB&$FFF]+3
        sta MEMW+[VRAM_BCB&$FFF]+4
        sta MEMW+[VRAM_BCB&$FFF]+5
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND = 0
        sta MEMW+[VRAM_BCB&$FFF]+16  ; XOR = 0
        sta MEMW+[VRAM_BCB&$FFF]+17
        sta MEMW+[VRAM_BCB&$FFF]+18
        sta MEMW+[VRAM_BCB&$FFF]+19
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode 0
        lda #80
        sta zdx
        lda #0
        sta zdxh
        lda #72
        sta zdy
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        lda #183
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #87
        sta MEMW+[VRAM_BCB&$FFF]+14
        jsr run_blit
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+16
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        rts
.endp

; ============================================
; TEXT DATA
; ============================================
txt_newgame dta c'NEW GAME',0
txt_settings dta c'SETTINGS',0
txt_save dta c'SAVE    ',0
txt_load dta c'LOAD    ',0
txt_credits dta c'CREDITS ',0
txt_snd_lbl dta c'SOUND   ',0
txt_on  dta c'ON      ',0
txt_off dta c'OFF     ',0
txt_empty dta c'        ',0
txt_cr1 dta c'DOOM 2D  ATARI 8BIT',0
txt_cr2 dta c'ORIGINAL DOOM 2D PC',0
txt_cr3 dta c'PRIKOL SOFTWARE 1996',0
txt_cr4 dta c'DOOM BY ID SOFTWARE',0
txt_cr5 dta c'D2D FOREVER COMMUNITY',0
txt_cr6 dta c'ATARI PORT  W1K',0
txt_cr7 dta c'TOOLS MADS ALTIRRA',0
txt_cr8 dta c'ATARI 800XL VBXE',0
