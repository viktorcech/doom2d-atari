;==============================================
; DOOM2D - Scroll camera (smooth h+v) + RING bg canvas + parallax sky
; camera.asm  (ring-canvas rewrite 2026-08)
;
; The BG_STRIDE x BG_H bg canvas at $061000 is a TORUS on both axes: map
; column C lives in canvas slot C mod NSX, map row R in slot R mod NSY - the
; slot of a map tile never depends on the camera. Crossing a tile boundary
; therefore shifts NOTHING: only the newly exposed edge column/row strip is
; rendered into its ring slots.
;
; Every frame copy_bg_window copies the 320x192 window starting at ring
; offset (slot(cam_tcol)*TW + cam_x%TW, slot(cam_trow)*TH + cam_fy), split
; at the canvas seams into up to 4 sub-blits written as ONE chained
; BlitterList (BCB byte 20 bit 3 = continue) - a single kick, no CPU spins
; between the parts.
;
; The parallax sky is blitted first in the same list (sky.asm, 1.27 jump
; container), the window copy goes over it in MODE 1.
;
; Single-tile map changes (doors, switches, walls, barrels) no longer force
; a full window rebuild: they queue the tile (canvas_mark_tile) and the
; next frame patches just that cell (canvas_apply_patches).
;==============================================

NSX       = TILES_X+1               ; ring slots across (41)
NSY       = TILES_Y+1               ; ring slots down (25)
BG_STRIDE = NSX*TW                  ; bg canvas width (328)
BG_H      = NSY*TH                  ; bg canvas height (200)
        ert NSX*TW>512 || BG_H>256  ; one blit covers a whole strip
VCAM_DZ   = 40                      ; vertical camera dead-zone (+-px from center)

; 1 = blit_sprite applies (world - cam_x); 0 = screen-fixed (HUD).
spr_cam dta 0
cam_vsnap dta 1                     ; 1 = snap camera Y to target (level start)

cam_fy     dta 0                ; fine vertical pixel offset (cam_y & TH-1)

; Per-level horizontal camera limit (16-bit). Default = engine max; recomputed
; at level load by compute_max_cam from the map's rightmost non-empty column,
; so narrow (single-screen) maps don't scroll into empty space.
cam_xmax  dta <MAX_CAM_X, >MAX_CAM_X
cam_ymax  dta 0, 0              ; per-level vertical camera limit (16-bit)

; --- Ring slot LUTs (free RAM below the main segment, both in one page -> no
; page-cross penalty). Canvas slot of map column/row 0..MAP_W/MAP_H: one past
; the map, read before the edge test (cam_tcol+TILES_X, cam_trow+TILES_Y). ---
ring_lut_save = *
        org $1E00
slotx_lut
        :MAP_W+1 dta [# - [#/NSX]*NSX]
sloty_lut
        :MAP_H+1 dta [# - [#/NSY]*NSY]
        ert >*<>$1E
        org ring_lut_save

; ============================================
; COMPUTE_MAX_CAM - content extent of the map -> per-level camera limits:
; cam_xmax = max(0, cm_w*8 - SCR_W), cam_ymax = max(0, cm_h*8 - GAME_H),
; cm_w/cm_h = rightmost column / bottom row with a non-empty tile, +1 (0 =
; none). One pass over the rows, bank per row. Call once at level load
; (after the map is in VRAM, before update_camera).
; ============================================
.proc compute_max_cam
        lda #0
        sta cm_w
        sta cm_h
        ldx #MAP_H                  ; X = row + 1, counts down to 1
?row    lda map_row_bank-1,x
        sta VBXE_BANK_SEL
        lda map_row_lo-1,x
        sta ztptr
        lda map_row_hi-1,x
        sta ztptr+1
        ldy #MAP_W-1                ; scan the row from the right
?col    lda (ztptr),y
        bne ?hit
        dey
        bpl ?col
        bmi ?next                   ; empty row
?hit    lda cm_h
        bne ?h_ok                   ; a lower row came first (rows count down)
        stx cm_h
?h_ok   iny                         ; Y = column + 1
        cpy cm_w
        bcc ?next
        sty cm_w
?next   dex
        bne ?row
        ldx #2                      ; X = 2: cm_h -> cam_ymax, 0: cm_w -> cam_xmax
?lim    lda cm_w,x                  ; cm*8: hi = cm>>5 (parked), lo = cm<<3
        lsr
        lsr
        lsr
        lsr
        lsr
        sta ?hx+1
        lda cm_w,x
        asl
        asl
        asl
        sec
        sbc ?scr,x
        sta cam_xmax,x
?hx     lda #0                      ; (patched: hi; lda keeps C)
        sbc ?scr+1,x
        sta cam_xmax+1,x
        bcs ?ok
        lda #0
        sta cam_xmax,x
        sta cam_xmax+1,x
?ok     dex
        dex
        bpl ?lim
        rts
?scr    dta <SCR_W, >SCR_W, <GAME_H, >GAME_H
cm_w    dta 0, 0                    ; (+1 unused: cm_h = cm_w+2 for X = 0/2)
cm_h    dta 0
.endp
        ert cam_ymax<>cam_xmax+2

; bg canvas address = $061000 + rowtop[r_row] + colx[r_col] (computed
; inline in tl_add, written straight into the BCB). CANVAS coords.
; canvas column slot * TW (slot 0..NSX-1), lo/hi
bgcolx_lo
        :NSX dta <[#*TW]
bgcolx_hi
        :NSX dta >[#*TW]
bgbuf_rowtop_lo
        :NSY dta <[#*TH*BG_STRIDE]
bgbuf_rowtop_hi
        :NSY dta >[#*TH*BG_STRIDE]
; fine vertical pixel offset * BG_STRIDE, 0..TH-1
fyrow_lo
        :TH dta <[#*BG_STRIDE]
fyrow_hi
        :TH dta >[#*BG_STRIDE]

; ============================================
; COMPOSITE_FRAME - draw background into the backbuffer.
; Refresh the ring canvas only on tile-column/row change; every frame copy
; the toroidal 320x192 window (one chained BlitterList).
; ============================================
.proc composite_frame
        lda cam_tcol
        cmp last_cam_tcol
        bne ?chg
        lda cam_trow
        cmp last_cam_trow
        beq ?draw
?chg    jsr update_canvas           ; edge strip render or full rebuild
?draw   lda cq_cnt                  ; queued single-tile patches (doors,
        beq ?nq                     ; switches, barrels) and the animated
        jsr canvas_apply_patches    ; textures' cells: with THIS camera, the
?nq     jsr anim_tick               ; ring slots the window list shows
        jsr copy_bg_window          ; the window list, written before the START
        jmp sky_run                 ; ONE START: the sky, its jump container on
                                    ; to the window list (sky.asm, VBXE 1.27)
.endp
last_cam_tcol dta $FF               ; force rebuild on first frame / level load
last_cam_trow dta $FF

; ============================================
; REBUILD_BG - clear the ring canvas to 0 (transparent) + render the whole
; NSX x NSY window into its ring slots. Level load / camera teleport only -
; single-tile map changes go through canvas_mark_tile instead.
; ============================================
.proc rebuild_bg
        jsr pl_run                  ; this frame's queued pre lists first (it
        jsr clear_bgbuf             ; waits for frame N); transparent bg
        inc pl_sync                ; (frame.asm: each row's tiles at once)
        jsr render_tiles            ; whole window into ring slots
        dec pl_sync
        rts
.endp

; ============================================
; UPDATE_CANVAS - bring the ring canvas from (last_cam_tcol/trow) to
; (cam_tcol/trow). One-tile crossings render ONLY the newly exposed edge
; strip into its ring slots (nothing shifts). Multi-tile jumps and level
; load ($FF) fall back to the full rebuild.
; ============================================
.proc update_canvas
        lda cam_trow            ; (dx/dy are garbage on a $FF level load:
        sec                     ;  that path rebuilds without reading them)
        sbc last_cam_trow
        sta uc_dy
        lda cam_tcol
        sec
        sbc last_cam_tcol
        sta uc_dx
        ; commit new canvas position (X/Y: A keeps dx)
        ldx last_cam_tcol       ; $FF = level load -> full rebuild
        ldy cam_tcol
        sty last_cam_tcol
        ldy cam_trow
        sty last_cam_trow
        inx
        beq ?full
        ; |dx| > 1 or |dy| > 1 -> full rebuild: d in -1..1 <=> d+1 < 3
        clc
        adc #1
        cmp #3
        bcs ?full
        lda uc_dy
        adc #1                  ; C=0 (bcs not taken)
        cmp #3
        bcc ?dy_ok
?full   jmp rebuild_bg

?dy_ok  ; render the newly exposed edge column (ring: nothing shifts)
        lda uc_dx
        beq ?no_col
        eor #$FF                ; dx +1: $FE & TILES_X = TILES_X (new right edge),
        and #TILES_X            ; dx -1: 0 (new left edge); TILES_X even (ert)
        jsr render_bg_col
?no_col lda uc_dy
        beq ?no_row
        eor #$FF                ; dy +1: TILES_Y (new bottom edge), -1: 0 (top)
        and #TILES_Y
        jmp render_bg_row
?no_row rts
        ert [TILES_X&1]<>0 .or [TILES_Y&1]<>0
uc_dx   dta 0
uc_dy   dta 0
.endp

; ============================================
; RENDER_BG_COL - clear + render ONE window column into its ring slots.
; A = window column index 0..TILES_X (map col = cam_tcol + A, slot = col
; mod NSX). Past the map edge the strip stays transparent.
; ============================================
.proc render_bg_col
        clc
        adc cam_tcol
        sta rbc_mcol                 ; map column
        tay
        lda slotx_lut,y
        sta rbc_slot                 ; canvas slot column
        ; clear the TW x BG_H strip at x = slot*8 (slot <= 40: the 3rd asl
        ; shifts out bit 5 = the high byte, the first two shift out 0)
        asl
        asl
        asl
        sta cv_s
        lda #0
        rol @
        sta cv_s+1
        lda #TW-1
        sta cv_w1
        lda #BG_H-1
        sta cv_h1
        lda #0
        sta cv_w1+1
        jsr cv_rect                  ; (the clear list: before the tiles)
        lda rbc_mcol
        cmp #MAP_W
        bcs ?ret                     ; past right edge -> stays transparent
        lda rbc_slot
        sta r_col
        lda #0                       ; A = rbc_j at the loop head
?lp     sta rbc_j                    ; C=0: entry bcs not taken, loop bcc taken
        adc cam_trow                 ; map row
        cmp #MAP_H
        bcs ?ret                     ; past bottom -> rest stays transparent
        tax
        lda sloty_lut,x
        sta r_row                    ; ring slot row
        lda map_row_bank,x           ; re-set each tile (tl_add leaves BCB bank)
        sta VBXE_BANK_SEL
        lda map_row_lo,x
        sta ztptr
        lda map_row_hi,x
        sta ztptr+1
        ldy rbc_mcol
        lda (ztptr),y
        beq ?skip
        cmp #15
        beq ?skip                    ; invisible solid (barrel)
        tax                          ; X = the tile
        jsr tl_add
?skip   ldx rbc_j
        inx
        txa
        cmp #NSY                     ; TILES_Y+1 rows
        bcc ?lp
?ret    jmp tl_flush
rbc_mcol dta 0
rbc_slot dta 0
rbc_j    dta 0
.endp

; ============================================
; RENDER_BG_ROW - clear + render ONE window row into its ring slots.
; A = window row index 0..TILES_Y (map row = cam_trow + A, slot = row mod NSY).
; ============================================
.proc render_bg_row
        clc
        adc cam_trow
        sta rbr_mrow                 ; map row
        tay
        lda sloty_lut,y
        sta rbr_slot                 ; canvas slot row
        tay                          ; clear the BG_STRIDE x TH strip of slot row
        lda bgbuf_rowtop_lo,y
        sta cv_s
        lda bgbuf_rowtop_hi,y
        sta cv_s+1
        lda #<[BG_STRIDE-1]
        sta cv_w1
        lda #>[BG_STRIDE-1]
        sta cv_w1+1
        lda #TH-1
        sta cv_h1
        jsr cv_rect                  ; (the clear list: before the tiles)
        ldx rbr_mrow                 ; (X kept for the row base below)
        cpx #MAP_H
        bcs ?ret                     ; past bottom -> stays transparent
        lda rbr_slot
        sta r_row
        lda #MAP_W                   ; columns = min(NSX, MAP_W - cam_tcol)
        sec
        sbc cam_tcol
        cmp #NSX
        bcc ?ncok
        lda #NSX
?ncok   sta rbr_ncol
        lda map_row_bank,x           ; ztptr = map row base (index with map col)
        sta ?bk+1                    ; the row's bank as the loop's immediate
        lda map_row_lo,x
        sta ztptr
        lda map_row_hi,x
        sta ztptr+1
        lda #0                       ; A = rbr_i at the loop head
        clc                          ; loop-back arrives with C=0 (bcc taken)
?lp     sta rbr_i
        adc cam_tcol                 ; map column
        tay
?bk     lda #0                       ; re-set each tile (tl_add leaves BCB bank)
        sta VBXE_BANK_SEL
        lda (ztptr),y
        beq ?skip
        cmp #15
        beq ?skip                    ; invisible solid (barrel)
        tax                          ; X = the tile
        lda slotx_lut,y              ; Y = map column
        sta r_col                    ; ring slot column
        jsr tl_add
?skip   ldx rbr_i
        inx
        txa
        cmp rbr_ncol
        bcc ?lp
?ret    jmp tl_flush
rbr_mrow dta 0
rbr_slot dta 0
rbr_ncol dta 0
rbr_i    dta 0
.endp

; CLEAR_BGBUF - fill the BG_STRIDE x BG_H bg buffer with 0 (transparent).
; BCB written while a previous blit may run (it loaded its BCB at START);
; wait right before START, none after it: the fill runs under the tile list
; setup, tl_flush waits before its START.
.proc clear_bgbuf
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+0
        sta MEMW+[VRAM_BCB&$FFF]+1
        sta MEMW+[VRAM_BCB&$FFF]+2
        sta MEMW+[VRAM_BCB&$FFF]+3
        sta MEMW+[VRAM_BCB&$FFF]+4
        sta MEMW+[VRAM_BCB&$FFF]+5
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND=0 fill
        sta MEMW+[VRAM_BCB&$FFF]+16
        sta MEMW+[VRAM_BCB&$FFF]+17
        sta MEMW+[VRAM_BCB&$FFF]+18
        sta MEMW+[VRAM_BCB&$FFF]+19
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode 0
        sta MEMW+[VRAM_BCB&$FFF]+6   ; dst $061000
        lda #$10
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda #$06
        sta MEMW+[VRAM_BCB&$FFF]+8
        lda #<BG_STRIDE
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #>BG_STRIDE
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11
        lda #<[BG_STRIDE-1]
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #>[BG_STRIDE-1]
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #BG_H-1
        sta MEMW+[VRAM_BCB&$FFF]+14
        jmp wait_run                 ; START is ignored while a blit runs
.endp


; ============================================
; COPY_BG_WINDOW - copy the 320x192 window from the RING canvas at fine
; offset, split at the canvas seams into up to 4 sub-blits emitted as ONE
; chained BlitterList (single kick - the CPU never spins between parts).
; MODE 1 copy over this frame's sky (sky.asm: the sky BCB is first, it
; erases last frame's sprites; the canvas' colour-0 cells leave it).
; ============================================
.proc copy_bg_window
        ; This set's window list (frame.asm: the blitter runs the other one);
        ; it runs after the sky and on into the sprite list.
        lda ls_bank                  ; the set being built (frame.asm)
        sta VBXE_BANK_SEL
        ; --- window origin inside the ring canvas ---
        ldy cam_trow
        lda sloty_lut,y
        tax                          ; X = row slot 0..NSY-1 (until the row base)
        asl
        asl
        asl                          ; *TH (slot <= 24: shifts out 0, C=0)
        adc cam_fy                   ; source Y 0..BG_H-1, leaves C=0
        ; --- split heights: h1 = min(192, BG_H - sy), h2 = 192 - h1 ---
        eor #$FF
        adc #BG_H+1                  ; ~sy + BG_H+1 = BG_H - sy (C=0), leaves C=1
        cmp #GAME_H
        bcc ?h_ok
        lda #GAME_H
?h_ok   sta cbw_h1
        eor #$FF
        sec
        adc #GAME_H                  ; 192 - h1
        sta cbw_h2
        ; --- source X: slot(cam_tcol)*TW + cam_x%TW (0..BG_STRIDE-1) ---
        ldy cam_tcol
        lda slotx_lut,y              ; col slot 0..NSX-1
        asl
        asl
        asl                          ; slot*8 lo, C = bit 5 = hi (<= 320)
        sta zt
        lda #0
        rol @                        ; hi 0/1, leaves C=0
        sta cbw_sx+1
        lda cam_x
        and #TW-1
        adc zt                       ; C=0; zt low 3 bits 0 -> never carries
        sta cbw_sx                   ; source X 0..BG_STRIDE-1 (16-bit)
        ; --- split widths: w1 = min(320, BG_STRIDE - sx), w2 = 320 - w1 ---
        lda #<[BG_STRIDE+1]          ; C=0 (adc above) is the -1
        sbc cbw_sx
        sta cbw_w1
        lda #>[BG_STRIDE+1]
        sbc cbw_sx+1
        sta cbw_w1+1
        cmp #>SCR_W                  ; compare (BG_STRIDE-sx) with 320
        bcc ?w_split                 ; hi=0 -> < 256 -> split
        lda cbw_w1
        cmp #<SCR_W
        bcc ?w_split                 ; 256..319 -> split
        lda #<SCR_W                  ; >= 320 -> single span
        sta cbw_w1
        lda #>SCR_W
        sta cbw_w1+1
        lda #0
        sta cbw_w2
        sta cbw_w2+1
        beq ?w_done
?w_split
        lda #<[SCR_W+1]              ; w2 = 320 - w1: C=0 (bcc taken) is the -1
        sbc cbw_w1
        sta cbw_w2
        lda #>[SCR_W+1]
        sbc cbw_w1+1
        sta cbw_w2+1
?w_done
        ; --- src row base: cbw_row = $061000 + rowtop[srow] + fyrow[fy] ---
        ldy cam_fy
        lda bgbuf_rowtop_lo,x        ; X = row slot
        clc
        adc fyrow_lo,y
        sta cbw_row
        lda bgbuf_rowtop_hi,x
        adc fyrow_hi,y               ; C = carry into the bank byte
        ldx #$06                     ; bank byte = $06 + both carries
        bcc ?r1
        inx
        clc
?r1     adc #$10                     ; C=0 on both paths
        sta cbw_row+1
        bcc ?r2
        inx
?r2     stx cbw_row+2
        ; --- slot 0 of set A is also run_blit's BCB: its constant fields
        ;     again only after run_blit used it (cbw_k0); else cbw_template's ---
        lda cbw_k0
        beq ?k0                      ; @taken: true  (run_blit: menus, rebuilds)
        ldx #0
        jsr cbw_slot
        lda ls_bank                  ; set A's slot 0 restored: done (set B's
        cmp #BANK_EN+LS_PAGE_A       ; is never touched, A's stays to do)
        bne ?k0
        lda #0
        sta cbw_k0
?k0     lda #0
        ; --- sub-blit A (slot 0, always): src = row+sx, dst (0,0), w1 x h1 ---
        sta CBW_B0+6
        sta CBW_B0+7
        lda cbw_row
        clc
        adc cbw_sx
        sta CBW_B0+0
        lda cbw_row+1
        adc cbw_sx+1
        sta CBW_B0+1
        lda cbw_row+2
        adc #0                       ; bank byte <= 7 -> leaves C=0
        sta CBW_B0+2
        lda zbuf_hi
        sta CBW_B0+8
        lda cbw_w1
        sbc #0                       ; C=0: w1-1
        sta CBW_B0+12
        lda cbw_w1+1
        sbc #0                       ; w1 >= 1 -> leaves C=1
        sta CBW_B0+13
        ldy cbw_h1
        dey
        sty CBW_B0+14                ; Y = h1-1 (kept for B)
        lda #CBW_CTRL
        sta CBW_B0+20
        ldx #0                       ; X = offset of the last slot written
        ; --- B (slot 1, x-wrap): src = row, dst (w1,0), w2 x h1 ---
        lda cbw_w2
        ora cbw_w2+1
        beq ?no_b
        lda cbw_row
        sta CBW_B1+0
        lda cbw_row+1
        sta CBW_B1+1
        lda cbw_row+2
        sta CBW_B1+2
        lda #<BG_STRIDE              ; (a jump container may have been here)
        sta CBW_B1+3
        lda cbw_w1
        sta CBW_B1+6
        lda cbw_w1+1
        sta CBW_B1+7
        lda zbuf_hi
        sta CBW_B1+8
        lda cbw_w2
        sbc #1                       ; C=1 from A's size
        sta CBW_B1+12
        lda cbw_w2+1
        sbc #0                       ; w2 >= 1 -> leaves C=1
        sta CBW_B1+13
        sty CBW_B1+14                ; h1-1
        lda #CBW_CTRL
        sta CBW_B1+20
        ldx #21
?no_b                                ; C=1 on both paths
        ; --- C (next slot, y-wrap): src = $061000+sx, dst (0,h1), w1 x h2 ---
        lda cbw_h2
        jeq ?no_cd
        txa
        adc #20                      ; C=1: next slot = X + 21, leaves C=0
        tax
        lda cbw_sx
        sta CBW_B0+0,x
        lda cbw_sx+1
        adc #$10                     ; C=0; sx hi <= 1 -> leaves C=0
        sta CBW_B0+1,x
        lda #$06
        sta CBW_B0+2,x
        lda #<BG_STRIDE              ; (a jump container may have been here)
        sta CBW_B0+3,x
        ldy cbw_h1
        lda y_addr_lo,y
        sta CBW_B0+6,x
        lda y_addr_hi,y
        sta CBW_B0+7,x
        lda zbuf_hi
        sta CBW_B0+8,x
        lda cbw_w1
        sbc #0                       ; C=0: w1-1
        sta CBW_B0+12,x
        lda cbw_w1+1
        sbc #0                       ; leaves C=1
        sta CBW_B0+13,x
        lda cbw_h2
        sbc #1                       ; C=1: h2-1, h2 >= 1 -> leaves C=1
        sta CBW_B0+14,x
        lda #CBW_CTRL
        sta CBW_B0+20,x
        ; --- D (slot 3: exists only with B and C): src = $061000,
        ;     dst (w1,h1), w2 x h2 ---
        lda cbw_w2
        ora cbw_w2+1
        beq ?no_cd
        lda #$00
        sta CBW_B3+0
        lda #$10
        sta CBW_B3+1
        lda #$06
        sta CBW_B3+2
        lda #<BG_STRIDE              ; (a jump container may have been here)
        sta CBW_B3+3
        lda y_addr_lo,y              ; Y = h1
        clc
        adc cbw_w1
        sta CBW_B3+6
        lda y_addr_hi,y
        adc cbw_w1+1                 ; y_addr + w1 < 65536 -> leaves C=0
        sta CBW_B3+7
        lda zbuf_hi
        sta CBW_B3+8
        lda cbw_w2
        sbc #0                       ; C=0: w2-1
        sta CBW_B3+12
        lda cbw_w2+1
        sbc #0                       ; leaves C=1
        sta CBW_B3+13
        lda cbw_h2
        sbc #1                       ; C=1: h2-1
        sta CBW_B3+14
        lda #CBW_CTRL
        sta CBW_B3+20
        ldx #63
?no_cd
        ; on into the sprite list: after slot 3 it follows; an earlier last
        ; slot jumps there (1.27 container in the next slot's first 4 bytes:
        ; B, C and D write their +0..+3 when used)
        cpx #63
        beq ?r
        lda #$80+CBW_CTRL            ; EXTENDED: the jump
        sta CBW_B0+20,x
        lda #0
        sta CBW_B0+21,x
        lda #<SPRL_OFF
        sta CBW_B0+22,x
        lda ls_mid
        ora #>SPRL_OFF
        sta CBW_B0+23,x
        lda ls_hi
        sta CBW_B0+24,x
?r      rts
.endp
        ert CBW_B0+84<>SPRL_W
CBW_B0 = MEMW+[VRAM_BCB&$FFF]        ; window list slots in the MEMAC window
CBW_B1 = CBW_B0+21
CBW_B3 = CBW_B0+63
CBW_CTRL = BLT_TRANS+$08             ; MODE 1 (colour 0 leaves the sky) + NEXT
cbw_sx   dta 0,0                     ; source X in canvas (0..BG_STRIDE-1)
cbw_w1   dta 0,0                     ; left span width (1..320)
cbw_w2   dta 0,0                     ; wrapped span width (0..319)
cbw_h1   dta 0                       ; top span height (1..192)
cbw_h2   dta 0                       ; wrapped span height (0..191)
cbw_row  dta 0,0,0                   ; 24-bit src base of the window's top row
cbw_k0   dta 1                       ; 1: run_blit wrote set A's slot 0
; frame.asm (no room there): the pre-list slots pl_chain gave an absolute
; jump (hi 0: none), per set (ds_o 0 A, 3 B) and list; pl_reset undoes them
ds_o     dta 0
ds_lo    dta 0,0,0, 0,0,0
ds_hi    dta 0,0,0, 0,0,0

; CBW_TEMPLATE - constant fields of window list slots 0-3 (copy_bg_window
; never writes them; set A's slot 0 is restored after run_blit: cbw_k0).
; Both sets, at init (frame.asm lists_init).
.proc cbw_template
        lda ls_bank                  ; the set being built (frame.asm)
        sta VBXE_BANK_SEL
        ldx #63
?lp     jsr cbw_slot
        txa
        sec
        sbc #21
        tax
        bpl ?lp                      ; 63, 42, 21, 0
        rts
.endp

; CBW_SLOT - the constant fields of window list slot X/21 (keeps X)
.proc cbw_slot
        lda #<BG_STRIDE              ; src step = canvas stride
        sta CBW_B0+3,x
        lda #>BG_STRIDE
        sta CBW_B0+4,x
        lda #1
        sta CBW_B0+5,x
        sta CBW_B0+11,x
        lda #<SCR_W                  ; dst step 320
        sta CBW_B0+9,x
        lda #>SCR_W
        sta CBW_B0+10,x
        lda #$FF                     ; AND = copy
        sta CBW_B0+15,x
        lda #0
        sta CBW_B0+16,x
        sta CBW_B0+17,x
        sta CBW_B0+18,x
        sta CBW_B0+19,x
        rts
.endp

; ============================================
; UPDATE_CAMERA - follow player. cam_x = clamp(player_center - 160), smooth.
; cam_tcol = cam_x>>3 (cell column), fine offset = cam_x & 7. Vertical:
; cam_y = clamp(player_y - 96), cam_trow/cam_fy analogous.
; ============================================
; Targets live in X (lo) / Y (hi), not in zt/zt2; zt/zt2 still end = cam_y
; (shared scratch). Clobbers X/Y: both callers (main loop, init_render)
; go straight on to code that loads X/Y before reading them.

; (cam_to_ecam deleted 2026-11-11: nothing read ecam - 6502-idioms "delete
; what nothing reads")
.proc update_camera
        lda zpx
        clc
        adc #PL_W/2
        tax                         ; X = sum lo
        lda zpx_hi
        adc #0                      ; A = sum hi
        cpx #160                    ; C = no borrow out of (lo - 160)
        sbc #0                      ; A = target hi, C = same carry as hi-160
        bcc ?lo                     ; target negative -> 0
        tay                         ; Y = target hi
        txa
        sbc #160                    ; C=1 (bcc not taken) -> X = target lo
        tax
        ; clamp target (Y:X) to per-level cam_xmax (16-bit)
        cpy cam_xmax+1
        bcc ?store                  ; target_hi < max_hi -> in range
        bne ?hi                     ; target_hi > max_hi -> clamp
        cpx cam_xmax
        bcc ?store
        beq ?store                  ; target_lo <= max_lo -> in range
?hi     ldx cam_xmax
        ldy cam_xmax+1
        bcs ?store                  ; C=1: both ways in passed a not-taken bcc
?lo     ldx #0
        ldy #0
?store  stx cam_x
        sty cam_x_hi
        tya                         ; cam_tcol = hi*32 | lo>>3 (hi <= 1)
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,x
        sta cam_tcol
        ; --- vertical (16-bit): target = (zpy_hi:zpy) - 96 ---
        ; DEAD-ZONE: the camera moves only when the player drifts more than
        ; VCAM_DZ px from center. A normal jump arc (~36px) stays inside ->
        ; no canvas row work while jumping.
        lda zpy
        sec
        sbc #96
        tax
        lda zpy_hi
        sbc #0
        tay                         ; Y:X = raw target (signed)
        lda cam_vsnap
        bne ?snap
        ; diff = target - cam_y (16-bit signed)
        txa
        sec
        sbc cam_y
        sta zva
        tya
        sbc cam_y_hi
        bpl ?dz_pos
        cmp #$FF
        bne ?dz_up                  ; diff <= -256 -> move up
        lda zva
        cmp #256-VCAM_DZ
        bcs ?dz_keep                ; -DZ..-1 -> keep camera
?dz_up  txa                         ; candidate = target + DZ
        clc
        adc #VCAM_DZ
        tax
        bcc ?dz_clamp
        iny
        bcs ?dz_clamp               ; C=1: bcc not taken, iny keeps C
?snap   lda #0                      ; level start: snap straight to target
        sta cam_vsnap
        beq ?dz_clamp               ; Z=1 from lda #0
?dz_pos bne ?dz_dn                  ; diff >= 256 -> move down (Z from sbc)
        lda zva
        cmp #VCAM_DZ+1
        bcc ?dz_keep                ; 0..DZ -> keep camera
?dz_dn  txa                         ; candidate = target - DZ
        sec
        sbc #VCAM_DZ
        tax
        bcs ?dz_clamp
        dey
?dz_clamp
        ; clamp candidate (Y:X) to 0..cam_ymax
        tya
        bpl ?vy_pos
?vy_neg ldx #0                      ; negative -> 0 (0 <= cam_ymax: no clamp)
        ldy #0
        beq ?vy_ok
?dz_keep
        ldx cam_y                   ; inside dead-zone: camera stays put
        ldy cam_y_hi                ; N = sign of the hi byte
        bmi ?vy_neg
?vy_pos cpy cam_ymax+1              ; clamp to cam_ymax (16-bit)
        bcc ?vy_ok
        bne ?vy_clamp
        cpx cam_ymax
        bcc ?vy_ok
        beq ?vy_ok
?vy_clamp ldx cam_ymax
        ldy cam_ymax+1
?vy_ok  stx cam_y                   ; smooth cam_y (no snap)
        sty cam_y_hi
        stx zt
        sty zt2
        txa
        and #TH-1
        sta cam_fy                  ; fine vertical offset
        tya                         ; cam_trow = (cam_y_hi:cam_y) >> 3
        asl
        asl
        asl
        asl
        asl
        ora div8_lut,x
        sta cam_trow
        rts
.endp

; ============================================
; CANVAS TILE PATCH QUEUE - single-tile map changes (door open/close,
; switch toggle, wall remove, barrel solid). canvas_mark_tile queues the
; tile; canvas_apply_patches (main loop top, blitter idle) clears + reblits
; just that 16x16 canvas cell. Replaces the full 273-tile rebuild that cost
; ~79k CPU cycles + ~19 ms of blitter per door.
; ============================================
CQ_MAX = 8
cq_cnt dta 0
cq_col .ds CQ_MAX
cq_row .ds CQ_MAX

; CANVAS_MARK_TILE - queue map tile (A = column, Y = row). Preserves X.
; Queue overflow (barrel chains etc.) falls back to a full rebuild.
.proc canvas_mark_tile
        sty cq_tmpr
        ldy cq_cnt
        cpy #CQ_MAX
        bcs ?full
        sta cq_col,y
        lda cq_tmpr
        sta cq_row,y
        inc cq_cnt
        bne ?ret                ; (always: cq_cnt 1..CQ_MAX)
?full   lda #$FF                ; queue full -> full rebuild next frame
        sta last_cam_tcol
?ret    ldy cq_tmpr             ; restore Y for callers that reuse it
        rts
cq_tmpr dta 0
.endp

; CANVAS_APPLY_PATCHES - main loop top (blitter idle after the frame flip):
; patch every queued tile that lies inside the camera window. Off-window
; tiles are dropped - their ring slot currently belongs to a different map
; tile, and the edge strip render redraws them when they scroll into view.
.proc canvas_apply_patches
        lda cq_cnt
        bne ?have
        rts
?have   lda last_cam_tcol
        cmp #$FF
        beq ?done               ; full rebuild pending: queue is superseded
        ldx #0
?lp     cpx cq_cnt
        bcs ?done
        stx cq_idx
        lda cq_col,x            ; window-relative col 0..NSX-1, else skip
        sec
        sbc cam_tcol
        cmp #NSX
        bcs ?next               ; off-window (also catches negative)
        lda cq_row,x
        sec
        sbc cam_trow
        cmp #NSY
        bcs ?next
        jsr canvas_patch_one
?next   ldx cq_idx
        inx
        bne ?lp
?done   lda #0
        sta cq_cnt
        rts
cq_idx  dta 0
.endp

; CANVAS_PATCH_ONE - clear + reblit the canvas cell of queue entry X.
.proc canvas_patch_one
        ldy cq_col,x
        sty cp_mcol
        lda slotx_lut,y
        sta cp_cslot            ; ring slot column
        ldy cq_row,x
        sty cp_mrow
        lda sloty_lut,y
        sta cp_rslot            ; ring slot row
        ; clear the cell: cv_s = rowtop[rslot] + colx[cslot]
        tay
        ldx cp_cslot
        lda bgbuf_rowtop_lo,y
        clc
        adc bgcolx_lo,x
        sta cv_s
        lda bgbuf_rowtop_hi,y
        adc bgcolx_hi,x
        sta cv_s+1
        lda #TW-1               ; = TH-1 (ert below): width-1 and height-1
        sta cv_w1
        sta cv_h1
        ert TW<>TH
        lda #0
        sta cv_w1+1
        jsr cv_rect             ; fill 0 (transparent -> sky shows through)
        ; read the (already updated) map tile and reblit it
        ldy cp_mrow
        lda map_row_bank,y
        sta VBXE_BANK_SEL
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldy cp_mcol
        lda (ztptr),y
        beq ?done               ; empty -> cell stays transparent
        cmp #15
        beq ?done               ; invisible solid (barrel)
        tax                     ; X = the tile
        lda cp_cslot
        sta r_col
        lda cp_rslot
        sta r_row
        jsr tl_add
        jmp tl_flush            ; tail call (jsr/rts -> jmp)
?done   rts
cp_mcol  dta 0
cp_mrow  dta 0
cp_cslot dta 0
cp_rslot dta 0
.endp
