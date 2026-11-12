;==============================================
; DOOM2D - The sky, drawn by the VBXE blitter (FX core 1.27)
; sky.asm
;
; ONE BCB a frame in each list set (frame.asm): the level sky
; (tools/sky2vbxe.py: 84 x 96, game palette, no colour 0) zoomed 4 x 2 to
; the 320 x 192 game window of the back buffer, then its jump container
; (VBXE FX 1.27) on to the set's window list. ANTIC DMA stays off.
; Parallax: source column = cam_x >> 7 (0..3, the 4 spare columns).
;==============================================

VRAM_SKY  = $032000             ; 8064 B, banks $32-$33 (sky_upload)
SKY_W     = 84
SKY_H     = 96
SKY_BCB   = VRAM_XDL+$C0        ; 21 B + its 4 B jump container, bank $7F
SKY_B     = MEMW+[SKY_BCB&$FFF]
        ert SKY_W*SKY_H>$2000
        ert [VRAM_SKY&$FFF]<>0
        ert xdl_len>$C0
        ert SKY_BCB+25>VRAM_BCB
        ert [SKY_BCB>>12]<>BANK_BCB
        ert SKY_W*4<SCR_W+4*3
        ert SKY_H*2<>GAME_H

; SKY_INIT - the BCB template and its jump, once (every field constant but
; the source column, +0, and the back buffer, +8: sky_run writes those)
.proc sky_init
        lda ls_bank             ; this set (frame.asm lists_init)
        sta VBXE_BANK_SEL
        ldx #21
?lp     lda ?t,x
        sta SKY_B,x
        dex
        bpl ?lp
        lda #<[VRAM_BCB&$FFF]   ; the jump: this set's window list
        sta SKY_B+22
        lda ls_mid
        ora #>[VRAM_BCB&$FFF]
        sta SKY_B+23
        lda ls_hi
        sta SKY_B+24
        rts
?t      dta <VRAM_SKY, >VRAM_SKY, ^VRAM_SKY     ; +0 source
        dta SKY_W, 0, 1                         ; +3 source step y, +5 x
        dta 0, 0, 0                             ; +6 destination (sky_frame)
        dta <SCR_W, >SCR_W, 1                   ; +9 destination step y, +11 x
        dta 80-1, 0, SKY_H-1                    ; +12 width-1, +14 height-1
        dta $FF, 0, 0                           ; +15 AND, XOR, collision mask 0
        dta $13, 0                              ; +18 zoom: Y x2, X x4; pattern off
        dta $80+$08                             ; +20 MODE 0, EXTENDED, NEXT
        dta $00                                 ; +21 absolute jump: the window list
.endp

; SKY_RUN - this frame's sky column and back buffer, in the set being built
; (frame.asm: the frame's one START runs it after the pre lists)
.proc sky_run
        lda ls_bank
        sta VBXE_BANK_SEL
        lda cam_x               ; column = cam_x >> 7 (cam_x_hi <= 1)
        asl
        lda cam_x_hi
        rol
        sta SKY_B+0             ; <VRAM_SKY = 0: the column is the low byte
        lda zbuf_hi
        sta SKY_B+8
        rts
.endp
        ert <VRAM_SKY<>0
        ert [MAX_CAM_X>>7]>SKY_W-80
