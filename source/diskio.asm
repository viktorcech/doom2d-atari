;==============================================
; DOOM2D - Disk I/O (level + sky loading via SIO)
; diskio.asm
; Reads .lvl data from raw ATR sectors (no DOS needed)
;==============================================

; SIO Device Control Block
SIOV        = $E459
DDEVIC      = $0300
DUNIT       = $0301
DCOMND      = $0302
DSTATS      = $0303
DBUFLO      = $0304
DBUFHI      = $0305
DTIMLO      = $0306
DBYTLO      = $0308
DBYTHI      = $0309
DAUX1       = $030A         ; sector lo
DAUX2       = $030B         ; sector hi

LVL_BUF     = $8000         ; temp buffer for .lvl / .sky data
LVL_SECTORS = 10            ; ceil(1161 / 128) — level data + 9-byte header
        icl '../data/atr_layout_const.asm'  ; defines LVL_SEC1, SAVE_SEC1, NUM_SKIES

;==============================================
; READ SECTORS FROM DISK (generic SIO reader)
; Input: DAUX1/DAUX2 = start sector
;        DBUFLO/DBUFHI = dest buffer
;        X = number of sectors to read
; Clobbers: A, X, Y
; Returns: C=0 ok, C=1 error
;==============================================
.proc read_sectors
        stx rs_cnt
?rd_lp  lda #$31
        sta DDEVIC
        lda #$01
        sta DUNIT
        lda #$52            ; read sector
        sta DCOMND
        lda #$40            ; receive data
        sta DSTATS
        lda #128
        sta DBYTLO
        lda #0
        sta DBYTHI
        lda #$07
        sta DTIMLO
        jsr SIOV
        bmi ?err

        ; Advance buffer pointer by 128
        lda DBUFLO
        clc
        adc #128
        sta DBUFLO
        bcc ?no_inc
        inc DBUFHI
?no_inc ; Next sector
        inc DAUX1
        bne ?no_aux
        inc DAUX2
?no_aux dec rs_cnt
        bne ?rd_lp
        clc
        rts
?err    sec
        rts
rs_cnt  dta 0
.endp

;==============================================
; LOAD LEVEL FROM DISK (SIO direct sector read)
; Reads LVL_SECTORS sectors from ATR to LVL_BUF,
; uploads tiles to VRAM, parses entity data.
; Sector = LVL_SEC1 + current_level * LVL_SECTORS
;==============================================
.proc load_level
        ; --- Calculate starting sector for current_level ---
        lda #<LVL_SEC1
        sta ll_sec
        lda #>LVL_SEC1
        sta ll_sec+1
        ldx current_level
        beq ?sec_ok
?add_lp lda ll_sec
        clc
        adc #LVL_SECTORS
        sta ll_sec
        bcc ?no_hi
        inc ll_sec+1
?no_hi  dex
        bne ?add_lp
?sec_ok
        ; --- Disable sound IRQ before SIO (both use POKEY timers) ---
        lda #0
        sta snd_active
        sta AUDC4               ; silence channel
        lda POKMSK
        and #$FE                ; mask Timer 1 IRQ
        sta POKMSK
        sta IRQEN

        ; --- Read sectors via SIO ---
        lda #<LVL_BUF
        sta DBUFLO
        lda #>LVL_BUF
        sta DBUFHI
        lda ll_sec
        sta DAUX1
        lda ll_sec+1
        sta DAUX2
        ldx #LVL_SECTORS
        jsr read_sectors
        bcc ?rd_ok
        jmp ?err
?rd_ok

        ; --- Upload tiles (1024B) to VRAM bank $1E ---
        lda #$90+MC_CPU
        sta VBXE_MEMAC_CTRL
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        lda #<LVL_BUF
        sta zsrc
        lda #>LVL_BUF
        sta zsrc+1
        ldx #4              ; 4 pages = 1024 bytes
        lda #>MEMW
        sta ?tw+2
?tp     ldy #0
?tl     lda (zsrc),y
?tw     sta MEMW,y
        iny
        bne ?tl
        inc zsrc+1
        inc ?tw+2
        dex
        bne ?tp
        lda #0
        sta VBXE_BANK_SEL

        ; --- Parse header (at LVL_BUF+1024, 9 bytes) ---
        lda LVL_BUF+1024       ; +0 spawn_x lo
        sta pl_start_x
        lda LVL_BUF+1025       ; +1 spawn_x hi
        sta pl_start_x+1
        lda LVL_BUF+1026       ; +2 spawn_y
        sta pl_start_y
        lda LVL_BUF+1027       ; +3 num_enemies
        sta num_en
        lda LVL_BUF+1028       ; +4 num_pickups
        sta num_pk
        lda LVL_BUF+1029       ; +5 num_decor
        sta num_dc
        lda LVL_BUF+1030       ; +6 num_switches
        sta num_switches
        lda LVL_BUF+1031       ; +7 num_tile_bg
        sta tile_bg_cnt
        lda LVL_BUF+1032       ; +8 sky_index
        sta ll_sky_idx

        ; --- Parse entity data (at LVL_BUF+1033) ---
        lda #<(LVL_BUF+1033)
        sta zsrc
        lda #>(LVL_BUF+1033)
        sta zsrc+1

        ; --- Enemies (6 bytes each: x_lo, x_hi, y, type, dir, sleep) ---
        ldx #0
?en_lp  cpx num_en
        bcs ?en_done
        ldy #0
        lda (zsrc),y            ; x_lo
        sta zt
        iny
        lda (zsrc),y            ; x_hi
        sta zt2
        txa
        asl
        tay
        lda zt
        sta enemy_spawn_x,y
        lda zt2
        sta enemy_spawn_x+1,y
        ldy #2
        lda (zsrc),y            ; y
        sta enemy_spawn_y,x
        iny
        lda (zsrc),y            ; type
        sta enemy_spawn_type,x
        iny
        lda (zsrc),y            ; dir
        sta enemy_spawn_dir,x
        iny
        lda (zsrc),y            ; sleep
        sta enemy_spawn_sleep,x
        lda zsrc
        clc
        adc #6
        sta zsrc
        bcc ?en_nc
        inc zsrc+1
?en_nc  inx
        jmp ?en_lp
?en_done

        ; --- Pickups (4 bytes each: x_lo, x_hi, y, type) ---
        ldx #0
?pk_lp  cpx num_pk
        bcs ?pk_done
        ldy #0
        lda (zsrc),y
        sta pickup_spawn_x,x
        iny
        lda (zsrc),y
        sta pickup_spawn_xhi,x
        iny
        lda (zsrc),y
        sta pickup_spawn_y,x
        iny
        lda (zsrc),y
        sta pickup_spawn_type,x
        lda zsrc
        clc
        adc #4
        sta zsrc
        bcc ?pk_nc
        inc zsrc+1
?pk_nc  inx
        jmp ?pk_lp
?pk_done

        ; --- Decorations (4 bytes each: x_lo, x_hi, y, type) ---
        ldx #0
?dc_lp  cpx num_dc
        bcs ?dc_done
        ldy #0
        lda (zsrc),y
        sta decor_spawn_x,x
        iny
        lda (zsrc),y
        sta decor_spawn_xhi,x
        iny
        lda (zsrc),y
        sta decor_spawn_y,x
        iny
        lda (zsrc),y
        sta decor_spawn_type,x
        lda zsrc
        clc
        adc #4
        sta zsrc
        bcc ?dc_nc
        inc zsrc+1
?dc_nc  inx
        jmp ?dc_lp
?dc_done

        ; --- Switches (5 bytes each: col, row, tgt_col, tgt_row, action) ---
        ldx #0
?sw_lp  cpx num_switches
        bcs ?sw_done
        ldy #0
        lda (zsrc),y
        sta sw_col,x
        iny
        lda (zsrc),y
        sta sw_row,x
        iny
        lda (zsrc),y
        sta sw_tgt_col,x
        iny
        lda (zsrc),y
        sta sw_tgt_row,x
        iny
        lda (zsrc),y
        sta sw_action,x
        lda zsrc
        clc
        adc #5
        sta zsrc
        bcc ?sw_nc
        inc zsrc+1
?sw_nc  inx
        jmp ?sw_lp
?sw_done
        ; --- Tile BG overrides (3 bytes each: col, row, tile_id) ---
        ldx #0
?tb_lp  cpx tile_bg_cnt
        bcs ?tb_done
        ldy #0
        lda (zsrc),y
        sta tile_bg_col,x
        iny
        lda (zsrc),y
        sta tile_bg_row,x
        iny
        lda (zsrc),y
        sta tile_bg_tid,x
        lda zsrc
        clc
        adc #3
        sta zsrc
        bcc ?tb_nc
        inc zsrc+1
?tb_nc  inx
        jmp ?tb_lp
?tb_done

        ; --- Sky is now static (uploaded at boot) ---
?sky_ok
        jmp ?re_snd

?err    ; SIO failed — zero all counts (empty level)
        lda #0
        sta num_en
        sta num_pk
        sta num_dc
        sta num_switches
        sta tile_bg_cnt

?re_snd ; Re-enable sound IRQ
        lda POKMSK
        ora #$01                ; unmask Timer 1 IRQ
        sta POKMSK
        sta IRQEN
        rts

ll_cnt  dta 0
ll_sec  dta a(0)
ll_sky_idx dta 0
.endp

;==============================================
; LOAD SKY FROM DISK + RLE DECOMPRESS TO VRAM
;
; Strategy: decompress RLE row-by-row into a 320-byte
; line buffer in RAM, then write each row to VRAM twice
; (320x96 -> 320x192).
;
; RLE: $00-$7F = literal run (N+1 raw bytes follow)
;      $80-$FF = repeat run (byte repeated N-125 times, 3..130)
;
; VRAM dest: $034000 (BANK_BG), 320 bytes/row, 192 rows
;==============================================

SKY_LINE = LVL_BUF+$6000       ; 320-byte line buffer at $E000

.proc load_sky
        ; --- Look up sky sector from table ---
        ldx current_sky
        lda sky_sec_lo,x
        sta DAUX1
        lda sky_sec_hi,x
        sta DAUX2
        lda sky_sec_cnt,x
        cmp #161                ; cap at 160 sectors ($5000 = 20KB)
        bcc ?cnt_ok
        lda #160
?cnt_ok tax                     ; X = sectors to read

        ; --- Read compressed sky to LVL_BUF ---
        lda #<LVL_BUF
        sta DBUFLO
        lda #>LVL_BUF
        sta DBUFHI
        jsr read_sectors
        bcc ?sky_rd_ok
        rts                     ; SIO error, bail
?sky_rd_ok

        ; --- DEBUG: just disable/enable ROM, no decompression ---
        sei
        lda #0
        sta $D40E
        lda $D301
        and #$FC
        sta $D301

        ; ... nothing ...

        lda $D301
        ora #$03
        sta $D301
        lda #$40
        sta $D40E
        cli
        rts

        ; --- Original code below (unreachable for now) ---
        lda #$90+MC_CPU
        sta VBXE_MEMAC_CTRL

        lda #<(LVL_BUF+2)
        sta zsrc
        lda #>(LVL_BUF+2)
        sta zsrc+1

        lda #BANK_EN+BANK_BG
        sta sk_bank
        lda #0
        sta sk_voff
        sta sk_voff+1

        lda #96
        sta sk_rows

?row_lp ; === Decompress one row (320 bytes) to SKY_LINE buffer ===
        lda #0
        sta sk_bufpos
        sta sk_bufpos+1
        lda #<320
        sta sk_rowrem
        lda #>320
        sta sk_rowrem+1

?decomp lda sk_rowrem
        ora sk_rowrem+1
        beq ?row_done

        ldy #0
        lda (zsrc),y
        jsr ?adv_src
        bmi ?repeat

        ; --- Literal run: N+1 raw bytes ---
        tax
        inx
?lit_lp ldy #0
        lda (zsrc),y
        jsr ?adv_src
        jsr ?buf_write
        dex
        bne ?lit_lp
        jmp ?decomp

        ; --- Repeat run ---
?repeat and #$7F
        clc
        adc #3
        tax
        ldy #0
        lda (zsrc),y
        jsr ?adv_src
        sta sk_val
?rep_lp lda sk_val
        jsr ?buf_write
        dex
        bne ?rep_lp
        jmp ?decomp

?row_done
        ; === Write SKY_LINE buffer to VRAM twice (row doubling) ===
        jsr ?flush_line
        jsr ?flush_line

        dec sk_rows
        bne ?row_lp

        ; --- Done, restore system ---
        lda #0
        sta VBXE_BANK_SEL
        lda $D301
        ora #$03
        sta $D301
        lda #$40
        sta $D40E
        rts

; --- Advance RLE source pointer ---
?adv_src
        inc zsrc
        bne ?as1
        inc zsrc+1
?as1    rts

; --- Write byte A to line buffer at sk_bufpos, advance ---
?buf_write
        pha
        lda sk_bufpos+1
        clc
        adc #>SKY_LINE
        sta ?bw+2
        pla
        ldy sk_bufpos
?bw     sta SKY_LINE,y

        ; Advance buffer position
        inc sk_bufpos
        bne ?bw1
        inc sk_bufpos+1
?bw1
        ; Decrement row remaining
        lda sk_rowrem
        bne ?bw2
        dec sk_rowrem+1
?bw2    dec sk_rowrem
        rts

; --- Write 320 bytes from SKY_LINE to VRAM at current position ---
?flush_line
        lda #0
        sta sk_flpos            ; source offset in SKY_LINE (0..319)
        sta sk_flpos+1
        lda #<320
        sta sk_flcnt
        lda #>320
        sta sk_flcnt+1

?fl_lp  ; Set VRAM window
        lda sk_bank
        sta VBXE_BANK_SEL
        lda sk_voff+1
        and #$0F
        ora #>MEMW
        sta ?fw+2

        ; Read from line buffer
        lda sk_flpos+1
        clc
        adc #>SKY_LINE
        sta ?fr+2
        ldy sk_flpos
?fr     lda SKY_LINE,y

        ; Write to VRAM
        ldy sk_voff
?fw     sta MEMW,y

        ; Advance VRAM offset
        inc sk_voff
        bne ?fv1
        inc sk_voff+1
        lda sk_voff+1
        and #$0F
        bne ?fv1
        ; Bank crossing
        lda #0
        sta sk_voff
        sta sk_voff+1
        inc sk_bank
?fv1
        ; Advance source
        inc sk_flpos
        bne ?fp1
        inc sk_flpos+1
?fp1
        ; Decrement count
        lda sk_flcnt
        bne ?fc1
        dec sk_flcnt+1
?fc1    dec sk_flcnt
        lda sk_flcnt
        ora sk_flcnt+1
        bne ?fl_lp
        rts

; --- Local variables ---
sk_bank       dta 0
sk_voff       dta a(0)
sk_rows       dta 0
sk_rowrem     dta a(0)
sk_val        dta 0
sk_bufpos     dta a(0)          ; position in SKY_LINE buffer
sk_flpos      dta a(0)          ; flush: source position
sk_flcnt      dta a(0)          ; flush: bytes remaining
.endp
