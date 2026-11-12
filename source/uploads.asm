;==============================================
; DOOM2D - Asset uploads (VRAM)
; uploads.asm
;==============================================

;==============================================
; GENERIC CHUNK UPLOAD — Copy data from RAM to VBXE VRAM
;
; Copies data through the MEMAC-A window ($9000-$9FFF, 4KB per bank).
; Each bank maps a 4KB slice of VRAM. Multi-bank uploads are supported.
;
; Placed at $0630 (init-only, after snd_memac_read at $0610).
; Safe: below bootloader ($0700) and SECBUF ($0800).
; Frees ~88 bytes in the main segment (was near $6000 limit).
;
; Params:
;   zsrc      = 16-bit source pointer in RAM (e.g. $6000)
;   uc_bank   = VBXE bank number (BANK_EN + bank, e.g. $9E for VRAM $01E000)
;   uc_cnt    = number of 4KB banks to upload (1 = single bank)
;   uc_lastpg = pages (256B each) in the LAST bank (max 16 = full 4KB)
;
; During upload, OS ROM is disabled ($D301) and POKEY IRQs are masked
; to prevent interference with the MEMAC-A window.
;==============================================
        org $0630
.proc generic_upload
        php
        sei                     ; NO IRQs while the OS ROM is off below: a late
                                ; POKEY/serial IRQ would fetch its vector from
                                ; the RAM under the ROM (= garbage) and crash
        lda #$90+MC_CPU         ; MEMAC-A: 4KB window at $9000, CPU access
        sta VBXE_MEMAC_CTRL
        lda #0
        sta $D40E               ; NMIEN=0: no VBI during upload either
        lda $D301
        and #$FC                ; disable OS ROM (expose RAM under $C000-$FFFF)
        sta $D301

?nxbank lda uc_bank
        sta VBXE_BANK_SEL      ; select VRAM bank → $9000 maps to VRAM
        lda #>MEMW              ; reset write pointer to $9000
        sta ?wr+2               ; self-modifying: patch STA address hi byte
        ldx #16                 ; default: 16 pages (4KB) per bank
        lda uc_cnt
        cmp #1
        bne ?full
        ldx uc_lastpg           ; last bank: only upload partial pages
?full
?page   ldy #0                  ; copy 256 bytes (one page)
?lp     lda (zsrc),y            ; read from RAM
?wr     sta MEMW,y              ; write to VRAM via MEMAC window
        iny
        bne ?lp
        inc zsrc+1              ; advance source by 256
        inc ?wr+2               ; advance dest by 256 (within $9000-$9FFF)
        dex
        bne ?page
        inc uc_bank             ; next VRAM bank
        dec uc_cnt
        bne ?nxbank

        lda #0                  ; disable MEMAC bank mapping
        sta VBXE_BANK_SEL      ; (prevents XEX loader writing to VRAM)

        lda $D301
        ora #$03                ; re-enable OS ROM (+ keep BASIC off)
        sta $D301
        lda #$40
        sta $D40E               ; NMIEN: VBI back on
        plp                     ; restore caller's IRQ mask
        rts
.endp
uc_bank   dta 0
uc_cnt    dta 0
uc_lastpg dta 0

;==============================================
; PALETTE SETUP (768 bytes, loaded at $6000, written to VBXE palette regs)
;==============================================
        org $6000
palette_data
        ins '../data/palette.bin'

        org $0580
.proc upload_palette
        lda #0
        sta VBXE_CSEL
        lda #1
        sta VBXE_PSEL
        ldx #0
?lp     lda palette_data,x
        asl                     ; *2: expand 7-bit (0-127) to 8-bit (0-254)
        sta VBXE_CR
        lda palette_data+256,x
        asl
        sta VBXE_CG
        lda palette_data+512,x
        asl
        sta VBXE_CB
        inx
        bne ?lp
        rts
.endp
        ini upload_palette

; --- The sky (sky.asm, tools/sky2vbxe.py): 8064 B -> VRAM_SKY, banks $32-$33 ---
        org $6000
sky_data ins '../data/sky_vbxe.bin'
        org $0580
.proc upload_sky
        lda #<sky_data
        sta zsrc
        lda #>sky_data
        sta zsrc+1
        lda #BANK_EN+[VRAM_SKY>>12]
        sta uc_bank
        lda #2
        sta uc_cnt
        lda #[SKY_W*SKY_H-$1000+255]/256    ; pages in the second bank
        sta uc_lastpg
        jmp generic_upload
.endp
        ini upload_sky

; --- The MODE 7 tables: the liquid filters (liquid.asm) + the stats' red text
;     (hud.asm show_level_stats): 4 x 256 B -> VRAM_LUT, bank $30 ---
        org $6000
lut_data ins '../data/liquid_lut.bin'
        org $0580
.proc upload_lut
        lda #<lut_data
        sta zsrc
        lda #>lut_data
        sta zsrc+1
        lda #BANK_EN+[VRAM_LUT>>12]
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #4                  ; 4 pages: water, acid1, acid2, the red text
        sta uc_lastpg
        jmp generic_upload
.endp
        ini upload_lut

; (map tiles come with each level: diskio.asm load_map_tiles -> VRAM_TILESET)

;==============================================
; HUD FONT UPLOAD (2432 bytes = 10 pages, bank $1D)
; Chars: 0-9, heart, bullet, A-Z
;==============================================
        org $6000
hud_font_data
        ins '../data/hud_font.bin'

        org $0580
.proc upload_hud_font_ini
        lda #<hud_font_data
        sta zsrc
        lda #>hud_font_data
        sta zsrc+1
        lda #BANK_EN+BANK_HUD
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #11                 ; 44 glyphs x 64 B = 11 pages
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_hud_font_ini

;==============================================
; SPRITES: monsters, player, items, barrels, HUD icons, projectiles
; (tools/prepare_sprites.py, the Doom 2D Forever graphics)
;==============================================
        icl 'gen/mon_upload.asm'

;==============================================
; SOUND DATA UPLOAD TO VRAM ($044000+)
; Original .bin files concatenated, read via MEMAC-B
;==============================================

; --- Sound chunk 1: 12288 bytes (banks $44-$46) ---
        org $6000
snd_c1  ins '../data/snd_c1.bin'
        org $0580
.proc upload_snd1
        lda #<snd_c1
        sta zsrc
        lda #>snd_c1
        sta zsrc+1
        lda #BANK_EN+$44
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_snd1

; --- Sound chunk 2: 12288 bytes (banks $47-$49) ---
        org $6000
snd_c2  ins '../data/snd_c2.bin'
        org $0580
.proc upload_snd2
        lda #<snd_c2
        sta zsrc
        lda #>snd_c2
        sta zsrc+1
        lda #BANK_EN+$47
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_snd2

; --- Sound chunk 3: 12288 bytes (banks $4A-$4C, 48 pages) ---
        org $6000
snd_c3  ins '../data/snd_c3.bin'
        org $0580
.proc upload_snd3
        lda #<snd_c3
        sta zsrc
        lda #>snd_c3
        sta zsrc+1
        lda #BANK_EN+$4A
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_snd3

; --- Sound chunk 4: last chunk (banks $4D+) ---
; IMPORTANT: After adding/removing sounds in sounds2vram.py,
; update uc_lastpg below! Calculate: chunk4 size / 4096 = full banks,
; remainder / 256 rounded up = uc_lastpg. If wrong, new sounds crackle.
        org $6000
snd_c4  ins '../data/snd_c4.bin'
        org $0580
.proc upload_snd4
        lda #<snd_c4
        sta zsrc
        lda #>snd_c4
        sta zsrc+1
        lda #BANK_EN+$4D
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16                 ; 12288 bytes: 3 full banks (48 pages, 16 per bank)
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_snd4

; --- Sound chunk 5: overflow sounds (bank $50) ---
; IMPORTANT: update uc_lastpg when adding more sounds!
        org $6000
snd_c5  ins '../data/snd_c5.bin'
        org $0580
.proc upload_snd5
        lda #<snd_c5
        sta zsrc
        lda #>snd_c5
        sta zsrc+1
        lda #BANK_EN+$50
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16                 ; snd_c5: 3 banks ($50-$52), full (12288B)
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_snd5

        org $6000
snd_c6  ins '../data/snd_c6.bin'
        org $0580
.proc upload_snd6
        lda #<snd_c6
        sta zsrc
        lda #>snd_c6
        sta zsrc+1
        lda #BANK_EN+$53
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16                 ; snd_c6: 3 banks ($53-$55), full (12288B)
        sta uc_lastpg
        jmp generic_upload
.endp
        ini upload_snd6

        org $6000
snd_c7  ins '../data/snd_c7.bin'
        org $0580
.proc upload_snd7
        lda #<snd_c7
        sta zsrc
        lda #>snd_c7
        sta zsrc+1
        lda #BANK_EN+$56
        sta uc_bank
        lda #2
        sta uc_cnt
        lda #11                 ; snd_c7: 2 banks ($56-$57), 11 pages in the last (6879B)
        sta uc_lastpg
        jmp generic_upload
.endp
        ini upload_snd7

; snd_x: the sounds past the blood lists ($058000), in the map's last bank
; after its rows ($05D200, tools/sounds2vram.py X_BASE); the level load
; overwrites the zero padding below them with the map's last rows
        org $6000
snd_x   ins '../data/snd_x.bin'
        org $0580
.proc upload_sndx
        lda #<snd_x
        sta zsrc
        lda #>snd_x
        sta zsrc+1
        lda #BANK_EN+$5D
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #15                 ; snd_x: 15 pages (3840B)
        sta uc_lastpg
        jmp generic_upload
.endp
        ini upload_sndx
        ert BANK_MAP*4096+MAP_BYTES>$05D200

; snd_y: the bank $012000 between the small sprites ($011000) and $013000
; (tools/prepare_sprites.py REGIONS leaves it out)
        org $6000
snd_y   ins '../data/snd_y.bin'
        org $0580
.proc upload_sndy
        lda #<snd_y
        sta zsrc
        lda #>snd_y
        sta zsrc+1
        lda #BANK_EN+$12
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #16                 ; snd_y: 16 pages (4096B)
        sta uc_lastpg
        jmp generic_upload
.endp
        ini upload_sndy
