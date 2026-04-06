;==============================================
; DOOM2D - Dirty tile tracking for optimized rendering
; dirty.asm
;
; Instead of redrawing all 240 tiles every frame,
; only restore tiles that had sprites on them.
;==============================================

; Dirty flags: 1 byte per tile, 0=clean, 1=dirty
; Separate array per double-buffer
dirty_0 .ds TILES_X*TILES_Y    ; 240 bytes for buffer 0
dirty_1 .ds TILES_X*TILES_Y    ; 240 bytes for buffer 1


; ============================================
; SETUP DIRTY POINTER for current back buffer
; ============================================
.proc setup_dirty_ptr
        lda zbuf_hi
        bne ?buf1
        lda #<dirty_0
        sta dirty_ptr
        lda #>dirty_0
        sta dirty_ptr+1
        rts
?buf1   lda #<dirty_1
        sta dirty_ptr
        lda #>dirty_1
        sta dirty_ptr+1
        rts
.endp


; ============================================
; CLEAR ALL DIRTY FLAGS (both buffers, for init)
; ============================================
.proc clear_dirty_all
        lda #0
        ldy #TILES_X*TILES_Y-1
?lp     sta dirty_0,y
        sta dirty_1,y
        dey
        bpl ?lp
        rts
.endp

; init_render is in the overlay segment (end of main.asm)

; ============================================
; RENDER STATIC: bake pickups + decorations into background
; Called once per buffer during init_render.
; No mark_dirty - these are part of the background.
; ============================================
.proc render_static
        ; --- Pickups ---
        ldx #0
?pk     lda pk_act,x
        beq ?pnx
        stx rs_idx
        lda pk_x,x
        sta zdx
        lda pk_xhi,x
        sta zdxh
        lda pk_y,x
        sec
        sbc #16
        bcc ?pnx2
        sta zdy
        ldx rs_idx
        lda pk_type,x
        tax
        lda pk_spr_tab,x
        jsr blit_sprite
?pnx2   ldx rs_idx
?pnx    inx
        cpx #MAX_PICKUPS
        bne ?pk

        ; --- Decorations ---
        jsr render_decorations
        rts
rs_idx  dta 0
.endp

; ============================================
; RESTORE DIRTY TILES
; Re-blits only tiles marked dirty, then clears flags.
; Call at start of render phase (before drawing sprites).
; ============================================
; Dirty bounding box (set by restore_dirty, used by static redraw)
dirty_min_col dta TILES_X
dirty_max_col dta 0
dirty_min_row dta TILES_Y
dirty_max_row dta 0
dirty_any     dta 0             ; 0 = no dirty tiles this frame

.proc restore_dirty
        jsr setup_dirty_ptr
        ; Reset bounding box
        lda #TILES_X
        sta dirty_min_col
        lda #TILES_Y
        sta dirty_min_row
        lda #0
        sta dirty_max_col
        sta dirty_max_row
        sta dirty_any
        sta rd_idx
        sta r_row
?rrow   lda #0
        sta r_col
?rcol   ldy rd_idx
        lda (dirty_ptr),y
        beq ?clean

        ; --- Dirty tile: restore it ---
        ; Clear flag
        lda #0
        sta (dirty_ptr),y

        ; Update bounding box
        lda #1
        sta dirty_any
        lda r_col
        cmp dirty_min_col
        bcs ?nc1
        sta dirty_min_col
?nc1    cmp dirty_max_col
        bcc ?nc2
        sta dirty_max_col
?nc2    lda r_row
        cmp dirty_min_row
        bcs ?nc3
        sta dirty_min_row
?nc3    cmp dirty_max_row
        bcc ?nc4
        sta dirty_max_row
?nc4
        ; Look up map tile at (r_col, r_row) [inlined calc_map_ptr]
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        ldy r_row
        lda map_row_lo,y
        clc
        adc r_col
        sta ztptr
        lda map_row_hi,y
        adc #0
        sta ztptr+1

        ldy #0
        lda (ztptr),y
        beq ?empty
        cmp #15
        beq ?empty             ; tile 15 = invisible solid (barrel), draw sky
        ; Non-empty tile: blit it
        sta r_tile
        jsr blit_tile
        jmp ?clean
?empty  ; Empty/invisible tile: restore sky background
        jsr blit_bg

?clean  inc rd_idx
        inc r_col
        lda r_col
        cmp #TILES_X
        bcc ?rcol
        inc r_row
        lda r_row
        cmp #TILES_Y
        bcc ?rrow
        rts
rd_idx  dta 0
.endp

; ============================================
; MARK DIRTY SPRITE
; Marks tiles covered by sprite at (zdx:zdxh, zdy)
; with size md_w x md_h as dirty.
; Call BEFORE blit_sprite for each sprite.
;
; Tiles are 16x16 px, so pixel-to-tile conversion = divide by 16.
; For X: tiles can span 0-319 (20 cols), needing 16-bit pixel coords.
;   tile_col = (zdxh:zdx) / 16 = (zdxh << 4) | (zdx >> 4)
; For Y: tiles span 0-191 (12 rows), 8-bit is enough.
;   tile_row = zdy / 16 = zdy >> 4
; ============================================
.proc mark_dirty_sprite
        ; --- Left column = pixel X / 16 ---
        lda zdxh
        cmp #2
        bcc ?onscr
        rts                     ; off screen right (X>=512), skip
?onscr
        asl                     ; zdxh << 4: hi byte contributes bits 4+
        asl
        asl
        asl
        sta md_cl
        lda zdx
        lsr                     ; zdx >> 4: lo byte contributes bits 0-3
        lsr
        lsr
        lsr
        ora md_cl               ; combine into tile column
        sta md_cl

        ; --- Right column = (X + width - 1) / 16 ---
        lda zdx                 ; 16-bit: zt2:zt = zdx:zdxh + md_w - 1
        clc
        adc md_w
        sta zt
        lda zdxh
        adc #0
        sta zt2
        lda zt                  ; subtract 1 for rightmost pixel
        sec
        sbc #1
        sta zt
        lda zt2
        sbc #0
        sta zt2
        lda zt2                 ; same pixel-to-tile formula
        asl
        asl
        asl
        asl
        sta md_cr
        lda zt
        lsr
        lsr
        lsr
        lsr
        ora md_cr
        sta md_cr

        ; --- Top row = Y / 16 ---
        lda zdy
        lsr
        lsr
        lsr
        lsr
        sta md_rt

        ; --- Bottom row = (Y + height - 1) / 16 ---
        lda zdy
        clc
        adc md_h
        sec
        sbc #1
        lsr
        lsr
        lsr
        lsr
        sta md_rb

        ; --- Clamp to screen bounds ---
        lda md_cl
        cmp #TILES_X
        bcc ?cl_ok
        rts                     ; left col >= 20: entirely off screen
?cl_ok
        lda md_cr
        cmp #TILES_X
        bcc ?cr_ok
        lda #TILES_X-1
        sta md_cr
?cr_ok  lda md_rt
        cmp #TILES_Y
        bcc ?rt_ok
        rts                     ; top row >= 12: below screen
?rt_ok
        lda md_rb
        cmp #TILES_Y
        bcc ?rb_ok
        lda #TILES_Y-1
        sta md_rb
?rb_ok
        ; --- Mark tiles in rectangle [md_cl..md_cr] x [md_rt..md_rb] ---
        lda md_rt
        sta md_r
?rlp    ; dirty_idx = md_r * 20 + md_c
        ldx md_r
        lda row_x20,x
        sta md_base             ; row * 20

        lda md_cl
        sta md_c
?clp    lda md_base
        clc
        adc md_c
        tay
        lda #1
        sta (dirty_ptr),y

        lda md_c
        cmp md_cr
        bcs ?rnx                ; done with this row
        inc md_c
        jmp ?clp

?rnx    lda md_r
        cmp md_rb
        bcs ?done               ; done with all rows
        inc md_r
        jmp ?rlp

?done   rts

md_cl   dta 0                   ; left column
md_cr   dta 0                   ; right column
md_rt   dta 0                   ; top row
md_rb   dta 0                   ; bottom row
md_r    dta 0                   ; current row
md_c    dta 0                   ; current column
md_base dta 0                   ; row * 20
.endp

; Sprite size params (set before calling mark_dirty_sprite)
md_w    dta 0
md_h    dta 0
