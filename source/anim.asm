;==============================================
; DOOM2D - Animated textures (D2DF ANIM.txt: torches, candles, ...)
; anim.asm
;
; d2df2map gives the animated tiles of a texture consecutive tile ids and
; stores their frames back to back in VRAM_ANIM (frame k of all of them, then
; frame k+1). Every waitcount ticks ONE blit copies the next frame of all of a
; texture's tiles into the tileset; then the visible cells of its panels are
; recopied (opaque, one tile list) into the bg canvas.
;==============================================

VRAM_ANIM = $014000             ; the frames ($014000-$01BFFF)
AT_MAX    = 8                   ; animated textures / their panels per level
AP_MAX    = 40                  ; (d2df2map AT_MAX, AP_MAX, ANIM_RAM_BYTES)
ANIM_SECTORS = 2

; The level's tables (ANIM_SECTORS read at load), in LVL_BUF after the pickups
ANIM_RAM  = $8E00
n_at      = ANIM_RAM            ; animated textures
n_ap      = ANIM_RAM+1          ; their panels
at_id0    = ANIM_RAM+2          ; first tile id
at_n      = at_id0+AT_MAX       ; tiles
at_fr     = at_n+AT_MAX         ; frames
at_wait   = at_fr+AT_MAX        ; ticks a frame (36 Hz)
at_vlo    = at_wait+AT_MAX      ; frame 0 in VRAM_ANIM (16-bit offset)
at_vhi    = at_vlo+AT_MAX
ap_t      = at_vhi+AT_MAX       ; panel: its texture
ap_c0     = ap_t+AP_MAX         ; and its animated cells [c0, c1) x [r0, r1)
ap_r0     = ap_c0+AP_MAX
ap_c1     = ap_r0+AP_MAX
ap_r1     = ap_c1+AP_MAX
        ert ap_r1+AP_MAX>ANIM_RAM+ANIM_SECTORS*128
at_cur    = ANIM_RAM+ANIM_SECTORS*128   ; runtime: the frame shown
at_tmr    = at_cur+AT_MAX               ; ticks to the next one
        ert at_tmr+AT_MAX>MEMW
        ert ANIM_RAM<pk_row+MAX_PICKUPS


; ============================================
; ANIM_LOAD - after trig_load (DAUX continues): the tables into ANIM_RAM and
; the frames into VRAM_ANIM. C=1 on an SIO error.
; ============================================
.proc anim_load
        lda #0
        sta n_at
        lda an_sectors
        beq ?ok                 ; no animated texture
        lda #<ANIM_RAM
        sta DBUFLO
        lda #>ANIM_RAM
        sta DBUFHI
        ldx #ANIM_SECTORS
        jsr read_sectors.win
        bcs ?r
        lda #BANK_EN+[VRAM_ANIM>>12]
        sta vram_sio.vs_bank
        lda an_sectors
        clc                     ; read
        jsr vram_sio.go
        bcs ?r
        ldx #AT_MAX-1           ; frame 0 shown, a whole wait to the next
?t      lda at_wait,x
        sta at_tmr,x
        lda #0
        sta at_cur,x
        dex
        bpl ?t
?ok     clc
?r      rts
.endp
an_sectors dta 0                ; level header +11

; ============================================
; ANIM_TICK - main loop top (blitter idle after the flip): per 36 Hz tick,
; every texture whose wait ran out shows its next frame
; ============================================
.proc anim_tick
        lda an_tk               ; the last frame's animation ticks (main.asm)
        beq ?r
        sta ?k+1
        lda #0                  ; once (init_render composites twice)
        sta an_tk
        ldx n_at
        beq ?r
?lp     dex
        bmi ?r
?k      ldy #0                  ; (patched: the ticks)
        lda #0
        sta ?st+1
?tk     dec at_tmr,x            ; TAnimation.update per tick
        bne ?tn
        lda at_wait,x
        sta at_tmr,x
        sta ?st+1               ; (<> 0) a new frame
        lda at_cur,x            ; next frame, 0 after the last
        clc
        adc #1
        cmp at_fr,x
        bcc ?f
        lda #0
?f      sta at_cur,x
?tn     dey
        bne ?tk
?st     lda #0                  ; (patched)
        beq ?lp
        stx at_i
        jsr at_step             ; once a frame: the frame it reached
        ldx at_i
        bpl ?lp                 ; (always: X < AT_MAX)
?r      rts
.endp
at_i    dta 0
an_tk   dta 0                   ; animation ticks for anim_tick (main.asm)

; AT_STEP - texture X: its frame at_cur into the tileset (one blit), then
; its visible panel cells into the canvas
.proc at_step
        lda at_n,x              ; ?sz = n * 64 (a frame of all its tiles)
        lsr
        sta ?sz+1
        lda #0
        ror
        lsr ?sz+1
        ror
        sta ?sz
        lda at_vhi,x            ; src = VRAM_ANIM + v + cur * ?sz
        sta ?s+1
        lda at_vlo,x            ; lo in A, X free (at_i reloads it below)
        ldy at_cur,x
        beq ?a
?m      clc
        adc ?sz
        tax
        lda ?s+1
        adc ?sz+1
        sta ?s+1
        txa
        dey
        bne ?m
?a      sta ?s
        jsr ab_add              ; a frame copy slot (frame.asm): pl_p, Y = 0
        ldx at_i
        lda ?s
        sta (pl_p),y            ; +0
        lda ?s+1                ; C=0: the adds above stay < $8000
        clc
        adc #>VRAM_ANIM
        iny
        sta (pl_p),y            ; +1
        lda #VRAM_ANIM>>16
        iny
        sta (pl_p),y            ; +2
        lda at_id0,x            ; lo = (id0 & 3) << 6: lsr/ror/ror rotate
        lsr                     ; bits 1-0 through C into bits 7-6
        ror
        ror
        and #$C0
        ldy #6
        sta (pl_p),y            ; +6 dst = VRAM_TILESET + id0 * 64
        lda at_id0,x
        lsr
        lsr
        ora #>VRAM_TILESET      ; = adc: id0/4 < $40 meets no set bit
        ert [>VRAM_TILESET]&$3F
        iny
        sta (pl_p),y            ; +7
        lda #VRAM_TILESET>>16
        iny
        sta (pl_p),y            ; +8
        lda at_n,x
        sec
        sbc #1
        ldy #14
        sta (pl_p),y            ; +14 height - 1 = tiles - 1
        lda last_cam_tcol
        cmp #$FF
        bne at_cells            ; else a full rebuild is pending: it draws
        rts                     ; the new frame
?s      dta 0,0
?sz     dta 0,0
.endp

; AT_CELLS - texture X: every cell of its panels inside the ring window,
; recopied opaque (tile list in copy mode: no clear needed)
.proc at_cells
        stx ?t+1
        lda #$80+$08            ; tl_add: opaque copy (mode 0)
        sta tl_add.md+1
        ldy n_ap
        bpl ?pl                 ; (always: n_ap <= AP_MAX)
?end    jsr tl_flush
        lda #$80+BLT_TRANS+$08  ; back to the transparent tile list
        sta tl_add.md+1
        rts
?pl     dey
        bmi ?end
        lda ap_t,y
?t      cmp #0                  ; (patched: the texture)
        bne ?pl
        sty ?p
        ; rows [max(r0, cam_trow), min(r1, cam_trow + NSY))
        lda cam_trow
        clc
        adc #NSY
        cmp ap_r1,y
        bcc ?rh
        lda ap_r1,y
?rh     sta ?r1
        lda ap_r0,y
        cmp cam_trow
        bcs ?rl
        lda cam_trow
?rl     sta ?row
        lda cam_tcol
        clc
        adc #NSX
        cmp ap_c1,y
        bcc ?ch
        lda ap_c1,y
?ch     sta ?c1
        lda ap_c0,y
        cmp cam_tcol
        bcs ?cl
        lda cam_tcol
?cl     sta ?c0
?rw     lda ?row
        cmp ?r1
        bcs ?nx                 ; no (more) rows in the window
        tay
        lda sloty_lut,y
        sta r_row
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        lda map_row_bank,y
        sta ?mb+1
        lda ?c0
        sta ?col
?cw     lda ?col
        cmp ?c1
        bcs ?nr
        tay
        lda slotx_lut,y
        sta r_col
?mb     lda #0                  ; (patched: the map row's bank)
        sta VBXE_BANK_SEL
        lda (ztptr),y
        tax                     ; X = the tile
        jsr tl_add              ; (sets the pre bank; a full list runs)
        inc ?col
        bne ?cw                 ; (always: col < MAP_W)
?nr     inc ?row
        bne ?rw                 ; (always)
?nx     ldy ?p
        jmp ?pl
?p      dta 0
?row    dta 0
?r1     dta 0
?col    dta 0
?c0     dta 0
?c1     dta 0
.endp

