;==============================================
; DOOM2D - Liquids: water / acid as the original's FILTER (g_panel.pas:
; e_DrawFillQuad TBlending.Filter = what is under it times the colour)
; liquid.asm
;
; In the original's order (g_game.pas: after the walls, items, monsters
; and the player, before the foreground) every liquid rect in view is ONE
; MODE 7 BCB in the sprite list: the screen filtered in place through a
; 256-byte table (VBXE FX 1.27: dest = table[AUX:cmask:source],
; tools/sky2vbxe.py data/liquid_lut.bin), like Wolfette's minimap shade.
; The rect also goes to sr_*: the foreground over it is drawn again.
;==============================================

LQ_MAX     = 80                         ; tools/d2df2map.py LIQ_MAX
LQ_SECTORS = 4                          ; tools/map2bin.py LIQ_SECTORS
LIQ_RAM    = $A000                      ; the level's liquid rects (load_map_tiles)
lq_first   = LIQ_RAM                    ; [FB_NB*FB_NB+1] first rect of a bucket
lq_c0      = lq_first+FB_NB*FB_NB+1     ; rect left column
lq_r0      = lq_c0+LQ_MAX               ; top row
lq_w       = lq_r0+LQ_MAX               ; width in cells
lq_h       = lq_w+LQ_MAX                ; height in cells
lq_k       = lq_h+LQ_MAX                ; 0 water, 1 acid1, 2 acid2 = the table page
LIQ_CODE   = LIQ_RAM+LQ_SECTORS*128     ; the code below (main.asm)
        ert LQ_SECTORS*128<FB_NB*FB_NB+1+5*LQ_MAX
VRAM_LUT   = $030000                    ; MODE 7 tables: AUX 3, page (cmask) = kind
LQ_CTRL    = [[VRAM_LUT>>16]<<4]+$08+7  ; AUX, NEXT, MODE 7
        ert [VRAM_LUT&$FFFF]<>0

; zero page (free since the sky left ANTIC)
lq_x0      = $89                        ; 2b: the rect on the screen [x0, x1) x [y0, y1)
lq_x1      = $8B                        ; 2b
lq_y0      = $9E
lq_y1      = $9F
lq_i       = $B8                        ; rect index

; LQ_BK - cell -> bucket, at most FB_NB-1 (render_fore's)
.proc lq_bk
        lsr
        lsr
        lsr
        lsr
        cmp #FB_NB
        bcc ?r
        lda #FB_NB-1
?r      rts
.endp

; LIQ_FILTER - the liquid rects of the buckets in view, appended to the
; sprite list after the world sprites, before render_fore (main.asm).
; fore_restore puts their slots back (fo_p, fo_n: the foreground's too).
.proc liq_filter
        lda spl_ptr             ; the first slot fore_restore puts back
        sta fo_p
        lda spl_ptr+1
        sta fo_p+1
        lda lq_first+FB_NB*FB_NB
        jeq ?end                ; no liquid in the level
        lda ls_bank             ; the set being built (frame.asm)
        sta VBXE_BANK_SEL
        lda cam_x
        and #7
        sta lq_fx
        lda cam_tcol            ; lq_rect's cheap reject: the window's cells
        sta lq_rect.?c0+1       ; [cam_tcol, +NSX) x [cam_trow, +NSY)
        clc
        adc #NSX
        sta lq_rect.?c1+1
        lda cam_trow
        sta lq_rect.?r0+1
        clc
        adc #NSY
        sta lq_rect.?r1+1
        lda cam_trow            ; buckets in view
        jsr lq_bk
        sta ?by+1
        lda cam_trow
        clc
        adc #NSY-1
        jsr lq_bk
        sta ?by1+1
        lda cam_tcol
        jsr lq_bk
        sta ?bx0+1
        lda cam_tcol
        clc
        adc #NSX-1
        jsr lq_bk
        sec
        sbc ?bx0+1
        sta ?nr0+1              ; buckets in a row - 1
?row
?by     ldy #0                  ; (patched: the bucket row)
        lda render_fore.fb_row,y
        clc
?bx0    adc #0                  ; (patched: the first bucket column)
        sta ?b+1
?nr0    lda #0                  ; (patched)
        sta ?cnt+1
?bk
?b      ldy #0                  ; (patched: the bucket)
        lda lq_first,y
        sta lq_i
        lda lq_first+1,y
        sta ?e+1
?r      ldx lq_i
?e      cpx #0                  ; (patched: the next bucket's first)
        bcs ?nbk
        jsr lq_rect
        inc lq_i
        bne ?r                  ; (always: lq_i < LQ_MAX)
?nbk    inc ?b+1
        dec ?cnt+1
?cnt    lda #0                  ; (patched; N from the dec above)
        bpl ?bk
        lda ?by+1
?by1    cmp #0                  ; (patched: the last bucket row)
        inc ?by+1               ; (C kept)
        bcc ?row
?end    rts
.endp

; LQ_RECT - rect X clipped to the game window: its MODE 7 BCB (source =
; destination = the back buffer) and its sr_* rect
.proc lq_rect
        lda lq_c0,x             ; cheap reject in cells first (fable-skill-atari:
?c1     cmp #0                  ; pass 1): c0 >= the window's end column
        bcs ?out0               ; (patched by liq_filter), c0 + w <= its start,
        adc lq_w,x              ; the same for the rows (C=0 from the bcs)
?c0     cmp #0
        bcc ?out0
        beq ?out0
        lda lq_r0,x
?r1     cmp #0
        bcs ?out0
        adc lq_h,x
?r0     cmp #0
        bcc ?out0
        bne ?in
?out0   rts
        ; The rect is clipped in window cells first (fable-skill-atari: the
        ; cheap domain): a cell d of the window is the pixel d*8 - (cam & 7),
        ; d <= NSX: 8-bit shifts, the third asl's carry the high byte.
?in     sbc cam_trow            ; (A = r0 + h, C=1: the cmp) rows to its end >= 1
        cmp #NSY
        bcs ?y1m                ; past the window: GAME_H
        asl
        asl
        asl
        sec
        sbc cam_fy
        dta $2C                 ; bit abs: skips the lda
?y1m    lda #GAME_H
        sta lq_y1
        lda lq_r0,x             ; y0: at / above the window's top 0
        sec
        sbc cam_trow
        bcc ?y0z
        beq ?y0z
        asl                     ; (< NSY rows: <= 192, C=0)
        asl
        asl
        sec
        sbc cam_fy
        cmp #GAME_H
        bcs ?no
        dta $2C                 ; bit abs: skips the lda
?y0z    lda #0
        sta lq_y0
        lda lq_c0,x             ; x1: columns to its end >= 1
        clc
        adc lq_w,x
        sec
        sbc cam_tcol
        cmp #NSX
        bcc ?x1c
        lda #<SCR_W             ; past the window: 320
        ldy #>SCR_W
        bne ?x1s                ; (always: >SCR_W = 1)
?no     rts                     ; off the window
?x0z    lda #0                  ; at / left of the window's edge: 0
        tay
        beq ?x0s                ; (always)
?x1c    ldy #0
        asl
        asl
        asl
        bcc ?a
        iny
?a      sec
        sbc lq_fx
        bcs ?x1s
        dey
?x1s    sta lq_x1
        sty lq_x1+1
        lda lq_c0,x             ; x0
        sec
        sbc cam_tcol
        bcc ?x0z
        beq ?x0z
        ldy #0
        asl
        asl
        asl
        bcc ?b
        iny
?b      sec
        sbc lq_fx
        bcs ?c
        dey
?c      cpy #>SCR_W             ; x0 >= 320 (the last column, cam_x & 7 = 0):
        bcc ?x0s                ; nothing
        cmp #<SCR_W
        bcs ?no
?x0s    sta lq_x0
        sty lq_x0+1
        lda spl_ptr             ; the sprite list is full: skip
        cmp #<[SPRL_W+SPRL_MAX*21]
        lda spl_ptr+1
        sbc #>[SPRL_W+SPRL_MAX*21]
        bcs ?no
        ; --- the BCB: source = destination = back buffer + y0*320 + x0 ---
        ldx lq_y0
        lda y_addr_lo,x
        clc
        adc lq_x0
        ldy #0
        sta (spl_ptr),y         ; +0
        ldy #6
        sta (spl_ptr),y         ; +6
        lda y_addr_hi,x
        adc lq_x0+1
        ldy #1
        sta (spl_ptr),y         ; +1
        ldy #7
        sta (spl_ptr),y         ; +7
        lda zbuf_hi
        ldy #2
        sta (spl_ptr),y         ; +2
        lda #<SCR_W
        ldy #3
        sta (spl_ptr),y         ; +3 source step y = 320
        lda #>SCR_W
        iny
        sta (spl_ptr),y         ; +4 (fore_restore puts 0 back)
        iny                     ; +5 source step x = 1 (A = >320 = 1): the
        sta (spl_ptr),y         ; slot's last sprite may have left $FF (mirror)
        ert >SCR_W<>1
        lda lq_x1               ; width-1 = x1 - x0 - 1 (9 bits)
        clc
        sbc lq_x0
        ldy #12
        sta (spl_ptr),y         ; +12
        lda lq_x1+1
        sbc lq_x0+1
        iny
        sta (spl_ptr),y         ; +13 (fore_restore puts 0 back)
        lda lq_y1               ; height-1 = y1 - y0 - 1
        clc
        sbc lq_y0
        iny
        sta (spl_ptr),y         ; +14
        ldx lq_i
        lda lq_k,x
        ldy #17
        sta (spl_ptr),y         ; +17 the table page (fore_restore puts 0 back)
        lda #LQ_CTRL
        ldy #20
        sta (spl_ptr),y         ; +20
        lda spl_ptr             ; next slot
        clc
        adc #21
        sta spl_ptr
        bcc ?s
        inc spl_ptr+1
?s      inc fo_n
        ; --- sr_*: x0/2, ceil(x1/2), y0, y1 (sr_add's units) ---
        ldy sr_n
        cpy #SR_MAX
        bcs ?full               ; (also sr_n = $FF already)
        lda lq_x0+1
        lsr
        lda lq_x0
        ror
        sta sr_x0,y
        lda lq_x1+1
        lsr
        lda lq_x1
        ror
        adc #0                  ; C = the dropped bit: ceil (x1 <= 320)
        sta sr_x1,y
        lda lq_y0
        sta sr_y0,y
        lda lq_y1
        sta sr_y1,y
        iny
        sty sr_n
        rts
?full   lda #$FF
        sta sr_n
        rts
.endp
lq_fx   dta 0                   ; cam_x & 7 (liq_filter)
        ert NSX>63 .or NSY*8-8<>GAME_H
