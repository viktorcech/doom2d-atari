;==============================================
; DOOM2D - Title screen uploads
; uploads_title.asm
;==============================================

; =============================================
; TITLE SCREEN UPLOAD (320x200 = 64000 bytes)
; Upload to Screen 0 ($000000) and Screen 1 ($020000)
; 6 chunks, same layout as sky upload
; =============================================
; --- Title chunk 1 (banks $00-$02) ---
        org $6000
title_c1 ins '../data/title_c1.bin'
        org $0580
.proc upload_title1
        lda #<title_c1
        sta zsrc
        lda #>title_c1
        sta zsrc+1
        lda #BANK_EN+$00
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        ; Also upload to Screen 1
        lda #<title_c1
        sta zsrc
        lda #>title_c1
        sta zsrc+1
        lda #BANK_EN+$20
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_title1

; --- Title chunk 2 (banks $03-$05) ---
        org $6000
title_c2 ins '../data/title_c2.bin'
        org $0580
.proc upload_title2
        lda #<title_c2
        sta zsrc
        lda #>title_c2
        sta zsrc+1
        lda #BANK_EN+$03
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        lda #<title_c2
        sta zsrc
        lda #>title_c2
        sta zsrc+1
        lda #BANK_EN+$23
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_title2

; --- Title chunk 3 (banks $06-$08) ---
        org $6000
title_c3 ins '../data/title_c3.bin'
        org $0580
.proc upload_title3
        lda #<title_c3
        sta zsrc
        lda #>title_c3
        sta zsrc+1
        lda #BANK_EN+$06
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        lda #<title_c3
        sta zsrc
        lda #>title_c3
        sta zsrc+1
        lda #BANK_EN+$26
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_title3

; --- Title chunk 4 (banks $09-$0B) ---
        org $6000
title_c4 ins '../data/title_c4.bin'
        org $0580
.proc upload_title4
        lda #<title_c4
        sta zsrc
        lda #>title_c4
        sta zsrc+1
        lda #BANK_EN+$09
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        lda #<title_c4
        sta zsrc
        lda #>title_c4
        sta zsrc+1
        lda #BANK_EN+$29
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_title4

; --- Title chunk 5 (banks $0C-$0E) ---
        org $6000
title_c5t ins '../data/title_c5.bin'
        org $0580
.proc upload_title5
        lda #<title_c5t
        sta zsrc
        lda #>title_c5t
        sta zsrc+1
        lda #BANK_EN+$0C
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        lda #<title_c5t
        sta zsrc
        lda #>title_c5t
        sta zsrc+1
        lda #BANK_EN+$2C
        sta uc_bank
        lda #3
        sta uc_cnt
        lda #16
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_title5

; --- Title chunk 6 (bank $0F, partial) ---
        org $6000
title_c6t ins '../data/title_c6.bin'
        org $0580
.proc upload_title6
        lda #<title_c6t
        sta zsrc
        lda #>title_c6t
        sta zsrc+1
        lda #BANK_EN+$0F
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #10
        sta uc_lastpg
        jsr generic_upload
        lda #<title_c6t
        sta zsrc
        lda #>title_c6t
        sta zsrc+1
        lda #BANK_EN+$2F
        sta uc_bank
        lda #1
        sta uc_cnt
        lda #10
        sta uc_lastpg
        jsr generic_upload
        rts
.endp
        ini upload_title6
