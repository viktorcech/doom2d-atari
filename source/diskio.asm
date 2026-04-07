;==============================================
; DOOM2D - Disk I/O (level loading via SIO)
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

LVL_BUF     = $8000         ; temp buffer for .lvl data
LVL_SECTORS = 9             ; ceil(1104 / 128)
        icl '../data/atr_layout.asm'    ; defines LVL_SEC1

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
?rd_lp  stx ll_cnt
        lda #$31            ; disk device
        sta DDEVIC
        lda #$01            ; drive 1
        sta DUNIT
        lda #$52            ; read sector
        sta DCOMND
        lda #$40            ; receive data
        sta DSTATS
        lda #128            ; sector size
        sta DBYTLO
        lda #0
        sta DBYTHI
        lda #$07            ; timeout
        sta DTIMLO
        jsr SIOV
        bpl ?rd_ok          ; SIO ok
        jmp ?err
?rd_ok

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
?no_aux ldx ll_cnt
        dex
        bne ?rd_lp

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

        ; --- Parse header (at LVL_BUF+1024) ---
        lda LVL_BUF+1024       ; spawn_x lo
        sta pl_start_x
        lda LVL_BUF+1025       ; spawn_x hi
        sta pl_start_x+1
        lda LVL_BUF+1026       ; spawn_y
        sta pl_start_y
        lda LVL_BUF+1027
        sta num_en
        lda LVL_BUF+1028
        sta num_pk
        lda LVL_BUF+1029
        sta num_dc
        lda LVL_BUF+1030
        sta num_switches

        ; --- Parse entity data (at LVL_BUF+1031) ---
        lda #<(LVL_BUF+1031)
        sta zsrc
        lda #>(LVL_BUF+1031)
        sta zsrc+1

        ; --- Enemies (5 bytes each: x_lo, x_hi, y, type, dir) ---
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
        lda zsrc
        clc
        adc #5
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
        jmp ?re_snd

?err    ; SIO failed — zero all counts (empty level)
        lda #0
        sta num_en
        sta num_pk
        sta num_dc
        sta num_switches

?re_snd ; Re-enable sound IRQ
        lda POKMSK
        ora #$01                ; unmask Timer 1 IRQ
        sta POKMSK
        sta IRQEN
        rts

ll_cnt  dta 0
ll_sec  dta a(0)
.endp
