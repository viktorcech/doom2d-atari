;==============================================
; DOOM2D - VBXE init, palette, XDL, blitter
; vbxe.asm
;==============================================

; ============================================
; SETUP XDL + BLITTER DEFAULTS
; Writes the eXtended Display List to VRAM and pre-fills
; constant BCB (Blitter Control Block) fields used by all blits.
;
; VBXE BCB register map (21 bytes at VRAM_BCB):
;   0-2:   src address (lo, mid, hi) — 24-bit VRAM source
;   3-5:   src step (lo, hi, mode)   — bytes per row in source
;   6-8:   dst address (lo, mid, hi) — 24-bit VRAM destination
;   9-11:  dst step (lo, hi, mode)   — bytes per row in dest
;   12-13: width-1 (lo, hi)          — blit width in pixels
;   14:    height-1                   — blit height in pixels
;   15:    AND mask ($FF=copy, $00=fill constant)
;   16-19: XOR bytes (usually 0)
;   20:    mode (0=opaque, BLT_TRANS=skip color 0)
; ============================================
.proc setup_xdl
        ; Copy XDL template into VRAM
        lda #BANK_EN+BANK_XDL
        sta VBXE_BANK_SEL
        ldx #xdl_len-1
?lp     lda xdl_data,x
        sta MEMW+[VRAM_XDL&$FFF],x
        dex
        bpl ?lp
        ; Pre-fill BCB fields that stay constant during gameplay:
        ; dst step = 320 (screen width), AND=$FF, XOR=0
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9      ; dst step lo = 320
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10     ; dst step hi
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11     ; dst step mode (1=use explicit step)
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15     ; AND mask ($FF = copy source)
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+16     ; XOR lo
        sta MEMW+[VRAM_BCB&$FFF]+17     ; XOR hi
        sta MEMW+[VRAM_BCB&$FFF]+18     ; collision
        sta MEMW+[VRAM_BCB&$FFF]+19     ; pattern
        rts
.endp

; XDL template: 2 entries
; Entry 1: 20 empty scanlines (border), no overlay
; Entry 2: 200 scanlines with 320px 8bpp overlay from VRAM $010040
xdl_data
        dta $24,$00,19          ; flags, ov_palette, repeat=20 lines
        dta $62,$88,199         ; flags (OV+RPTL+END+OVADR), palette, repeat=200 lines
        dta $00,$00,$00         ; overlay addr (lo, mid, hi) = $000000
        dta $40,$01             ; overlay step = 320
        dta $11,$FF             ; ov_width, ov_priority
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
; CLEAR_FULL_BLACK - Fill entire 320x200 buffer with black (0)
; Uses current zbuf_hi for buffer select.
; ============================================
.proc clear_full_black
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        ; src = 0 (fill with AND=0)
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
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode 0 (fill)
        ; dst = buffer start
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+6
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zbuf_hi
        sta MEMW+[VRAM_BCB&$FFF]+8
        ; dst step = 320
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11
        ; size = 320x200
        lda #<[SCR_W-1]
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #>[SCR_W-1]
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #SCR_H-1
        sta MEMW+[VRAM_BCB&$FFF]+14
        jsr run_blit
        jsr wait_blit
        ; Restore normal BCB state
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND = $FF
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+16
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        rts
.endp

; ============================================
; RUN_BLIT - Start VBXE blitter (no wait — caller must ensure idle)
; BCB must be fully configured before calling.
; Returns immediately — CPU continues while blitter runs.
; ============================================
.proc run_blit
        lda #$00                ; BCB address = $07F100
        sta VBXE_BL_ADR0       ;   lo
        lda #$F1
        sta VBXE_BL_ADR1       ;   mid
        lda #$07
        sta VBXE_BL_ADR2       ;   hi
        lda #1
        sta VBXE_BLITTER       ; start blit (async)
        rts
.endp

; WAIT_BLIT - Wait for blitter + do deferred sound VRAM reads
; 2026-04-08: Calls snd_poll while waiting — does pending VRAM reads
; during blitter dead time instead of wasting cycles in tight loop.
.proc wait_blit
        lda VBXE_BLITTER
        beq ?done
?w      jsr snd_poll
        lda VBXE_BLITTER
        bne ?w
?done   rts
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
        ; Check bit 7 = BG variant (same texture, non-solid, draw with sky bg)
        lda #0
        sta bt_is_bg
        lda r_tile
        bpl ?no_bg_flag
        and #$7F            ; strip bit 7
        sta r_tile
        lda #1
        sta bt_is_bg
        jmp ?draw_bg
?no_bg_flag
        ; Check if one-way tile, half-height or switch (needs bg + transparent blit)
        tax
        lda tile_oneway,x
        bne ?draw_bg
        lda tile_halfh,x
        bne ?draw_bg
        lda r_tile
        cmp #TILE_SWITCH_OFF
        beq ?draw_bg
        cmp #TILE_SWITCH_ON
        beq ?draw_bg
        cmp #TILE_EXIT_SW_OFF
        beq ?draw_bg
        cmp #TILE_EXIT_SW_ON
        beq ?draw_bg
        cmp #15             ; barrel solid tile — draw with BG
        beq ?draw_bg
        jmp ?normal_sub
?draw_bg
        ; First: draw background at this tile position
        ; Check bg override table (for switches/platforms on wall BG)
        lda r_tile
        pha                 ; save original tile index
        ldx #0
?ov_lp  cpx tile_bg_cnt
        bcs ?ov_sky         ; no override, draw sky
        lda tile_bg_col,x
        cmp r_col
        bne ?ov_nx
        lda tile_bg_row,x
        cmp r_row
        bne ?ov_nx
        ; Found override — draw BG tile opaque, then switch transparent on top
        lda tile_bg_tid,x
        sta r_tile
        lda #0
        sta bt_is_bg        ; draw BG tile as normal opaque
        jsr ?normal_sub     ; draw the BG tile (opaque)
        jmp ?ov_done
?ov_nx  inx
        jmp ?ov_lp
?ov_sky jsr blit_bg         ; copies sky from VRAM $034000+ at r_col,r_row
?ov_done
        pla
        sta r_tile          ; restore original tile
        lda #1
        sta bt_is_bg        ; force transparent for the overlay tile
        ; Then: draw overlay tile with BLT_TRANS
        jsr ?normal_sub
?skip   rts

?normal_sub
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+0
        lda r_tile
        cmp #TILE_SOLIDFLR
        bne ?not_sflr
        lda #12             ; solid floor uses metalflr texture
?not_sflr
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
        ; Blitter mode: transparent for BG/one-way/switch tiles, opaque for rest
        lda bt_is_bg
        bne ?trans
        lda r_tile
        tax
        lda tile_oneway,x
        bne ?trans
        lda tile_halfh,x
        bne ?trans
        lda r_tile
        cmp #TILE_SWITCH_OFF
        beq ?trans
        cmp #TILE_SWITCH_ON
        beq ?trans
        cmp #TILE_EXIT_SW_OFF
        beq ?trans
        cmp #TILE_EXIT_SW_ON
        beq ?trans
        lda #0              ; BLT_COPY (opaque)
        beq ?setm
?trans  lda #BLT_TRANS      ; transparent (skip index 0)
?setm   sta MEMW+[VRAM_BCB&$FFF]+20
        jsr run_blit
        rts
bt_is_bg dta 0
.endp

; Tile BG override table (max 8 entries)
MAX_TILE_BG = 8
tile_bg_cnt dta 0
tile_bg_col .ds MAX_TILE_BG
tile_bg_row .ds MAX_TILE_BG
tile_bg_tid .ds MAX_TILE_BG

; ============================================
; BLIT SPRITE (transparent — color 0 = see-through)
; Input: A = sprite index, zdx/zdxh = X pos, zdy = Y pos
; Sprites stored in VRAM at: spr_off_bank:(spr_off_hi+$10):spr_off_lo
; Handles right-edge and bottom-edge clipping automatically.
; ============================================
.proc blit_sprite
        tax
        ; --- Right-edge clipping ---
        ; Screen is 320px wide. zdxh:zdx is 16-bit X position.
        ; zdxh>=2: entirely off screen (X>=512)
        ; zdxh=1:  partially visible, clip to 320-256=64 available px
        ; zdxh=0:  fully visible (max right edge = 255+16 = 271 < 320)
        lda zdxh
        cmp #2
        bcc ?xlt2
        jmp ?skip
?xlt2   cmp #1
        beq ?clip_r
        lda spr_w,x
        sta bs_w
        jmp ?chk_bot
?clip_r lda #64                 ; available pixels = 320 - 256 - zdx
        sec
        sbc zdx
        beq ?cr_off
        bcc ?cr_off             ; zdx >= 64: sprite fully off right edge
        cmp spr_w,x
        bcs ?clip_rok           ; available >= sprite width: no clip needed
        sta bs_w                ; clipped width = available pixels
        jmp ?chk_bot
?cr_off jmp ?skip
?clip_rok
        lda spr_w,x
        sta bs_w

?chk_bot
        ; --- Bottom-edge clipping ---
        ; If sprite extends below Y=200, reduce height
        lda spr_h,x
        sta bs_h
        lda zdy
        clc
        adc bs_h
        cmp #SCR_H+1
        bcc ?no_bclip
        lda #SCR_H              ; clipped height = 200 - zdy
        sec
        sbc zdy
        bne ?bclip_ok
        jmp ?skip
?bclip_ok
        sta bs_h
?no_bclip
        ; --- Wait for previous blit, then configure BCB ---
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        ; Source VRAM address from lookup tables
        ; Final addr = spr_off_bank:(spr_off_hi+$10):spr_off_lo
        ; The +$10 offset is because sprites start at VRAM $01_10_00
        lda spr_off_lo,x
        sta MEMW+[VRAM_BCB&$FFF]+0     ; src addr lo
        lda spr_off_hi,x
        clc
        adc #$10
        sta MEMW+[VRAM_BCB&$FFF]+1     ; src addr mid
        lda spr_off_bank,x
        adc #0                          ; propagate carry
        sta MEMW+[VRAM_BCB&$FFF]+2     ; src addr hi
        ; Source row step = full sprite width (not clipped, to skip hidden cols)
        lda spr_w,x
        sta MEMW+[VRAM_BCB&$FFF]+3     ; src step lo
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+4     ; src step hi
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5     ; src step mode
        ; Destination = screen position (calc_dst uses zdx/zdxh/zdy/zbuf_hi)
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6     ; dst addr lo
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7     ; dst addr mid
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8     ; dst addr hi
        ; dst step [9-11], AND [15], XOR [16-19] pre-filled by setup_xdl
        ; Blit size = (clipped width - 1) x (clipped height - 1)
        lda bs_w
        sec
        sbc #1
        sta MEMW+[VRAM_BCB&$FFF]+12    ; width-1 lo
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13    ; width-1 hi
        lda bs_h
        sec
        sbc #1
        sta MEMW+[VRAM_BCB&$FFF]+14    ; height-1
        lda #BLT_TRANS                  ; transparent: skip color 0
        sta MEMW+[VRAM_BCB&$FFF]+20    ; blit mode
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
        jsr wait_blit
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
