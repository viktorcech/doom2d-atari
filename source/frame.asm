;==============================================
; DOOM2D - The frame's blitter lists in two sets (VBXE FX 1.27, Wolfette)
; frame.asm
;
; The CPU builds frame N+1's lists into one set while the blitter runs frame
; N's from the other: no list is written while the blitter can reach it, and
; the frame is ONE START, after the flip (main.asm). A set's main bank holds
; the sky BCB (jump -> the window list), the window list (on into the sprite
; list) and the sprite list; its pre bank the canvas clears, the animated
; textures' frame copies and the tile list, 25-byte slots (a BCB and its
; jump container: relative +1, the last of a list absolute to the next).
; Chain: clears -> frame copies -> tiles -> sky -> window -> sprites.
;==============================================

LS_PAGE_A = BANK_BCB            ; set A main bank: $07F000 (with the XDL)
LS_PAGE_B = $10                 ; set B: $010000
PL_PAGE_A = $1E                 ; the pre banks: $01E000, $01F000
PL_PAGE_B = $1F
SLOT      = 25                  ; BCB + jump container
CL_OFF    = $000                ; canvas clears (cv_rect)
CL_MAX    = 16
AB_OFF    = CL_OFF+CL_MAX*SLOT  ; animated textures' frame copies (at_step)
AB_MAX    = AT_MAX
TL_OFF    = AB_OFF+AB_MAX*SLOT  ; the tile list (tl_add)
PL_STOP   = $FE0                ; a BCB that ends a synchronous run
TL_SLOTS  = [PL_STOP-TL_OFF]/SLOT
CL_W      = MEMW+CL_OFF
AB_W      = MEMW+AB_OFF
TL_W      = MEMW+TL_OFF
TL_END    = TL_W+TL_SLOTS*SLOT
SKY_OFF   = SKY_BCB&$FFF
SPRL_OFF  = VRAM_SPRL&$FFF
        ert TL_SLOTS<NSX+NSY
        ert PL_STOP+21>$1000
        ert BANK_SV=PL_PAGE_A   ; the save slot buffer apart from the lists
        ert BANK_SV=PL_PAGE_B
        ert BANK_SV=LS_PAGE_B
        ert [LS_PAGE_A&$0F]<>$0F .or [LS_PAGE_B&$0F]<>0

; zero page (lq_* freed them)
ls_bank   = $AD                 ; BANK_EN + the set's main bank
pl_bank   = $AF                 ; BANK_EN + its pre bank
pl_p      = $B9                 ; 2b: a pre-list slot

lst_i     dta 0                 ; the set being built: 0 A, 1 B
ls_mid    dta 0                 ; its main bank's VRAM bits 15-8 (bits 11-8 0)
ls_hi     dta 0                 ; bits 18-16
pl_mid    dta 0                 ; the pre bank's bits 15-8 (bits 18-16: 1)
bl_bank   dta 0                 ; BANK_EN + the set's blood list bank
bl_mid    dta 0                 ; its bits 15-8 (bits 18-16: 5)
cl_n      dta 0                 ; clears in the list
ab_n      dta 0                 ; frame copies
pl_sync   dta 0                 ; 1: tl_flush runs the pre lists at once (rebuild)
pc_t      dta 0,0,0             ; pl_chain: the target, then the head (after
                                ; frame_chain the built frame's: frame_go)
fo_ps     dta 0,0,0,0           ; fore_restore's fo_p / fo_n of each set
fo_ns     dta 0,0

; LS_SET - X = the set to build (0/1)
.proc ls_set
        stx lst_i
        lda ?lb,x
        sta ls_bank
        lda ?lm,x
        sta ls_mid
        lda ?lh,x
        sta ls_hi
        lda ?pb,x
        sta pl_bank
        lda ?pm,x
        sta pl_mid
        lda ?bb,x
        sta bl_bank
        lda ?bm,x
        sta bl_mid
        lda ?do,x
        sta ds_o
        rts
?do     dta 0,3
?bb     dta BANK_EN+BL_PAGE_A, BANK_EN+BL_PAGE_B   ; the blood lists (blood.asm)
?bm     dta [BL_PAGE_A&$0F]<<4, [BL_PAGE_B&$0F]<<4
?lb     dta BANK_EN+LS_PAGE_A, BANK_EN+LS_PAGE_B
?lm     dta [LS_PAGE_A&$0F]<<4, [LS_PAGE_B&$0F]<<4
?lh     dta LS_PAGE_A>>4, LS_PAGE_B>>4
?pb     dta BANK_EN+PL_PAGE_A, BANK_EN+PL_PAGE_B
?pm     dta [PL_PAGE_A&$0F]<<4, [PL_PAGE_B&$0F]<<4
.endp
        ert [PL_PAGE_A>>4]<>1 .or [PL_PAGE_B>>4]<>1

; LISTS_INIT - every template of both sets, once (main.asm); set A after
.proc lists_init
        lda #BANK_EN+[HUD_ZERO>>12]     ; the 0 the HUD clears copy (VRAM is
        sta VBXE_BANK_SEL               ; not cleared at power-on)
        lda #0
        sta MEMW+[HUD_ZERO&$FFF]
        ldx #1
?s      stx ?x+1
        jsr ls_set
        jsr spl_template        ; sprite slots (vbxe.asm)
        jsr sky_init            ; the sky BCB, its jump to this set's window
        jsr cbw_template        ; window list slots 1-3
        jsr pl_template         ; the pre lists
        jsr bl_template         ; the blood list (blood.asm)
?x      ldx #0                  ; (patched)
        dex
        bpl ?s
        jmp pl_reset            ; set A's lists empty
.endp

; PL_TEMPLATE - the pre bank's slots: clears, frame copies, tiles, stop
.proc pl_template
        lda pl_bank
        sta VBXE_BANK_SEL
        ldx #2                  ; the three lists: clears, frame copies, tiles
?l      lda ?dl,x
        sta pl_p
        lda ?dh,x
        sta pl_p+1
        lda ?sl,x
        sta ?t+1
        lda ?sh,x
        sta ?t+2
        lda ?sn,x
        sta ?n+1
        stx ?x+1
?n      ldx #0                  ; (patched: slots)
?s      ldy #SLOT-1
?t      lda $FFFF,y             ; (patched: the template)
        sta (pl_p),y
        dey
        bpl ?t
        lda pl_p
        clc
        adc #SLOT
        sta pl_p
        bcc ?nx
        inc pl_p+1
?nx     dex
        bne ?s
?x      ldx #0                  ; (patched)
        dex
        bpl ?l
        ldy #20                 ; the stop: a 1-byte mode 1 copy of a 0, the end
?st     lda ?stop,y
        sta MEMW+PL_STOP,y
        dey
        bpl ?st
        rts
?dl     dta <CL_W, <AB_W, <TL_W
?dh     dta >CL_W, >AB_W, >TL_W
?sl     dta <?cl, <?ab, <?tl
?sh     dta >?cl, >?ab, >?tl
?sn     dta CL_MAX, AB_MAX, TL_SLOTS
; constant fields (variable ones 0); every ctrl EXTENDED + NEXT, relative +1
?cl     dta 0,0,0, <BG_STRIDE,>BG_STRIDE,1, 0,0,0, <BG_STRIDE,>BG_STRIDE,1
        dta 0,0,0, 0, 0,0,0,0, $80+$08          ; AND 0: fill with 0, MODE 0
        dta $01,$01,$00,$00
?ab     dta 0,0,0, 64,0,1, 0,0,0, 64,0,1, 63,0,0, $FF, 0,0,0,0, $80+$08
        dta $01,$01,$00,$00
?tl     dta 0,0,VRAM_TILESET>>16, TW,0,1, 0,0,0, <BG_STRIDE,>BG_STRIDE,1
        dta TW-1,0,TH-1, $FF, 0,0,0,0, $80+BLT_TRANS+$08
        dta $01,$01,$00,$00
?stop   dta <HUD_ZERO,>HUD_ZERO,^HUD_ZERO, 0,0,0, <HUD_ZERO,>HUD_ZERO,^HUD_ZERO
        dta 0,0,0, 0,0,0, $FF, 0,0,0,0, BLT_TRANS
.endp
        ert TL_SLOTS+1>255      ; tl_left

; PL_RESET - empty pre lists (the frame start, after a synchronous run)
.proc pl_reset
        ldx ds_o                ; the slots of this set pl_chain made jump
        jsr ?one                ; absolute: relative +1 again (the set's
        inx                     ; lists ran: the blitter is past them)
        jsr ?one
        inx
        jsr ?one
        lda #0
        sta cl_n
        sta ab_n
        lda #TL_SLOTS+1
        sta tl_left
        lda #<TL_W
        sta tl_ptr
        lda #>TL_W
        sta tl_ptr+1
?r      rts
?one    lda ds_hi,x             ; X = the entry (kept)
        beq ?r
        sta pl_p+1
        lda ds_lo,x
        sta pl_p
        lda #0
        sta ds_hi,x
        lda pl_bank
        sta VBXE_BANK_SEL
        ert *<>pl_rel           ; (falls into pl_rel)
.endp
; PL_REL - pl_p's slot jumps relative +1 again (after an absolute jump)
.proc pl_rel
        lda #$01
        ldy #21
        sta (pl_p),y
        iny
        sta (pl_p),y
        lda #0
        iny
        sta (pl_p),y
        rts
.endp

; PL_SLOT - pl_p = slot A of the list at X:Y (MEMW address), the pre bank
; selected; returns Y = 0
.proc pl_slot
        stx pl_p
        sty pl_p+1
        tax
        beq ?r
?m      lda pl_p
        clc
        adc #SLOT
        sta pl_p
        bcc ?n
        inc pl_p+1
?n      dex
        bne ?m
?r      lda pl_bank
        sta VBXE_BANK_SEL
        ldy #0
        rts
.endp

; CV_RECT - zero-fill one rectangle of the bg canvas (both strides
; BG_STRIDE): a slot of the clear list. cv_s = 16-bit offset from $061000
; (src = dst), cv_w1 = width-1 (16-bit), cv_h1 = height-1. Keeps nothing.
.proc cv_rect
        lda cl_n
        cmp #CL_MAX
        bcc ?ok                 ; @taken: true
        jsr pl_run              ; the list is full: run the pre lists now
        lda #0
?ok     inc cl_n
        ldx #<CL_W
        ldy #>CL_W
        jsr pl_slot             ; Y = 0
        lda cv_s                ; src = dst = $061000 + cv_s
        sta (pl_p),y            ; +0
        ldy #6
        sta (pl_p),y            ; +6
        lda cv_s+1
        clc
        adc #$10
        ldy #1
        sta (pl_p),y            ; +1
        ldy #7
        sta (pl_p),y            ; +7
        lda #$06
        adc #0
        ldy #2
        sta (pl_p),y            ; +2
        ldy #8
        sta (pl_p),y            ; +8
        lda cv_w1
        ldy #12
        sta (pl_p),y            ; +12
        lda cv_w1+1
        iny
        sta (pl_p),y            ; +13
        lda cv_h1
        iny
        sta (pl_p),y            ; +14
        rts                     ; (the jump is relative: pl_reset)
.endp
cv_s    dta 0,0
cv_w1   dta 0,0
cv_h1   dta 0

; AB_ADD - a frame copy slot: pl_p = it (pre bank selected, Y = 0); the
; caller writes src, dst, height (anim.asm at_step)
.proc ab_add
        lda ab_n                ; never full: at_step adds one per animated
        inc ab_n                ; texture a frame, AB_MAX = AT_MAX
        ldx #<AB_W
        ldy #>AB_W
        bne pl_slot             ; (always: a MEMAC page) Y = 0 (the jump is relative: pl_reset)
.endp

; TL_ADD - tile X into ring slot (r_col, r_row): src, dst and the control
; byte of the next slot of the tile list. Clobbers A, X and Y.
.proc tl_add
        dec tl_left             ; free slots + 1 (pl_reset)
        beq ?full               ; @taken: false
?ok     lda pl_bank
        sta VBXE_BANK_SEL
        ldy #0
        lda tile_src_lo,x
        sta (tl_ptr),y
        iny
        lda tile_src_mi,x
        sta (tl_ptr),y
        ldx r_col               ; dst = $061000 + rowtop[r_row] + colx[r_col]
        ldy r_row
        lda bgbuf_rowtop_lo,y
        clc
        adc bgcolx_lo,x
        ldy #6
        sta (tl_ptr),y
        ldy r_row               ; (ldy/sta keep C)
        lda bgbuf_rowtop_hi,y
        adc bgcolx_hi,x
        adc #$10                ; + $1000 (bg buffer base offset in bank $06)
        ldy #7
        sta (tl_ptr),y
        lda #$06
        adc #0                  ; may carry to $07 for low rows; 6+C <= 7: C=0
        iny
        sta (tl_ptr),y
md      lda #$80+BLT_TRANS+$08  ; EXTENDED + NEXT; patched: anim.asm (opaque)
        ldy #20                 ; (the jump +21..+23 stays relative +1:
        sta (tl_ptr),y          ; pl_reset undoes pl_chain's absolute one)
        lda tl_ptr
        clc
        adc #SLOT
        sta tl_ptr
        bcc ?r
        inc tl_ptr+1
?r      rts
?full   txa                     ; the list is full: run the pre lists now
        pha
        jsr pl_run              ; (tl_left = TL_SLOTS+1)
        pla
        tax
        dec tl_left
        bne ?ok                 ; (always: TL_SLOTS + 1 - 1)
.endp

; TL_FLUSH - the end of a group of tiles: a rebuild (pl_sync) runs the pre
; lists at once; a frame's groups wait for the frame's START
.proc tl_flush
        lda pl_sync
        bne pl_run
        rts
.endp

; PL_RUN - the pre lists at once, to the stop BCB, and wait (nothing may be
; written into them while they run); empty lists after
.proc pl_run
        jsr wait_blit           ; nothing else runs (frame N, a clear)
        lda #<PL_STOP
        sta pc_t
        lda pl_mid
        ora #>PL_STOP
        sta pc_t+1
        lda #1
        sta pc_t+2
        jsr pl_chain
        jsr pc_start
        jsr wait_blit
        jmp pl_reset
.endp

; PC_START - START the list at pc_t (the blitter is idle)
.proc pc_start
        lda pc_t
        sta VBXE_BL_ADR0
        lda pc_t+1
        sta VBXE_BL_ADR1
        lda pc_t+2
        sta VBXE_BL_ADR2
        lda #1
        sta VBXE_BLITTER
        rts
.endp

; PL_CHAIN - the pre lists' last slots jump to pc_t, each list to the next
; one present (tiles, frame copies, clears: back to front); pc_t = the head
.proc pl_chain
        lda tl_left             ; tiles: the last slot = tl_ptr - SLOT
        cmp #TL_SLOTS+1
        beq ?nt                 ; (none)
        lda tl_ptr
        sec
        sbc #SLOT
        sta pl_p
        lda tl_ptr+1
        sbc #0
        sta pl_p+1
        lda pl_bank
        sta VBXE_BANK_SEL
        ldy #0
        jsr ?jh
?nt     lda ab_n
        beq ?na
        sec
        sbc #1
        ldx #<AB_W
        ldy #>AB_W
        jsr pl_slot
        iny                     ; Y = 1 (pl_slot: 0)
        jsr ?jh
?na     lda cl_n
        beq ?r
        sec
        sbc #1
        ldx #<CL_W
        ldy #>CL_W
        jsr pl_slot
        ldy #2
?jh     tya                     ; Y = the list: pl_reset makes pl_p's slot
        clc                     ; relative again
        adc ds_o
        tax
        lda pl_p
        sta ds_lo,x
        lda pl_p+1
        sta ds_hi,x
        tya
        tax                     ; X = the list
        lda #0                  ; pl_p's slot: an absolute jump to pc_t
        ldy #21
        sta (pl_p),y
        lda pc_t
        iny
        sta (pl_p),y
        lda pc_t+1
        iny
        sta (pl_p),y
        lda pc_t+2
        iny
        sta (pl_p),y
        lda ?ol,x               ; pc_t = the list's head in the pre bank
        sta pc_t
        lda ?oh,x
        ora pl_mid
        sta pc_t+1
        lda #1
        sta pc_t+2
?r      rts
?ol     dta <TL_OFF, <AB_OFF, <CL_OFF
?oh     dta >TL_OFF, >AB_OFF, >CL_OFF
.endp

; FRAME_CHAIN - the built frame's head into pc_t: the sprite list ended,
; the pre lists on to the sky (main.asm, before the vsync wait)
.proc frame_chain
        jsr spl_close
        lda #<SKY_OFF
        sta pc_t
        lda ls_mid
        ora #>SKY_OFF
        sta pc_t+1
        lda ls_hi
        sta pc_t+2
        jmp pl_chain
.endp

; FRAME_GO - START the built frame (frame N is done, the flip is set), then
; build the next one in the other set
.proc frame_go
        jsr pc_start            ; pc_t: frame_chain's head (nothing between)
        lda lst_i               ; this set's foreground slots (fore_restore
        tax                     ; puts them back when it is built again)
        asl
        tay
        lda fo_p
        sta fo_ps,y
        lda fo_p+1
        sta fo_ps+1,y
        lda fo_n
        sta fo_ns,x
        txa
        eor #1
        tax
        jsr ls_set
        lda lst_i               ; the other set's, from two frames ago
        tax
        asl
        tay
        lda fo_ps,y
        sta fo_p
        lda fo_ps+1,y
        sta fo_p+1
        lda fo_ns,x
        sta fo_n
        jsr ls_stamp            ; its slots' bank (once: the sets go in step)
        jsr spl_reset
        jmp pl_reset
.endp

; LS_STAMP - this set's sprite and blood slots carry the back buffer's bank
; in +8 (sets and buffers alternate in step: it stays the set's), so their
; writers skip it (vbxe-blitter: stamp a per-frame value once, not per blit);
; here only when it changed (a new level, a menu's own flips). Keeps nothing.
.proc ls_stamp
        ldx lst_i
        lda zbuf_hi
        cmp ls_zb,x
        bne ?go
        rts
?go     sta ls_zb,x
        sta ?v+1
        lda ls_bank             ; the sprite slots: 21 apart
        sta VBXE_BANK_SEL
        lda #21
        sta ?st+1
        lda #<[SPRL_W+8]
        ldx #>[SPRL_W+8]
        ldy #SPRL_MAX
        jsr ?run
        lda bl_bank             ; the blood slots: BL_SL apart
        sta VBXE_BANK_SEL
        lda #BL_SL
        sta ?st+1
        lda #<[BLD_W+8]
        ldx #>[BLD_W+8]
        ldy #BL_N
?run    sta pl_p                ; A:X the first +8, Y slots, ?st+1 the stride
        stx pl_p+1
        tya
        tax
?v      lda #0                  ; (patched: the bank)
        ldy #0
?l      sta (pl_p),y
        pha
        lda pl_p
        clc
?st     adc #0                  ; (patched: the stride)
        sta pl_p
        bcc ?c
        inc pl_p+1
?c      pla
        dex
        bne ?l
        rts
.endp
ls_zb   dta $FF,$FF             ; the bank each set's slots carry ($FF: none yet)

; FRAME_NOW - build and run the frame at once (init_render: no frame runs)
.proc frame_now
        jsr spl_reset           ; no sprites: the window list's chain ends
        jsr frame_chain
        jsr wait_blit
        jsr pc_start
        jsr wait_blit
        jsr spl_reset
        jmp pl_reset
.endp
