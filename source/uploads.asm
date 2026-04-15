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
        lda #$90+MC_CPU         ; MEMAC-A: 4KB window at $9000, CPU access
        sta VBXE_MEMAC_CTRL
        lda #0
        sta $D40E               ; disable POKEY IRQ during upload
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
        ora #$03                ; re-enable OS ROM
        sta $D301
        lda #$40
        sta $D40E               ; re-enable POKEY IRQ
        rts
.endp
uc_bank   dta 0
uc_cnt    dta 0
uc_lastpg dta 0

;==============================================
; MAP + FIREBALL UPLOAD (bank $1E: map 1024B + imp 128B + caco 128B + baron 128B)
;==============================================
        org $6000
map_bin_data
        ins '../data/map1.bin'
        ins '../data/imp_fireball.bin'
        ins '../data/caco_fireball.bin'
        ins '../data/baron_fireball.bin'

        org $0580
.proc upload_map
        lda #<map_bin_data
        sta zsrc
        lda #>map_bin_data
        sta zsrc+1
        lda #BANK_EN+BANK_MAP
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #6                  ; 1408 bytes (map 1024 + imp 128 + caco 128 + baron 128) = 6 pages
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_map

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

;==============================================
; TILESHEET UPLOAD (4096 bytes, bank $10)
; Loaded at $6000, uploaded to VRAM, RAM freed
;==============================================
        org $6000
tilesheet_data
        ins '../data/tilesheet.bin'

        org $0580
.proc upload_tilesheet
        lda #<tilesheet_data
        sta zsrc
        lda #>tilesheet_data
        sta zsrc+1
        lda #BANK_EN+BANK_TILES
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_tilesheet

;==============================================
; Door tiles 25-27 are embedded in spritesheet_c5.bin at VRAM $032900-$032BFF
;==============================================

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
        lda #10
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_hud_font_ini

;==============================================
; MULTI-SEGMENT SPRITESHEET LOADING
; 4 chunks of max 12KB each (loaded at $6000-$8FFF, never hits $9000 MEMAC)
;==============================================

; --- Chunk 1: 12288 bytes (3 banks: $11-$13) ---
        org $6000
spritesheet_c1
        ins '../data/spritesheet_c1.bin'

        org $0580
.proc upload_chunk1
        lda #<spritesheet_c1
        sta zsrc
        lda #>spritesheet_c1
        sta zsrc+1
        lda #BANK_EN+BANK_SPR0
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk1

; --- Chunk 2: 12288 bytes (3 banks: $14-$16) ---
        org $6000
spritesheet_c2
        ins '../data/spritesheet_c2.bin'

        org $0580
.proc upload_chunk2
        lda #<spritesheet_c2
        sta zsrc
        lda #>spritesheet_c2
        sta zsrc+1
        lda #BANK_EN+$14
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk2

; --- Chunk 3: 12288 bytes (3 banks: $17-$19) ---
        org $6000
spritesheet_c3
        ins '../data/spritesheet_c3.bin'

        org $0580
.proc upload_chunk3
        lda #<spritesheet_c3
        sta zsrc
        lda #>spritesheet_c3
        sta zsrc+1
        lda #BANK_EN+$17
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk3

; --- Chunk 4: 11264 bytes (2 full banks $1A-$1B + 12 pages in $1C) ---
        org $6000
spritesheet_c4
        ins '../data/spritesheet_c4.bin'

        org $0580
.proc upload_chunk4
        lda #<spritesheet_c4
        sta zsrc
        lda #>spritesheet_c4
        sta zsrc+1
        lda #BANK_EN+$1A
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16             ; last bank: 16 pages (12288 bytes, chunk4 full)
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk4

; --- Chunk 5: new death sprites (bank $31 = VRAM $031000+) ---
        org $6000
spritesheet_c5
        ins '../data/spritesheet_c5.bin'

        org $0580
.proc upload_chunk5
        lda #<spritesheet_c5
        sta zsrc
        lda #>spritesheet_c5
        sta zsrc+1
        lda #BANK_EN+$31
        sta uc_bank
        lda #3              ; 3 banks: $31 + $32 + $33
        sta uc_cnt
        lda #16             ; last bank: full 16 pages
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk5

;==============================================
; SWITCH + NEW TILES at VRAM $060000 (bank $60)
; 28-31: switches, 32-42: new wall textures
;==============================================
        org $6000
switch_tiles
        ins '../data/switch_off.bin'
        ins '../data/switch_on.bin'
        ins '../data/switch3_off.bin'
        ins '../data/switch3_on.bin'
        ins '../data/new_tiles.bin'
        org $0580
.proc upload_switch_tiles
        lda #<switch_tiles
        sta zsrc
        lda #>switch_tiles
        sta zsrc+1
        lda #BANK_EN+$60
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #15
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_switch_tiles

; --- Chunk 6: plasma/cells pickup sprites (bank $1F, 2 pages) ---
        org $6000
spritesheet_c6
        ins '../data/spritesheet_c6.bin'

        org $0580
.proc upload_chunk6
        lda #<spritesheet_c6
        sta zsrc
        lda #>spritesheet_c6
        sta zsrc+1
        lda #BANK_EN+$1F
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk6

; --- Chunk 7: pain sprites (bank $52 = VRAM $052000) ---
; pl, pl_L, zombie, zombie_L, shotgun, shotgun_L, imp, imp_L,
; pinky, pinky_L, caco, caco_L, baron, baron_L (14 x 512B = 7168B)
        org $6000
spritesheet_c7
        ins '../data/pain_sprites.bin'

        org $0580
.proc upload_chunk7
        lda #<spritesheet_c7
        sta zsrc
        lda #>spritesheet_c7
        sta zsrc+1
        lda #BANK_EN+$58
        sta uc_bank
        lda #2
        sta uc_cnt
        lda #16                 ; 7168 bytes = 2 banks, last 16 pages
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk7

; --- Chunk 8: new decoration sprites (bank $54 = VRAM $054000) ---
; column, skulpillar, eleclamp, deadtree, browntree, hangbody, hangleg,
; impaled, skullpile, redtorch1-4 (6144B = 1 full bank + 8 pages)
        org $6000
spritesheet_c8
        ins '../data/spritesheet_decor.bin'

        org $0580
.proc upload_chunk8
        lda #<spritesheet_c8
        sta zsrc
        lda #>spritesheet_c8
        sta zsrc+1
        lda #BANK_EN+$54
        sta uc_bank
        lda #2              ; 2 banks: $54 (full) + $55 (partial)
        sta uc_cnt
        lda #8              ; last bank: 8 pages (2048 bytes)
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk8

; --- Chunk 9: Lost Soul sprites (bank $56-$57 = VRAM $056000-$057FFF) ---
; 16 sprites x 512B = 8192B = 2 full banks
        org $6000
spritesheet_c9
        ins '../data/spritesheet_lostsoul.bin'

        org $0580
.proc upload_chunk9
        lda #<spritesheet_c9
        sta zsrc
        lda #>spritesheet_c9
        sta zsrc+1
        lda #BANK_EN+$56
        sta uc_bank
        lda #2              ; 2 banks: $56 (full) + $57 (full)
        sta uc_cnt
        lda #16             ; last bank: full 16 pages
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_chunk9

;==============================================
; SKY UPLOAD TO VRAM $034000+ (banks $34-$43)
; Static upload at boot — 6 chunks, 64000 bytes total
;==============================================

; --- Sky chunk 1: 12288 bytes (banks $34-$36) ---
        org $6000
sky_c1  ins '../data/sky_c1.bin'
        org $0580
.proc upload_sky1
        lda #<sky_c1
        sta zsrc
        lda #>sky_c1
        sta zsrc+1
        lda #BANK_EN+$34
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_sky1

; --- Sky chunk 2: 12288 bytes (banks $37-$39) ---
        org $6000
sky_c2  ins '../data/sky_c2.bin'
        org $0580
.proc upload_sky2
        lda #<sky_c2
        sta zsrc
        lda #>sky_c2
        sta zsrc+1
        lda #BANK_EN+$37
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_sky2

; --- Sky chunk 3: 12288 bytes (banks $3A-$3C) ---
        org $6000
sky_c3  ins '../data/sky_c3.bin'
        org $0580
.proc upload_sky3
        lda #<sky_c3
        sta zsrc
        lda #>sky_c3
        sta zsrc+1
        lda #BANK_EN+$3A
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_sky3

; --- Sky chunk 4: 12288 bytes (banks $3D-$3F) ---
        org $6000
sky_c4  ins '../data/sky_c4.bin'
        org $0580
.proc upload_sky4
        lda #<sky_c4
        sta zsrc
        lda #>sky_c4
        sta zsrc+1
        lda #BANK_EN+$3D
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_sky4

; --- Sky chunk 5: 12288 bytes (banks $40-$42) ---
        org $6000
sky_c5  ins '../data/sky_c5.bin'
        org $0580
.proc upload_sky5
        lda #<sky_c5
        sta zsrc
        lda #>sky_c5
        sta zsrc+1
        lda #BANK_EN+$40
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_sky5

; --- Sky chunk 6: 2560 bytes (bank $43, 10 pages) ---
        org $6000
sky_c6  ins '../data/sky_c6.bin'
        org $0580
.proc upload_sky6
        lda #<sky_c6
        sta zsrc
        lda #>sky_c6
        sta zsrc+1
        lda #BANK_EN+$43
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #10
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_sky6

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
        lda #1
        sta uc_cnt
        lda #13                 ; snd_c6: 1 bank ($53), 13 pages (3176B)
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_snd6
