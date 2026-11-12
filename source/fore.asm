;==============================================
; DOOM2D - Foreground layer (D2DF PANEL_FORE: drawn over the monsters,
; items and the player, e.g. walls hiding a secret room)
; fore.asm
;
; The level's foreground cells come as rectangles cut to FB_BK x FB_BK
; buckets (tools/d2df2map.py fore_rects, loaded to FORE_RAM). Each frame
; the rects of the buckets in view are copied from the ring bg canvas (it
; holds those cells' pixels) over the sprites: transparent blits appended
; to the sprite list, split at the canvas seams like copy_bg_window.
;==============================================

FB_BK     = 16                      ; bucket size in cells
FB_NB     = [MAP_W+FB_BK-1]/FB_BK   ; buckets across / down (7)
FB_MAX    = 160                     ; rects per level
fb_first  = FORE_RAM                ; [FB_NB*FB_NB+1] first rect of a bucket
fr_c0     = FORE_RAM+FB_NB*FB_NB+1  ; [FB_MAX] rect left column
fr_r0     = fr_c0+FB_MAX            ; top row
fr_w      = fr_r0+FB_MAX            ; width in cells (<= FB_BK)
fr_h      = fr_w+FB_MAX             ; height in cells
        ert fr_h+FB_MAX>$C000 .or FORE_RAM<sr_y1+SR_MAX
        ert FORE_SECTORS*128<FB_NB*FB_NB+1+4*FB_MAX

; ============================================
; FORE_RESTORE - put src step hi (+4), width-1 hi (+13) and the table page
; (+17) back to 0 in last frame's liquid and foreground slots (sprites
; write none of them). Called before the frame's first sprite; the
; blitter finished that list (copy_bg_window waited for it).
; ============================================
.proc fore_restore
        ldx fo_n
        beq ?r
        lda ls_bank             ; the set being built (frame.asm)
        sta VBXE_BANK_SEL
        lda fo_p
        sta ztptr
        lda fo_p+1
        sta ztptr+1
?lp     lda #0
        ldy #4
        sta (ztptr),y
        ldy #13
        sta (ztptr),y
        ldy #17
        sta (ztptr),y
        lda ztptr
        clc
        adc #21
        sta ztptr
        bcc ?n
        inc ztptr+1
?n      dex
        bne ?lp
        stx fo_n                ; X = 0
?r      rts
.endp

; ============================================
; RENDER_FORE - the foreground rects in view, after all world sprites
; ============================================
.proc render_fore
        jsr fu_union            ; (liq_filter set fo_p: the slots from there)            ; pass 1: the cells all world sprites cover
        bcc ?go
        rts                     ; no world sprite: no foreground part to draw
?go
        lda cam_tcol            ; cells in view: [cam_tcol, +NSX) x [cam_trow, +NSY)
        clc
        adc #NSX
        sta fo_c1
        lda cam_trow
        adc #NSY                ; C=0: cam_tcol+NSX < 256
        sta fo_r1
        lda cam_tcol            ; buckets in view
        jsr ?bk
        sta fo_bx0
        lda fo_c1
        sec
        sbc #1                  ; last column in view
        jsr ?bk
        sta fo_bx1
        lda cam_trow
        jsr ?bk
        sta fo_by
        lda fo_r1
        sec
        sbc #1
        jsr ?bk
        sta fo_by1
?row    ldy fo_by
        lda fb_row,y
        clc
        adc fo_bx0
        sta fo_b                ; bucket = by*FB_NB + bx
        ldy fo_bx0
?col    sty fo_bx
        ldy fo_b
        lda fb_first+1,y        ; its rects: [first, next first)
        sta ?e+1
        lda fb_first,y
?rect
?e      cmp #0                  ; (patched: the next bucket's first)
        bcs ?nb
        sta fo_i
        tax
        jsr fore_rect
        ldx fo_i
        inx
        txa
        bne ?rect               ; (always: X <= FB_MAX)
?nb     inc fo_b
        ldy fo_bx
        iny
        cpy fo_bx1
        bcc ?col
        beq ?col
        inc fo_by
        lda fo_by1
        cmp fo_by
        bcs ?row
        rts
?bk     lsr                     ; cell -> bucket, at most FB_NB-1
        lsr
        lsr
        lsr
        cmp #FB_NB
        bcc ?bok
        lda #FB_NB-1
?bok    rts
fb_row  :FB_NB dta #*FB_NB
        ert FB_BK<>16
.endp

; FU_UNION - the cells [fu_c0, fu_c1) x [fu_r0, fu_r1) around this frame's
; world sprite rects (sr_*): fore_rect's pass-1 reject. C=1: no sprite;
; sr_n = $FF (too many): a rect over the whole view.
.proc fu_union
        ldx sr_n
        bne ?g
        sec
        rts
?g      cpx #$FF
        beq ?all
        lda #$FF                ; the running mins / maxes are the operands
        sta ?x0+1               ; of the cmp # below: mins $FF, maxes 0
        sta ?y0+1
        lda #0
        sta ?x1+1
        sta ?y1+1
?lp     dex
        bmi ?done
        lda sr_x0,x
?x0     cmp #0                  ; (patched: min x0)
        bcs ?a
        sta ?x0+1
?a      lda sr_x1,x
?x1     cmp #0                  ; (patched: max x1)
        bcc ?b
        sta ?x1+1
?b      lda sr_y0,x
?y0     cmp #0                  ; (patched: min y0)
        bcs ?c
        sta ?y0+1
?c      lda sr_y1,x
?y1     cmp #0                  ; (patched: max y1)
        bcc ?lp
        sta ?y1+1
        bcs ?lp                 ; (always)
?done   lda ?x0+1
        sta fu_c0
        lda ?x1+1
        sta fu_c1
        lda ?y0+1
        sta fu_r0
        lda ?y1+1
        sta fu_r1
        bne ?cv                 ; (always: a rect's y + h >= 1)
?all    lda #0                  ; too many sprites: the whole view
        sta fu_c0
        sta fu_r0
        lda #$FF
        sta fu_c1
        sta fu_r1
?cv     ldy #3                  ; cells: (2 * x/2 + cam_x) / 8, (y + cam_y) / 8,
?cl     ldx #0                  ; the ends + 7 (rounded up)
        lda fu_c0,y
        cpy #2
        bcs ?v
        asl
        bcc ?x
        inx
?x      adc cam_x               ; C=0
        sta ?t
        txa
        adc cam_x_hi
        bcc ?s                  ; (always: < 64K)
?v      clc
        adc cam_y
        sta ?t
        txa
        adc cam_y_hi
?s      tax
        lda ?t
        clc
        adc ?bias,y
        sta ?t
        txa
        adc #0                  ; A = hi <= 3 (x <= 510 + 480 + 7, y <= 862)
        ldx ?t
        lsr                     ; hi*32 by lsr + 3x ror, then | lo/8
        ror
        ror
        ror
        ora div8_lut,x
        sta fu_c0,y
        dey
        bpl ?cl
        clc
        rts
?bias   dta 0, 7, 0, 7
?t      dta 0
.endp

; FORE_RECT - rect X clipped to the cells in view, split at the column seam
; of the canvas (fore_rows splits at the row seam)
.proc fore_rect
        lda fr_c0,x             ; outside every sprite's cells (fu_union):
        cmp fu_c1               ; nothing of it is drawn (sr_hit would say so)
        bcs ?rr
        adc fr_w,x              ; C=0
        cmp fu_c0
        bcc ?rr
        beq ?rr
        lda fr_r0,x
        cmp fu_r1
        bcs ?rr
        adc fr_h,x              ; C=0
        cmp fu_r0
        bcc ?rr
        bne ?in
?rr     rts
?in     ldy fr_c0,x             ; c0 = max(left, cam_tcol)
        tya
        cmp cam_tcol
        bcs ?c0
        lda cam_tcol
?c0     sta fo_c0
        tya                     ; columns = min(left + w, fo_c1) - c0
        clc
        adc fr_w,x
        cmp fo_c1
        bcc ?c1
        lda fo_c1
?c1     sec
        sbc fo_c0
        beq ?rr
        bcc ?rr
        sta fo_cw
        ldy fr_r0,x             ; the same for the rows
        tya
        cmp cam_trow
        bcs ?r0
        lda cam_trow
?r0     sta fo_r0
        tya
        clc
        adc fr_h,x
        cmp fo_r1
        bcc ?r1
        lda fo_r1
?r1     sec
        sbc fo_r0
        beq ?rr
        bcc ?rr
        sta fo_rh
        ldy fo_c0               ; columns before the canvas seam
        lda #NSX
        sec
        sbc slotx_lut,y
        cmp fo_cw
        bcs ?one
        sta fo_n1               ; split: n1 columns, then the rest
        lda fo_cw
        sec
        sbc fo_n1
        sta fo_n2
        lda fo_n1
        sta fo_cw
        jsr fore_rows
        lda fo_c0
        clc
        adc fo_n1
        sta fo_c0
        lda fo_n2
        sta fo_cw
?one
.endp
        ert *<>fore_rows        ; falls through (6502-idioms: no jmp)

; FORE_ROWS - fo_r0 + fo_rh split at the row seam of the canvas (kept)
.proc fore_rows
        ldy fo_r0               ; rows before the canvas seam
        lda #NSY
        sec
        sbc sloty_lut,y
        cmp fo_rh
        jcs fore_part
        sta fo_m1
        lda fo_r0
        pha
        lda fo_rh
        pha
        sec
        sbc fo_m1
        sta fo_m2
        lda fo_m1
        sta fo_rh
        jsr fore_part
        lda fo_r0
        clc
        adc fo_m1
        sta fo_r0
        lda fo_m2
        sta fo_rh
        jsr fore_part
        pla
        sta fo_rh
        pla
        sta fo_r0
        rts
.endp

; FORE_PART - cells fo_c0 + fo_cw x fo_r0 + fo_rh (no seam inside) clipped
; to the game window, appended to the sprite list. Only the first cell in
; view can stick out left / above (by cam_x%8 / cam_fy, < 8 px).
.proc fore_part
        lda fo_c0               ; x = c0*8 - cam_x (16-bit)
        lsr
        lsr
        lsr
        lsr
        lsr
        tay                     ; Y = c0*8 hi
        lda fo_c0
        asl
        asl
        asl
        sec
        sbc cam_x
        sta fo_x
        tya
        sbc cam_x_hi
        sta fo_x+1
        lda fo_cw               ; w = cw*8 (<= FB_BK cells: < 256)
        asl
        asl
        asl
        sta bs_w
        lda #0
        sta fo_cl
        lda fo_x+1
        bpl ?xr
        lda #0                  ; x < 0: cut -x columns
        sec
        sbc fo_x
        sta fo_cl
        lda bs_w
        sec
        sbc fo_cl
        sta bs_w
        lda #0
        sta fo_x
        sta fo_x+1
?xr     lda fo_x                ; right edge: room = 320 - x
        cmp #<SCR_W
        lda fo_x+1
        sbc #>SCR_W
        bcs ?skip               ; x >= 320
        lda #<SCR_W
        sec
        sbc fo_x
        tay
        lda #>SCR_W
        sbc fo_x+1
        bne ?y                  ; room >= 256 > w
        cpy bs_w
        bcs ?y
        sty bs_w
?y      lda fo_r0               ; y = r0*8 - cam_y (16-bit)
        lsr
        lsr
        lsr
        lsr
        lsr
        tay                     ; Y = r0*8 hi
        lda fo_r0
        asl
        asl
        asl
        sec
        sbc cam_y
        sta fo_y
        tya
        sbc cam_y_hi
        tax                     ; X = y hi
        lda fo_rh
        asl
        asl
        asl
        sta bs_h
        lda #0
        sta fo_ct
        txa
        beq ?yb
        bmi ?yneg
?skip   rts
?yneg   lda #0                  ; y < 0: cut -y rows
        sec
        sbc fo_y
        sta fo_ct
        lda bs_h
        sec
        sbc fo_ct
        sta bs_h
        lda #0
        sta fo_y
?yb     lda fo_y
        cmp #GAME_H
        bcs ?skip
        adc bs_h                ; C=0: bottom clip at GAME_H
        bcs ?bc
        cmp #GAME_H+1
        bcc ?src
?bc     lda #GAME_H
        sec
        sbc fo_y
        sta bs_h
?src    jsr sr_hit              ; pass 2 reject: no world sprite under it
        bcc ?skip               ; (the window copy shows it already)
        lda spl_ptr             ; the sprite list is full: skip
        cmp #<[SPRL_W+SPRL_MAX*21]
        lda spl_ptr+1
        sbc #>[SPRL_W+SPRL_MAX*21]
        bcs ?skip
        ldx fo_r0               ; canvas = $061000 + rowtop[slot r0]
        ldy sloty_lut,x         ;   + cut*BG_STRIDE + colx[slot c0] + cut
        ldx fo_ct
        lda bgbuf_rowtop_lo,y
        clc
        adc fyrow_lo,x
        sta fo_s
        lda bgbuf_rowtop_hi,y
        adc fyrow_hi,x
        sta fo_s+1
        lda #$06
        adc #0
        sta fo_s+2
        ldx fo_c0
        ldy slotx_lut,x
        lda bgcolx_lo,y         ; low 3 bits 0: the cut (< 8) ors in
        ora fo_cl
        clc
        adc fo_s
        sta fo_s
        lda bgcolx_hi,y
        adc fo_s+1
        bcc ?s1
        inc fo_s+2
        clc
?s1     adc #$10
        sta fo_s+1
        bcc ?bcb
        inc fo_s+2
?bcb    lda ls_bank             ; the set being built (frame.asm)
        sta VBXE_BANK_SEL
        ldy #0
        lda fo_s
        sta (spl_ptr),y         ; +0 src
        iny
        lda fo_s+1
        sta (spl_ptr),y
        iny
        lda fo_s+2
        sta (spl_ptr),y
        iny
        lda #<BG_STRIDE
        sta (spl_ptr),y         ; +3 src step = canvas stride
        iny
        lda #>BG_STRIDE
        sta (spl_ptr),y         ; +4 (fore_restore puts 0 back)
        iny
        lda #1
        sta (spl_ptr),y         ; +5 src step x
        ldx fo_y                ; dst = y_addr[y] + x + buffer
        lda y_addr_lo,x
        clc
        adc fo_x
        iny
        sta (spl_ptr),y         ; +6
        iny
        lda y_addr_hi,x
        adc fo_x+1
        sta (spl_ptr),y         ; +7
        lda bs_w
        sec
        sbc #1
        ldy #12
        sta (spl_ptr),y         ; +12 width-1
        lda bs_h
        sbc #1                  ; C=1: bs_w >= 1
        ldy #14
        sta (spl_ptr),y         ; +14 height-1
        lda #BLT_TRANS+$08
        ldy #20
        sta (spl_ptr),y         ; +20 ctrl (spl_flush ends the list)
        lda spl_ptr
        clc
        adc #21
        sta spl_ptr
        bcc ?n
        inc spl_ptr+1
?n      inc fo_n
        rts
.endp
; (the fo_* / fu_* variables are in data.asm: this block ends at $BE00)
