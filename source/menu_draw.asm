;==============================================
; DOOM2D - Menu rendering & input
; menu_draw.asm
;==============================================

; ============================================
; BOTH_BUFS - `jsr both_bufs` as a routine's first instruction runs the rest
; of that routine (up to its rts) on this buffer, flips zbuf_hi, runs it
; again and flips back, then returns to the routine's caller. X/Y pass in
; untouched; exit A = zbuf_hi with N/Z of its eor (as the inline flip had).
; Not re-entrant (the body address lives in ?lo/?hi operands).
; ============================================
.proc both_bufs
        pla                     ; body-1 (the jsr's return address)
        sta ?lo+1
        pla
        sta ?hi+1
        jsr ?go
        jsr ?flip
        jsr ?go
?flip   lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi
        rts
?go
?hi     lda #0                  ; push body-1, rts enters the body; its rts
        pha                     ; comes back here
?lo     lda #0
        pha
        rts
.endp

; ============================================
; BACKUP MENU AREA (184x88 from screen to VRAM $070000)
; ============================================
.proc backup_menu_area
        ldx #0                  ; screen = src (BCB+0)
        ldy #6                  ; $070000 = dst (BCB+6)
        ert *<>menu_area_copy
.endp

; MENU_AREA_COPY - 184x88 copy between the screen (80,72) and VRAM $070000.
; X = BCB offset of the screen address group (0 src / 6 dst), Y = offset of
; the $070000 group (the other one). Ends with BCB step 9-10 = SCR_W and
; mode 20 = BLT_TRANS (what the other blits expect).
.proc menu_area_copy
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0                  ; $070000, step 184, step mode 1
        sta MEMW+[VRAM_BCB&$FFF]+0,y
        sta MEMW+[VRAM_BCB&$FFF]+1,y
        sta MEMW+[VRAM_BCB&$FFF]+4,y
        lda #$07
        sta MEMW+[VRAM_BCB&$FFF]+2,y
        lda #184
        sta MEMW+[VRAM_BCB&$FFF]+3,y
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5,y
        sta MEMW+[VRAM_BCB&$FFF]+5,x ; screen: step SCR_W, step mode 1
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+3,x
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+4,x
        jsr menu_area_blit
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        rts
.endp

; MENU_AREA_BLIT - size 184x88, mode 0, screen address of (80,72) into
; BCB+X..X+2, run the blit and wait (falls into menu_blit_x)
.proc menu_area_blit
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode 0
        sta zdxh
        lda #183
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #87
        sta MEMW+[VRAM_BCB&$FFF]+14
        lda #80
        sta zdx
        lda #72
        sta zdy
        ert *<>menu_blit_x
.endp

; MENU_BLIT_X - screen address of zdx/zdy into BCB+X..X+2, run the blit,
; wait, select the BCB bank again. Keeps X.
.proc menu_blit_x
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+0,x
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+1,x
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+2,x
        jsr run_blit
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        rts
.endp

; ============================================
; RESTORE MENU AREA (VRAM $070000 back to screen)
; ============================================
.proc restore_menu_area
        ldx #6                  ; screen = dst (BCB+6)
        ldy #0                  ; $070000 = src (BCB+0)
        jsr menu_area_copy
        ; Menu backup VRAM ($070000+) overlaps bg buffer's last rows -> force rebuild
        lda #$FF
        sta last_cam_tcol
        rts
.endp

; Clear menu area with black (VBXE constant fill: AND=0, XOR=0)
.proc clear_menu_area
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0
        ldx #5
?z      sta MEMW+[VRAM_BCB&$FFF]+0,x  ; src 0-5 = 0
        sta MEMW+[VRAM_BCB&$FFF]+15,x ; AND, XOR, coll, pattern, mode 15-20 = 0
        dex
        bpl ?z
        ldx #6
        jsr menu_area_blit
        ; XOR 16 is still 0 (written above; nothing writes the BCB since)
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        bne menu_clear_char.and_ff      ; (always: BLT_TRANS <> 0)
        ert BLT_TRANS=0
.endp

; ============================================
; MENU_CLEAR_CHAR - black-fill one 8x8 char cell at zdx/zdy
; (cursor erase; restores BCB AND back to $FF for the char blits)
; ============================================
.proc menu_clear_char
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0
        ldx #5
?z      sta MEMW+[VRAM_BCB&$FFF]+0,x
        dex
        bpl ?z
        sta MEMW+[VRAM_BCB&$FFF]+13
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND = 0 -> fill black
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode 0
        lda #HUD_CHAR_W-1
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #HUD_CHAR_H-1
        sta MEMW+[VRAM_BCB&$FFF]+14
        ldx #6
        jsr menu_blit_x
and_ff  lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15  ; restore AND (copy_bg_window relies on it)
        rts
.endp

; ============================================
; REDRAW BOTH BUFFERS (clear + draw on both screens)
; Set draw_mode before calling: 0=menu, 1=settings, 2=credits
; ============================================
.proc redraw_both
        jsr both_bufs           ; the rest runs once per buffer
        jsr clear_menu_area
        jsr ?draw
        jmp wait_blit
?draw   lda draw_mode
        jeq draw_menu
        cmp #2
        jne draw_settings
        ert *<>draw_credits
.endp

; DRAW CREDITS (falls into draw_list)
.proc draw_credits
        ldx #dl_cred-dl_tab
        ert *<>draw_list
.endp

; ============================================
; DRAW_LIST - draw a list of strings from dl_tab. X = list offset; entries
; are (y, x, a(text)), y = 0 ends the list.
; ============================================
.proc draw_list
?lp     lda dl_tab,x
        beq ?done
        sta zdy
        lda dl_tab+1,x
        sta zdx
        lda dl_tab+2,x
        sta txt_ptr
        lda dl_tab+3,x
        sta txt_ptr+1
        lda #0
        sta zdxh
        jsr draw_text           ; keeps X
        inx
        inx
        inx
        inx
        bne ?lp                 ; dl_tab < 256 bytes: X never wraps to 0
?done   rts
.endp

; ============================================
; DRAW MENU (cursor + items)
; ============================================
.proc draw_menu
        jsr move_cursor.cur     ; cursor at menu_sel
        ldx #dl_title-dl_tab    ; title: LOAD at slot 2 (no SAVE)
        lda menu_mode
        beq draw_list
        ldx #dl_pause-dl_tab    ; pause: SAVE at slot 2, LOAD at slot 3
        bne draw_list           ; (always: Z=0, ert below)
.endp

; ============================================
; DRAW SETTINGS
; ============================================
.proc draw_settings
        ldx #dl_off-dl_tab
        lda snd_enabled
        beq draw_list
        ldx #dl_on-dl_tab
        bne draw_list           ; (always: Z=0, ert below)
.endp
        ert dl_pause-dl_tab=0 .or dl_on-dl_tab=0

; ============================================
; MOVE_CURSOR - cursor-only menu redraw on selection change.
; Erases the cursor cell at menu_prev row, draws it at menu_sel row,
; on both buffers. Replaces a full clear+text redraw (~74 blits -> 4).
; ============================================
.proc move_cursor
        jsr both_bufs           ; the rest runs once per buffer
        lda menu_prev
        jsr cpos
        jsr menu_clear_char     ; erase old cursor
cur     lda menu_sel            ; draw_menu enters here
        jsr cpos
        lda #11                 ; cursor char
        jmp menu_char           ; draw new cursor (tail call)
cpos    ldy #MENU_X-16          ; row -> zdy = MENU_Y + row*16, zdx = Y
cpos_y  asl                     ; (slot_move_cursor.cpos enters here)
        asl
        asl
        asl                     ; row <= 4: zeros shifted out, C=0
        adc #MENU_Y
        sta zdy
        sty zdx
        lda #0
        sta zdxh
        rts
.endp

; ============================================
; DRAW TEXT STRING - walks txt_ptr (left on the terminator). Keeps X.
; ============================================
.proc draw_text
?lp     ldy #0
        lda (txt_ptr),y
        beq ?done
        cmp #'0'
        bcc ?adv                ; space (and below '0') = skip (transparent)
        cmp #':'
        bcc ?digit              ; C=0
        sbc #['A'-12]-['0'-1]   ; letters, C=1: A >= ':' -> no borrow, C stays 1
?digit  sbc #'0'-1              ; digit (C=0): A-'0'; letter (C=1): A-('A'-12)
        jsr menu_char
?adv    lda zdx
        clc
        adc #8
        sta zdx
        bcc ?nc
        inc zdxh
?nc     inc txt_ptr
        bne ?lp
        inc txt_ptr+1
        bne ?lp                 ; strings never wrap past $FFFF
?done   rts
.endp

; ============================================
; UPDATE MENU (joystick + keyboard)
; ============================================
.proc update_menu
        lda PORTA
        eor #$FF
        tay                     ; Y = stick, 1 = pressed
        lda um_prev
        eor #$FF
        sty um_prev             ; um_prev = this frame's stick (sty: no flags)
        and um_prev             ; A = newly pressed (pressed now, not before)
        tay
        and #J_UP
        beq ?no_jup
        jsr ?up                 ; keeps Y
?no_jup tya
        and #J_DOWN
        beq ?no_jdn
        jsr ?dn
?no_jdn lda CH
        and #$77                ; drop bits 7, 3: $06/$0E/$86/$8E -> $06 (up),
        clc                     ; $07/$0F/$87/$8F -> $07 (down), $FF -> $77
        adc #$FF-$07
        adc #$07-$06+1          ; C=1 inside [$06,$07]: A = 0 up, 1 down
        bcc ?r
        ldy #$FF
        sty CH
        lsr                     ; C = down
        bcc ?up
?dn     lda #MENU_ITEMS-3       ; last item - 1: 2 title / 3 pause (menu_mode 0/1)
        clc
        adc menu_mode
        cmp menu_sel
        bcc ?r                  ; menu_sel already last
        inc menu_sel
?r      rts
?up     lda menu_sel
        beq ?r
        dec menu_sel
        rts
um_prev dta 0
.endp

; ============================================
; DRAW LISTS (draw_list): y, x, a(text); y = 0 ends a list
; ============================================
dl_tab
dl_title dta MENU_Y, MENU_X, a(txt_newgame)
        dta MENU_Y+MENU_SPACE, MENU_X, a(txt_settings)
        dta MENU_Y+MENU_SPACE*2, MENU_X, a(txt_load)
        dta MENU_Y+MENU_SPACE*3, MENU_X, a(txt_credits)
        dta 0
dl_pause dta MENU_Y, MENU_X, a(txt_newgame)
        dta MENU_Y+MENU_SPACE, MENU_X, a(txt_settings)
        dta MENU_Y+MENU_SPACE*2, MENU_X, a(txt_save)
        dta MENU_Y+MENU_SPACE*3, MENU_X, a(txt_load)
        dta MENU_Y+MENU_SPACE*4, MENU_X, a(txt_credits)
        dta 0
dl_on   dta MENU_Y, MENU_X, a(txt_snd_lbl)
        dta MENU_Y, MENU_X+56, a(txt_on)
        dta 0
dl_off  dta MENU_Y, MENU_X, a(txt_snd_lbl)
        dta MENU_Y, MENU_X+56, a(txt_off)
        dta 0
dl_cred dta 74, 88, a(txt_cr1)
        dta 84, 88, a(txt_cr2)
        dta 94, 88, a(txt_cr3)
        dta 108, 88, a(txt_cr4)
        dta 118, 88, a(txt_cr5)
        dta 132, 88, a(txt_cr6)
        dta 142, 88, a(txt_cr7)
        dta 152, 88, a(txt_cr8)
        dta 0
dl_save_t dta SLOT_MENU_Y, SLOT_MENU_X, a(txt_save)   ; slot_draw titles
        dta 0
dl_load_t dta SLOT_MENU_Y, SLOT_MENU_X, a(txt_load)
        dta 0
        ert *-dl_tab>256

; ============================================
; TEXT DATA (a space draws nothing: no trailing spaces; clear_menu_area
; clears the area before every list)
; ============================================
txt_newgame dta c'NEW GAME',0
txt_settings dta c'SETTINGS',0
txt_save dta c'SAVE',0
txt_load dta c'LOAD',0
txt_credits dta c'CREDITS',0
txt_snd_lbl dta c'SOUND',0
txt_on  dta c'ON',0
txt_off dta c'OFF',0
txt_cr1 dta c'DOOM 2D  ATARI 8BIT',0
txt_cr2 dta c'ORIGINAL DOOM 2D PC',0
txt_cr3 dta c'PRIKOL SOFTWARE 1996',0
txt_cr4 dta c'DOOM BY ID SOFTWARE',0
txt_cr5 dta c'D2D FOREVER COMMUNITY',0
txt_cr6 dta c'ATARI PORT  W1K',0
txt_cr7 dta c'TOOLS MADS ALTIRRA',0
txt_cr8 dta c'ATARI 800XL VBXE',0
