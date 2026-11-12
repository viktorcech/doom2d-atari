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

LVL_BUF     = $8400         ; temp buffer for .lvl / .sky data
                            ; (was $8000, but main code in init_render
                            ;  spilled to $8000-$801C — SIO read clobbered it
                            ;  and crashed on next init_render call)
; .lvl = LVL_HDR_SECTORS of header + entities (into LVL_BUF), then the map's
; VRAM image (MAP_BYTES, bank by bank straight into the MEMAC window).
; Keep both in step with tools/map2bin.py and build_doom2d.py.
LVL_HDR_SECTORS = 8
TILE_ATTR_SECTORS = [2*256]/128     ; tile_solid, tile_oneway
; then the tiles in use (header +6, +7), FORE_SECTORS of foreground rects,
; TRIG_RAM_SECTORS of triggers and their panel cells (header +10); each
; level has its own size (build_doom2d.py: lvl_sec_lo/hi)
FORE_SECTORS = 6                    ; foreground rects (tools/d2df2map.py fore_rects)
TRIG_RAM_SECTORS = 13               ; triggers (tools/d2df2map.py trigger_block)
        ert MAP_BYTES&127
        icl 'gen/atr_layout_const.asm'  ; defines SAVE_SEC1, LVL_COUNT

;==============================================
; READ / WRITE SECTORS (generic SIO transfer, LVL_BUF up)
; Input: DAUX1/DAUX2 = start sector
;        X = number of sectors
; .win entries: DBUF set by the caller (the map goes through MEMW).
; Every game SIO call goes through here and sets DBUF first, so the
; DBUF values left behind are never read; DAUX ends past the last sector.
; Clobbers: A, X, Y
; Returns: C=0 ok, C=1 error
;==============================================
.proc read_sectors
        jsr dbuf_lvl
win     lda #$52            ; read sector
        ldy #$40            ; receive data
go      sta ?cmd+1
        sty ?st+1
        stx rs_cnt
?rd_lp  lda #$31
        sta DDEVIC
        lda #$01
        sta DUNIT
?cmd    lda #$52            ; command (patched)
        sta DCOMND
?st     lda #$40            ; direction (patched)
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

.proc write_sectors
        jsr dbuf_lvl
win     lda #$50            ; PUT (write without verify)
        ldy #$80            ; send data
        bne read_sectors.go ; Z=0: Y = $80
.endp

; DBUF = LVL_BUF (keeps X)
.proc dbuf_lvl
        lda #<LVL_BUF
        sta DBUFLO
        lda #>LVL_BUF
        sta DBUFHI
        rts
.endp

;==============================================
; MAP_SIO / TILESET_SIO / VRAM_SIO - a VRAM image <-> disk, bank by bank
; through MEMW (32 sectors a 4K bank, the last bank partial). DAUX = first
; sector, C=0 read, C=1 write; vram_sio takes vs_bank (first BANK_SEL value)
; and vs_left (sectors, 1..255). Returns C=1 on an SIO error; bank 0 after.
;==============================================
.proc map_sio
        lda #BANK_EN+BANK_MAP       ; (lda/sta keep C)
        sta vram_sio.vs_bank
        lda #MAP_BYTES/128
        bne vram_sio.go             ; Z=0
.endp
.proc vram_sio
go      sta vs_left
        lda #$90+MC_CPU             ; MEMAC-A: 4KB at $9000, CPU access
        sta VBXE_MEMAC_CTRL
        lda #<read_sectors.win
        ldx #>read_sectors.win
        bcc ?dir
        lda #<write_sectors.win
        ldx #>write_sectors.win
?dir    sta ?io+1
        stx ?io+2
?bank   lda vs_bank
        sta VBXE_BANK_SEL
        lda #<MEMW
        sta DBUFLO
        lda #>MEMW
        sta DBUFHI
        lda vs_left
        ldx #32
        sec
        sbc #32
        bcs ?n                      ; a bank or more left: a full one
        ldx vs_left                 ; the rest: all of it
        lda #0
?n      sta vs_left                 ; vs_left - X
?io     jsr read_sectors.win        ; (patched: read or write)
        bcs ?end
        inc vs_bank
        lda vs_left
        bne ?bank
        clc                         ; all banks done: success
?end    lda #0                      ; (lda/sta keep C)
        sta VBXE_BANK_SEL
        rts
vs_bank dta 0
vs_left dta 0
.endp
        ert MAP_BYTES/128>255

; TILESET_SIO - read the level's tiles in use: ids 0.. (walls, ts_walls
; sectors, >= 8: the barrels' 15 is in) and 128.. (background, ts_bg
; sectors, may be 0). Entry C=0 (read; its only caller, load_map_tiles,
; proves it). C=1 on an SIO error.
.proc tileset_sio
        lda #BANK_EN+[VRAM_TILESET>>12]
        sta vram_sio.vs_bank
        lda ts_walls
        jsr vram_sio.go
        bcs ?r
        lda ts_bg
        beq ?r                      ; (C=0)
        ldx #BANK_EN+[[VRAM_TILESET+128*TW*TH]>>12]
        stx vram_sio.vs_bank
        bcc vram_sio.go             ; (always) C=0: the bcs above not taken
?r      rts
.endp
        ert [VRAM_TILESET+128*TW*TH]&$FFF

;==============================================
; SIO_QUIET_SCR - display off, then SIO_QUIET: sound off, Timer 1 IRQ
; masked (SIO and the sound IRQ both use POKEY timers). It stays masked
; after the SIO (the OS SIO ends with AUDC1-4 = 0): only snd_play unmasks
; it, with a new sample's pointer and length.
; SIO_END_SCR - XDL back on; keeps A (exit N/Z from A).
;==============================================
.proc sio_quiet_scr
        lda #0
        sta SDMCTL
        sta VBXE_VCTL
        jmp snd_stop
.endp
sio_quiet = snd_stop            ; every voice idle and silent, timer 1 off
.proc sio_end_scr
        pha
        lda #VC_XDL_ON+VC_NO_TRANS
        sta VBXE_VCTL
        pla
        rts
.endp

;==============================================
; LOAD LEVEL FROM DISK (SIO direct sector read)
; Reads the header + entity sectors to LVL_BUF, the map straight into VRAM
; (map_sio), then parses the entity data.
; Sector = lvl_sec_hi:lvl_sec_lo[current_level] (build_doom2d.py)
;==============================================
.proc load_level
        ; --- Disable sound IRQ before SIO (both use POKEY timers) ---
        jsr sio_quiet

        ; --- Starting sector of current_level (build_doom2d.py: the levels
        ; have their own sizes) ---
        ldx current_level
        lda lvl_sec_lo,x
        sta DAUX1
        lda lvl_sec_hi,x
        sta DAUX2

        ; --- Read sectors via SIO: header + entities, then the map ---
        ldx #LVL_HDR_SECTORS
        jsr read_sectors
        bcc ?rd_ok              ; (the map and tiles follow the entity parse)
        lda #0                  ; SIO failed — zero all counts (empty level)
        sta num_en
        sta num_pk
        sta num_dc
        sta n_tr
        rts

; zsrc += A, X++; exit Z=0 (callers have X < count <= 255: X+1 <> 0)
?adv    clc
        adc zsrc
        sta zsrc
        bcc ?an
        inc zsrc+1
?an     inx
        rts

?rd_ok
        ; --- Parse header (at LVL_BUF, 12 bytes) ---
        lda LVL_BUF+0          ; +0 spawn_x lo
        sta pl_start_x
        lda LVL_BUF+1          ; +1 spawn_x hi
        sta pl_start_x+1
        lda LVL_BUF+2          ; +2 spawn_y lo
        sta pl_start_y
        lda LVL_BUF+3          ; +3 num_enemies
        sta num_en
        lda LVL_BUF+4          ; +4 num_pickups
        sta num_pk
        lda LVL_BUF+5          ; +5 num_decor
        sta num_dc
        lda LVL_BUF+6          ; +6, +7 tileset sectors: walls, background
        sta ts_walls
        lda LVL_BUF+7
        sta ts_bg
                               ; +8 sky_index: unused (static sky)
        lda LVL_BUF+9          ; +9 spawn_y hi (16-bit spawn)
        sta pl_start_y_hi
        lda LVL_BUF+10         ; +10 trigger panel cell sectors
        sta tpc_sectors
        lda LVL_BUF+11         ; +11 animated texture frame sectors
        sta an_sectors

        ; --- Parse entity data (at LVL_BUF+12) ---
        lda #<(LVL_BUF+12)
        sta zsrc
        lda #>(LVL_BUF+12)
        sta zsrc+1

        ; --- Enemies (7 bytes: x_lo, x_hi, y_lo, y_hi, type, dir, sleep) ---
        ldx #0
?en_lp  cpx num_en
        bcs ?en_done
        ldy #1
        lda (zsrc),y            ; x_hi
        pha
        dey
        lda (zsrc),y            ; x_lo
        pha
        txa
        asl
        tay
        pla
        sta enemy_spawn_x,y
        pla
        sta enemy_spawn_x+1,y
        ldy #2
        lda (zsrc),y            ; y_lo
        sta enemy_spawn_y,x
        iny
        lda (zsrc),y            ; y_hi
        sta enemy_spawn_yhi,x
        iny
        lda (zsrc),y            ; type
        sta enemy_spawn_type,x
        iny
        lda (zsrc),y            ; dir
        sta enemy_spawn_dir,x
        iny
        lda (zsrc),y            ; sleep
        sta enemy_spawn_sleep,x
        lda #7
        jsr ?adv
        bne ?en_lp              ; Z=0 always
?en_done

        ; --- Pickups (5 bytes: x_lo, x_hi, y_lo, y_hi, type) ---
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
        sta pickup_spawn_yhi,x
        iny
        lda (zsrc),y
        sta pickup_spawn_type,x
        lda #5
        jsr ?adv
        bne ?pk_lp              ; Z=0 always
?pk_done

        ; --- Barrels (4 bytes: x_lo, x_hi, y_lo, y_hi) ---
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
        sta decor_spawn_yhi,x
        lda #4
        jsr ?adv
        bne ?dc_lp              ; Z=0 always
?dc_done
        ; --- the map, the tile tables and the tileset (DAUX continues) ---
.endp
        ert *<>load_map_tiles   ; falls through (6502-idioms: jmp L, L the next)

; LOAD_MAP_TILES - DAUX = the level's map sector: map image -> VRAM, tile
; tables -> RAM, tileset -> VRAM_TILESET. C=1 on an SIO error.
.proc load_map_tiles
        clc                     ; C=0: read
        jsr map_sio
        bcs ?ret
        ldx #TILE_ATTR_SECTORS
        jsr read_sectors        ; into LVL_BUF
        bcs ?ret
        ldx #0
?cp     lda LVL_BUF,x
        sta tile_solid,x
        txa                     ; tile_oneway: ids 0..127 only (its readers
        bmi ?s                  ; test bit 7 first): 128 B, the rest is free
        lda LVL_BUF+256,x
        sta tile_oneway,x
?s      inx
        bne ?cp
        jsr tileset_sio         ; C=0 (bcs not taken, inx/bne keep it): read
        bcs ?ret
        lda #<FORE_RAM          ; the foreground rects (fore.asm)
        sta DBUFLO
        lda #>FORE_RAM
        sta DBUFHI
        ldx #FORE_SECTORS
        jsr read_sectors.win
        bcs ?ret
        lda #<LIQ_RAM           ; the liquid rects (liquid.asm)
        sta DBUFLO
        lda #>LIQ_RAM
        sta DBUFHI
        ldx #LQ_SECTORS
        jsr read_sectors.win
        bcs ?ret
        jsr trig_load           ; the triggers (triggers.asm)
        jcc anim_load           ; the animated textures (anim.asm)
?ret    rts
.endp
