;==============================================
; DOOM2D - VBXE init, palette, XDL, blitter
; vbxe.asm
;==============================================

; ============================================
; XDL
; ============================================
.proc setup_xdl
        lda #BANK_EN+BANK_XDL
        sta VBXE_BANK_SEL
        ldx #xdl_len-1
?lp     lda xdl_data,x
        sta MEMW+[VRAM_XDL&$FFF],x
        dex
        bpl ?lp
        ; Pre-fill constant BCB fields (never change during gameplay)
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9      ; dst step lo = 320
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10     ; dst step hi
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11     ; dst step mode
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15     ; AND mask
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+16     ; XOR lo
        sta MEMW+[VRAM_BCB&$FFF]+17     ; XOR hi
        sta MEMW+[VRAM_BCB&$FFF]+18     ; collision
        sta MEMW+[VRAM_BCB&$FFF]+19     ; pattern
        rts
.endp

xdl_data
        dta $24,$00,19
        dta $62,$88,199
        dta $00,$00,$00
        dta $40,$01
        dta $11,$FF
xdl_len = * - xdl_data

; ============================================
; INIT CLEAR (both screen buffers: banks 0-15 + $20-$2F)
; Currently unused but kept for potential level transitions
; ============================================
.proc init_clear
        ; Clear screen 0 (banks 0-15)
        lda #0
        sta ic_bank
?bank1  lda ic_bank
        ora #BANK_EN
        sta VBXE_BANK_SEL
        jsr ?clear_page
        inc ic_bank
        lda ic_bank
        cmp #16
        bne ?bank1
        ; Clear screen 1 (banks $20-$2F)
        lda #$20
        sta ic_bank
?bank2  lda ic_bank
        ora #BANK_EN
        sta VBXE_BANK_SEL
        jsr ?clear_page
        inc ic_bank
        lda ic_bank
        cmp #$30
        bne ?bank2
        rts

?clear_page
        lda #0
        ldy #0
?p      sta MEMW,y
        sta MEMW+$100,y
        sta MEMW+$200,y
        sta MEMW+$300,y
        sta MEMW+$400,y
        sta MEMW+$500,y
        sta MEMW+$600,y
        sta MEMW+$700,y
        sta MEMW+$800,y
        sta MEMW+$900,y
        sta MEMW+$A00,y
        sta MEMW+$B00,y
        sta MEMW+$C00,y
        sta MEMW+$D00,y
        sta MEMW+$E00,y
        sta MEMW+$F00,y
        iny
        bne ?p
        rts
ic_bank dta 0
.endp

; upload_tiles, upload_hud_font, setup_palette - all moved to INI segments in main.asm

; ============================================
; CLEAR SCREEN (blit sky to game area 320x192, HUD area stays black)
; ============================================
.proc clear_screen
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        ; src = background sky at $034000
        lda #$00
        sta MEMW+[VRAM_BCB&$FFF]+0
        lda #$40
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda #$03
        sta MEMW+[VRAM_BCB&$FFF]+2
        ; src step = 320 (advance each row)
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+3
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+4
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5
        ; dst = back buffer ($000000 or $020000)
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+6
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zbuf_hi             ; $00 or $02
        sta MEMW+[VRAM_BCB&$FFF]+8
        ; dst step = 320
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11
        ; size 320x192 (game area only, HUD at Y=192 stays black)
        lda #<[SCR_W-1]
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #>[SCR_W-1]
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #HUD_Y-1            ; 192-1 = 191 rows
        sta MEMW+[VRAM_BCB&$FFF]+14
        ; AND=$FF, copy mode
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+16
        sta MEMW+[VRAM_BCB&$FFF]+17
        sta MEMW+[VRAM_BCB&$FFF]+18
        sta MEMW+[VRAM_BCB&$FFF]+19
        sta MEMW+[VRAM_BCB&$FFF]+20
        jsr run_blit
        rts
.endp

; ============================================
; BLITTER
; ============================================
.proc run_blit
        jsr wait_blit
        lda #$00
        sta VBXE_BL_ADR0
        lda #$F1
        sta VBXE_BL_ADR1
        lda #$07
        sta VBXE_BL_ADR2
        lda #1
        sta VBXE_BLITTER
        rts                     ; return immediately, CPU works while blitter runs
.endp

.proc wait_blit
?w      lda VBXE_BLITTER
        bne ?w
        rts
.endp

; ============================================
; CALC DST: zva = zdy * 320 + zdx + buffer_base
; buffer 0 = $000000, buffer 1 = $020000
; ============================================
.proc calc_dst
        ; LUT version: zva = y_addr[zdy] + zdx + buffer_base
        ldy zdy
        lda y_addr_lo,y
        clc
        adc zdx
        sta zva
        lda y_addr_hi,y
        adc zdxh
        sta zva+1
        lda #0
        adc zbuf_hi
        sta zva+2
        rts
.endp

; Buffer high byte: $00 for screen 0, $02 for screen 1
zbuf_hi dta 0

; PAL/NTSC flag: 0=NTSC, non-zero=PAL
is_pal  dta 0

; ============================================
; BLIT TILE 16x16
; src = $01:(r_tile):$00
; ============================================
.proc blit_tile
        ; Check if one-way tile or switch (needs bg + transparent blit)
        lda r_tile
        tax
        lda tile_oneway,x
        bne ?draw_bg
        lda r_tile
        cmp #TILE_SWITCH_OFF
        beq ?draw_bg
        cmp #TILE_SWITCH_ON
        beq ?draw_bg
        jmp ?normal
?draw_bg
        ; First: draw sky background section at this tile position
        lda r_tile
        pha                 ; save original tile index
        jsr blit_bg         ; copies sky from VRAM $034000+ at r_col,r_row
        pla
        sta r_tile          ; restore original tile
        ; Then: draw platform with BLT_TRANS (below, mode set at end)
?normal
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+0
        lda r_tile
        cmp #16
        bcs ?newtile
        ; Old tiles 0-15: VRAM $01:tile:$00
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda #$01
        sta MEMW+[VRAM_BCB&$FFF]+2
        jmp ?tileok
?newtile
        ; Switch tiles 28-29: VRAM $06:(tile-28):$00
        cmp #TILE_SWITCH_OFF
        bcc ?oldnew
        sec
        sbc #TILE_SWITCH_OFF ; 28→0, 29→1
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda #$06
        sta MEMW+[VRAM_BCB&$FFF]+2
        jmp ?tileok
?oldnew
        ; New tiles 16-27: VRAM $03:(tile+$10):$00
        clc
        adc #$10            ; tile 16 → $20, tile 17 → $21...
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda #$03
        sta MEMW+[VRAM_BCB&$FFF]+2
?tileok
        lda #TW
        sta MEMW+[VRAM_BCB&$FFF]+3
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+4
        sta zdxh
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5
        lda r_col
        asl
        asl
        asl
        asl
        rol zdxh            ; capture carry for cols 16-19
        sta zdx
        lda r_row
        asl
        asl
        asl
        asl
        sta zdy
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        ; dst step [9-11], AND [15], XOR [16-19] pre-filled
        lda #TW-1
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #TH-1
        sta MEMW+[VRAM_BCB&$FFF]+14
        ; Blitter mode: transparent for one-way/switch tiles, opaque for rest
        lda r_tile
        tax
        lda tile_oneway,x
        bne ?trans
        lda r_tile
        cmp #TILE_SWITCH_OFF
        beq ?trans
        cmp #TILE_SWITCH_ON
        beq ?trans
        lda #0              ; BLT_COPY (opaque)
        beq ?setm
?trans  lda #BLT_TRANS      ; transparent (skip index 0)
?setm   sta MEMW+[VRAM_BCB&$FFF]+20
        jsr run_blit
?skip   rts
.endp

; ============================================
; BLIT SPRITE (transparent mode 1)
; src = $01:(spr_off_hi+$10):spr_off_lo
; ============================================
.proc blit_sprite
        tax
        ; --- Right-edge clipping ---
        lda zdxh
        cmp #2
        bcc ?xlt2
        jmp ?skip               ; X >= 512: entirely off screen
?xlt2   cmp #1
        beq ?clip_r             ; zdxh=1: may need right clip
        ; zdxh=0: max right edge = 255+16=271 < 320, no clip
        lda spr_w,x
        sta bs_w
        jmp ?chk_bot
?clip_r ; zdxh=1: available width = 320-256-zdx = 64-zdx
        lda #64
        sec
        sbc zdx
        beq ?cr_off
        bcc ?cr_off             ; zdx >= 64: off screen
        cmp spr_w,x
        bcs ?clip_rok           ; available >= sprite width
        sta bs_w                ; clipped width
        jmp ?chk_bot
?cr_off jmp ?skip
?clip_rok
        lda spr_w,x
        sta bs_w

?chk_bot
        ; --- Bottom-edge clipping ---
        lda spr_h,x
        sta bs_h
        lda zdy
        clc
        adc bs_h
        cmp #SCR_H+1            ; zdy + h > 200?
        bcc ?no_bclip
        lda #SCR_H              ; clip: new height = 200 - zdy
        sec
        sbc zdy
        bne ?bclip_ok
        jmp ?skip
?bclip_ok
        sta bs_h
?no_bclip
        ; --- Blit ---
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda spr_off_lo,x
        sta MEMW+[VRAM_BCB&$FFF]+0
        lda spr_off_hi,x
        clc
        adc #$10
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda spr_off_bank,x
        adc #0
        sta MEMW+[VRAM_BCB&$FFF]+2
        ; src step = original sprite width (not clipped!)
        lda spr_w,x
        sta MEMW+[VRAM_BCB&$FFF]+3
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+4
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        ; dst step [9-11] pre-filled by setup_xdl
        ; Blit size = clipped width x clipped height
        lda bs_w
        sec
        sbc #1
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda bs_h
        sec
        sbc #1
        sta MEMW+[VRAM_BCB&$FFF]+14
        ; AND [15], XOR [16-19] pre-filled by setup_xdl
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        jsr run_blit
?skip   rts
.endp

bs_w    dta 0
bs_h    dta 0

; ============================================
; BLIT BG 16x16 (restore sky background for empty tiles)
; src = sky VRAM at $034000 + r_row*5120 + r_col*16
; ============================================
.proc blit_bg
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        ; Source: background VRAM at bg_row[r_row] + r_col*16
        lda r_col
        asl
        asl
        asl
        asl                         ; r_col*16, C=1 if r_col>=16
        sta MEMW+[VRAM_BCB&$FFF]+0  ; src lo
        ldy r_row
        lda bg_row_mid,y
        adc #0                      ; add carry from r_col*16 overflow
        sta MEMW+[VRAM_BCB&$FFF]+1  ; src mid
        lda bg_row_hi,y
        sta MEMW+[VRAM_BCB&$FFF]+2  ; src hi
        ; src step = 320 (same pitch as screen)
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+3
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+4
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5
        ; Destination: screen at (r_col*16, r_row*16)
        lda #0
        sta zdxh
        lda r_col
        asl
        asl
        asl
        asl
        rol zdxh            ; capture carry for cols 16-19
        sta zdx
        lda r_row
        asl
        asl
        asl
        asl
        sta zdy
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        ; dst step [9-11], AND [15], XOR [16-19] pre-filled
        lda #TW-1
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #TH-1
        sta MEMW+[VRAM_BCB&$FFF]+14
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+20     ; mode=0 (opaque copy)
        jsr run_blit
        rts
.endp

; Background row address lookup (12 entries)
; Address = $034000 + row * 5120 ($1400)
bg_row_mid
        dta $40,$54,$68,$7C,$90,$A4,$B8,$CC,$E0,$F4,$08,$1C
bg_row_hi
        dta $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$04,$04
