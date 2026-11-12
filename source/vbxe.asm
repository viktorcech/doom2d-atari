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
; SPL_TEMPLATE - the sprite list's slots in this set (frame.asm
; lists_init; only blit_sprite & co write them, and only src/step/dst/size/
; ctrl): src step hi 0 + mode 1, dst step 320, AND $FF, XOR 0, cmask 0 (no
; collision cost), ctrl = BLT_TRANS + NEXT. Leaves spl_ptr at the start.
.proc spl_template
        lda ls_bank
        sta VBXE_BANK_SEL
        jsr spl_reset
        ldx #SPRL_MAX
?tl     ldy #20
?tf     lda spl_tmpl,y
        sta (spl_ptr),y
        dey
        bpl ?tf
        lda spl_ptr
        clc
        adc #21
        sta spl_ptr
        bcc ?tn
        inc spl_ptr+1
?tn     dex
        bne ?tl
        ; (falls into spl_reset)
        ert *<>spl_reset
.endp
; SPL_RESET - empty sprite list (spl_ptr = first slot)
.proc spl_reset
        lda #<SPRL_W
        sta spl_ptr
        lda #>SPRL_W
        sta spl_ptr+1
        rts
.endp

; SPL_ROOM - select the list's bank; C=1: the sprite list is full. Keeps X, Y.
.proc spl_room
        lda ls_bank
        sta VBXE_BANK_SEL
        lda spl_ptr
        cmp #<[SPRL_W+SPRL_MAX*21]
        lda spl_ptr+1
        sbc #>[SPRL_W+SPRL_MAX*21]
        rts
.endp

; SPL_END - A = the slot's ctrl (+20), then the next slot. Keeps X.
.proc spl_end
        ldy #20
        sta (spl_ptr),y
        lda spl_ptr
        clc
        adc #21
        sta spl_ptr
        bcc ?r
        inc spl_ptr+1
?r      rts
.endp
spl_tmpl dta 0,0,0, 0,0,1, 0,0,0, <SCR_W,>SCR_W,1, 0,0,0, $FF, 0,0,0,0, BLT_TRANS+$08
; Sprite BlitterList: right after the 4 window-list slots (VRAM_BCB+0..83).
; Room for every blit_sprite call of a frame (50 enemies + 12 pickups +
; 16 decorations (+ their explosions) + 4 + 3 projectiles + player + 4 HUD).
SPRL_MAX      = 110
VRAM_SPRL     = VRAM_BCB+84
SPRL_W        = MEMW+[VRAM_SPRL&$FFF]
        ert [VRAM_SPRL&$FFF]+[SPRL_MAX+1]*21>$1000 ; inside the 4K MEMAC page (+1: spl_close's end after a link)
spl_lk  dta 0,0                 ; spl_ptr right after the blood link (bl_draw)

; SPL_CLOSE - the sprite list ends at its last BCB (ctrl without NEXT); an
; empty one gets a BCB that writes nothing (the window list runs into it)
.proc spl_close
        lda ls_bank
        sta VBXE_BANK_SEL
        lda spl_ptr                     ; the blood link last (bl_draw)? Its list
        cmp spl_lk                      ; jumps back HERE, past the link's last
        bne ?ne                         ; slot: the end must be a BCB here too
        lda spl_ptr+1                   ; (2026-10-30: else the old slots ran on,
        cmp spl_lk+1                    ; an old link among them = an endless list)
        beq ?end
?ne     lda spl_ptr
        cmp #<SPRL_W
        bne ?go
        lda spl_ptr+1
        cmp #>SPRL_W
        bne ?go
?end    lda zbuf_hi                     ; (+8: the stamped bank stays: ls_stamp)
        sta ?nop+8
        ldy #20                         ; empty: a 1-byte mode 1 copy of a 0
?e      lda ?nop,y
        sta (spl_ptr),y
        dey
        bpl ?e
        rts
?go     lda spl_ptr                     ; ptr-1 = ctrl byte of the last BCB
        bne ?d
        dec spl_ptr+1
?d      dec spl_ptr
        ldy #0
        lda (spl_ptr),y                 ; last: its mode kept, the list ends
        and #$F7                        ; here (NEXT off)
        sta (spl_ptr),y
        rts
?nop    dta <HUD_ZERO,>HUD_ZERO,^HUD_ZERO, 0,0,1, 0,0,0, <SCR_W,>SCR_W,1
        dta 0,0,0, $FF, 0,0,0,0, BLT_TRANS
.endp

; SPL_FLUSH - the sprite list at once (menus, save slots: no frame list
; runs there): close it, wait, START, empty it
.proc spl_flush
        jsr spl_close
        jsr wait_blit                   ; START is ignored while a blit runs
        lda #<SPRL_OFF
        sta VBXE_BL_ADR0
        lda ls_mid
        ora #>SPRL_OFF
        sta VBXE_BL_ADR1
        lda ls_hi
        sta VBXE_BL_ADR2
        lda #1
        sta VBXE_BLITTER
        jmp spl_reset
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
        ; dst = buffer start (A = 0)
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
        ; Restore normal BCB state: no wait - the running fill loaded its BCB
        ; at START, and the next blit waits before its START (run_blit
        ; leaves the bank select alone)
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND = $FF
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+16
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        rts
.endp

; WAIT_RUN - wait_blit, then fall into run_blit (the callers' shared tail)
wait_run
        jsr wait_blit           ; START is ignored while a blit runs
        ert *<>run_blit

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
        sta cbw_k0             ; A = 1: set A's window slot 0 changed (camera.asm)
        rts
.endp

; WAIT_BLIT - wait for the blitter. Hardened: idle only when BUSY reads 0
; twice in a row - BUSY can drop to 0 for an instant between chained BCBs
; (the window list), and a START in that gap restarts the list.
.proc wait_blit
?w      lda VBXE_BLITTER
        bne ?w
        lda VBXE_BLITTER        ; second read
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

; Frames per second threshold (60 NTSC / 50 PAL), set once at init
fps_thr dta 60
; Tile texture source address (TW x TH = 64 B per tile, 256 tiles), lo/mid
; bytes; the bank byte is constant. Page-aligned in free RAM below the code.
tile_src_save = *
        org $0900
tile_src_lo
        :256 dta <[VRAM_TILESET+#*TW*TH]
tile_src_mi
        :256 dta >[VRAM_TILESET+#*TW*TH]
        org tile_src_save
        ert [VRAM_TILESET&$FFFF]+256*TW*TH>$10000   ; one bank byte for all tiles

; ============================================
; BLIT SPRITE (transparent — color 0 = see-through)
; Input: A = sprite index, zdx/zdxh = X pos, zdy = Y pos
; Sprites (data/spr_small.asm) at spr_off_bank:spr_off_hi:spr_off_lo.
; Handles right-edge and bottom-edge clipping automatically.
; ============================================
.proc blit_sprite
        tax
        ; --- Camera offset (world sprites): screen X = world X - cam_x ---
        ; spr_cam=0 for HUD (screen-fixed). Off-left (result <0 -> zdxh>=$80)
        ; is culled by the right-edge clip below (zdxh>=2 -> skip).
        lda spr_cam
        beq ?nocam
        lda zdx
        sec
        sbc cam_x
        sta zdx
        lda zdxh
        sbc cam_x_hi
        sta zdxh
        lda zdy                 ; screen Y = (zdy_hi:zdy world) - (cam_y_hi:cam_y)
        sec
        sbc cam_y
        sta zdy
        lda zdy_hi
        sbc cam_y_hi
        jne ?skip               ; hi != 0 -> off-screen vertically -> cull
?nocam
        ; --- Right-edge clipping ---
        ; Screen is 320px wide. zdxh:zdx is 16-bit X position.
        ; zdxh>=2: entirely off screen (X>=512)
        ; zdxh=1:  partially visible, clip to 320-256=64 available px
        ; zdxh=0:  fully visible (max right edge = 255+16 = 271 < 320)
        lda zdxh                ; 2026-11-10 6502-idioms.md "cmp #0 after lda:
        beq ?clip_rok           ; Z is already set": 0 first, then 1, else skip
        cmp #1
        jne ?skip
?clip_r lda #64                 ; available pixels = 320 - 256 - zdx (C=1: equal)
        sbc zdx
        beq ?cr_off
        bcc ?cr_off             ; zdx >= 64: sprite fully off right edge
        cmp spr_w,x
        bcs ?clip_rok           ; available >= sprite width: no clip needed
        sta bs_w                ; clipped width = available pixels
        bcc ?chk_bot            ; (always: bcs not taken)
?cr_off jmp ?skip
?clip_rok
        lda spr_w,x
        sta bs_w

?chk_bot
        ; --- Bottom-edge clipping ---
        ; World sprites (spr_cam=1) clip at GAME_H: the HUD band below is only
        ; redrawn on change, so they must never paint into it. HUD sprites
        ; (spr_cam=0) clip at SCR_H: weapon/key icons live at Y=184-199.
        lda #GAME_H
        ldy spr_cam
        bne ?cl_set
        lda #SCR_H
?cl_set sta bs_clip
        lda zdy
        cmp bs_clip
        jcs ?skip               ; top edge below clip line -> fully culled
                                ; (otherwise clip-zdy underflows to a huge height)
        lda spr_h,x
        sta bs_h
        adc zdy                 ; C=0 (jcs not taken)
        cmp bs_clip
        bcc ?no_bclip
        beq ?no_bclip           ; bottom == clip line exactly -> fits
        lda bs_clip             ; clipped height = clip - zdy
        sbc zdy                 ; C=1 (bcc not taken); zdy < bs_clip -> 1..
        sta bs_h
?no_bclip
        lda spr_cam             ; a world sprite: its rect for fore_part
        beq ?hud
        jsr sr_add              ; (keeps X)
?hud
        ; --- Append a BCB to the frame's sprite list (spl_flush starts the
        ; whole list once, after the window copy). The CPU builds it while
        ; the blitter copies the window: no wait here. Constant fields come
        ; from the setup_xdl template; order of the list = order of calls.
        lda ls_bank             ; the set being built (frame.asm)
        sta VBXE_BANK_SEL
        ldy #0                          ; source VRAM address (spr_small.asm)
        lda spr_off_lo,x
        sta (spl_ptr),y                 ; +0 src addr lo
        iny
        lda spr_off_hi,x
        sta (spl_ptr),y                 ; +1 src addr mid
        iny
        lda spr_off_bank,x
        sta (spl_ptr),y                 ; +2 src addr hi
        iny
        ; Source row step = full sprite width (not clipped, to skip hidden cols)
        lda spr_w,x
        sta (spl_ptr),y                 ; +3 src step lo (hi 0: template)
        ldy #5
        lda #1
        sta (spl_ptr),y                 ; +5 src step x (blit_frame mirrors: $FF)
        ; Destination = y_addr[zdy] + zdx + buffer base (calc_dst, written
        ; straight into the BCB)
        ldx zdy
        lda y_addr_lo,x
        clc
        adc zdx
        ldy #6
        sta (spl_ptr),y                 ; +6 dst addr lo
        iny
        lda y_addr_hi,x
        adc zdxh
        sta (spl_ptr),y                 ; +7 dst addr mid
        ; Blit size = (clipped width - 1) x (clipped height - 1); width-1 hi,
        ; dst step, AND, XOR, cmask: template
        lda bs_w
        sbc #0                          ; C=0: bs_w-1; bs_w >= 1 -> leaves C=1
        ldy #12
        sta (spl_ptr),y                 ; +12 width-1 lo
        lda bs_h
        sbc #1                          ; C=1 from above
        ldy #14
        sta (spl_ptr),y                 ; +14 height-1
        lda #BLT_TRANS+$08              ; transparent + NEXT (spl_flush ends it)
        ldy #20
        sta (spl_ptr),y                 ; +20 ctrl
        lda spl_ptr                     ; next slot
        adc #21-1                       ; C=1 from the height sbc: +21
        sta spl_ptr
        bcc ?skip
        inc spl_ptr+1
?skip   rts
.endp

; SR_ADD - this world sprite's screen rect for fore_part's pass-2 reject:
; x/2, ceil((x+w)/2), y, y+h (zdxh:zdx, zdy, bs_w, bs_h, clipped). Past
; SR_MAX: sr_n = $FF, every foreground part draws. Keeps X.
.proc sr_add
        ldy sr_n
        cpy #SR_MAX
        bcs ?full               ; (also sr_n = $FF already)
        lda zdxh
        lsr
        lda zdx
        ror
        sta sr_x0,y
        lda zdx
        clc
        adc bs_w
        sta ?l+1
        lda zdxh
        adc #0
        lsr
?l      lda #0                  ; (patched: (x+w) lo)
        ror
        adc #0                  ; C = the dropped bit: ceil (< 256: C=0)
        sta sr_x1,y
        lda zdy
        sta sr_y0,y
        adc bs_h
        sta sr_y1,y
        iny
        sty sr_n
        rts
?full   lda #$FF
        sta sr_n
        rts
.endp

; SR_HIT - C=1: a world sprite of this frame overlaps the foreground part
; fo_x (16-bit), fo_y, bs_w x bs_h (or sr_n = $FF: assume one does).
.proc sr_hit
        ldx sr_n
        bmi ?yes
        beq ?no                 ; (C=1 from nothing: clear it)
        lda fo_x+1              ; x/2, ceil((x+w)/2), y+h as sr_add keeps them
        lsr
        lda fo_x
        ror
        sta ?x0+1
        lda fo_x
        clc
        adc bs_w
        sta ?l+1
        lda fo_x+1
        adc #0
        lsr
?l      lda #0                  ; (patched: (x+w) lo)
        ror
        adc #0                  ; C = the dropped bit: ceil
        sta ?x1+1
        lda fo_y
        sta ?fy+1
        adc bs_h                ; C=0: the ceil above is < 256
        sta ?y1+1
        dex                     ; sprites, last first, down to 0 (sr_n <= SR_MAX)
?lp     lda sr_x0,x             ; overlap on both axes?
?x1     cmp #0
        bcs ?nx
?x0     lda #0
        cmp sr_x1,x
        bcs ?nx
        lda sr_y0,x
?y1     cmp #0
        bcs ?nx
?fy     lda #0                  ; (patched: fo_y)
        cmp sr_y1,x
        bcc ?yes
?nx     dex
        bpl ?lp
?no     clc
        rts
?yes    sec
        rts
.endp

; ============================================
; BLIT_FRAME - append one monster frame (mon_frames.asm mf_*) to the sprite
; list, clipped to the game window on all four sides.
; X = frame, zdxh:zdx / zdy_hi:zdy = its top-left in the world, bf_mir =
; $FF to draw it mirrored (source read right to left: step x -1), else 0.
; Frames are at most 64 wide (prepare_sprites.py), so x in 0..255 always
; fits the 320 px screen.
; ============================================
; IT_BLIT - item frame Y (it_*): its record into IT_SLOT, drawn unmirrored
.proc it_blit
        lda it_lo,y
        sta mf_lo+IT_SLOT
        lda it_mi,y
        sta mf_mi+IT_SLOT
        lda it_bk,y
        sta mf_bk+IT_SLOT
        lda it_w,y
        sta mf_w+IT_SLOT
        lda it_h,y
        sta mf_h+IT_SLOT
        lda #0
        sta bf_mir
        ldx #IT_SLOT
.endp
        ert *<>blit_frame       ; falls through
.proc blit_frame
        lda zdx                 ; screen = world - camera (16-bit signed)
        sec
        sbc cam_x
        sta zdx
        lda zdxh
        sbc cam_x_hi
        sta zdxh
        lda zdy
        sec
        sbc cam_y
        sta zdy
        lda zdy_hi
        sbc cam_y_hi
        beq ?yin
        cmp #$FF
        jne ?skip
        lda zdy                 ; above the top: visible rows = h + y
        clc
        adc mf_h,x
        jcc ?skip
        jeq ?skip
        sta bs_h
        lda #0                  ; C=1 (jcc not taken)
        sbc zdy
        sta bf_top              ; rows cut off at the top
        lda #0
        sta zdy
        beq ?x                  ; (always: y 0 + h <= 64 needs no bottom clip)
?yin    sta bf_top              ; A = 0
        lda zdy
        cmp #GAME_H
        jcs ?skip
        lda mf_h,x              ; C=0 (jcs not taken)
        sta bs_h
        adc zdy                 ; bottom: clip at GAME_H (the HUD below)
        cmp #GAME_H+1
        bcc ?x
        lda #GAME_H
        sbc zdy                 ; C=1
        sta bs_h
?x      lda mf_w,x
        sta bs_w
        lda zdxh                ; A = columns cut off at the left (0 here)
        beq ?src
        bmi ?xneg
        cmp #1
        jne ?skip
        lda #320-256            ; x = 256+zdx: room = 64 - zdx (C=1: cmp #1 equal)
        sbc zdx
        jcc ?skip
        jeq ?skip
        cmp bs_w
        bcs ?s0
        sta bs_w
?s0     lda #0                  ; none cut at the left
        beq ?src                ; (always)
?xneg   cmp #$FF
        jne ?skip
        lda zdx                 ; left of the screen: visible = w + x
        clc
        adc bs_w
        jcc ?skip
        jeq ?skip
        sta bs_w
        lda #0                  ; C=1 (jcc not taken)
        sbc zdx                 ; columns cut off at the left
        ldy #0
        sty zdx
        sty zdxh
        ; 2026-11-10 6502-idioms.md "no RAM cell for a value that only waits":
        ; the left cut stays in A (no bf_left); sr_add is the tail (below)
?src    ldy ls_bank             ; the set being built (frame.asm)
        sty VBXE_BANK_SEL
        ldy bf_mir              ; first column: left, mirrored w-1-left
        beq ?c
        eor #$FF
        clc
        adc mf_w,x
?c      ldy bf_top
        bne ?cut                ; rare: rows cut at the top (out of line)
        clc                     ; source = frame + first column, into the BCB
        adc mf_lo,x
        ldy #0
        sta (spl_ptr),y                 ; +0 src addr
        lda mf_mi,x
        adc #0
        iny
        sta (spl_ptr),y                 ; +1
        lda mf_bk,x
?hi     adc #0
        iny
        sta (spl_ptr),y                 ; +2 (a bank + carry < 256: C=0)
        iny
        lda mf_w,x
        sta (spl_ptr),y                 ; +3 src step y = full width
        ldy #5
        lda bf_mir
        ora #1
        sta (spl_ptr),y                 ; +5 src step x: 1, mirrored $FF
        ldx zdy                         ; dst = y_addr[zdy] + zdx + buffer
        lda y_addr_lo,x                 ; C=0 (the bank byte above)
        adc zdx
        iny
        sta (spl_ptr),y                 ; +6 dst addr lo
        iny
        lda y_addr_hi,x
        adc zdxh
        sta (spl_ptr),y                 ; +7
        lda bs_w
        sbc #0                          ; C=0: w-1, leaves C=1
        ldy #12
        sta (spl_ptr),y                 ; +12 width-1
        lda bs_h
        sbc #1                          ; C=1
        ldy #14
        sta (spl_ptr),y                 ; +14 height-1
        lda #BLT_TRANS+$08              ; transparent + NEXT (spl_flush ends it)
        ldy #20
        sta (spl_ptr),y                 ; +20 ctrl
        lda spl_ptr                     ; next slot
        adc #21-1                       ; C=1 from the height sbc: +21
        sta spl_ptr
        bcc ?sr
        inc spl_ptr+1
        ; 2026-11-10 6502-idioms.md "jsr X / rts -> jmp X": this sprite's rect
        ; last (sr_add reads only zdx, zdxh, zdy, bs_w, bs_h)
?sr     jmp sr_add
?skip   rts
?cut    clc                     ; A = first column, Y = rows cut at the top:
        adc mf_lo,x             ; source = frame + column + top*w
        pha                     ; (lo parked; A carries it through the loop)
        lda mf_mi,x
        adc #0
        sta bf_src
        lda mf_bk,x
        adc #0
        sta bf_src+1
        pla
?tl     clc
        adc mf_w,x
        bcc ?tn
        inc bf_src
        bne ?tn
        inc bf_src+1
?tn     dey
        bne ?tl
        sta (spl_ptr),y                 ; +0 src addr (Y = 0)
        lda bf_src
        iny
        sta (spl_ptr),y                 ; +1
        lda bf_src+1
        clc                             ; ?hi adds 0, leaves C=0
        bcc ?hi                         ; (always)
.endp
bf_src  dta 0,0                 ; mid, bank of the top-cut source

; bs_w/bs_h moved to zero page (zeropage.asm)

; (blit_bg + bg_row tables deleted 2026-06-10: dead since the scroll rewrite -
;  empty tiles stay color 0 in the bg canvas and the parallax sky shows through)
