;==============================================
; GENERIC VRAM CHUNK UPLOAD
; Params: zsrc=source, uc_bank=start bank, uc_cnt=bank count, uc_lastpg=pages in last bank
;==============================================
.proc generic_upload
        lda #$90+MC_CPU
        sta VBXE_MEMAC_CTRL
        lda #0
        sta $D40E
        lda $D301
        and #$FC
        sta $D301

?nxbank lda uc_bank
        sta VBXE_BANK_SEL
        lda #>MEMW
        sta ?wr+2
        ldx #16             ; default: full 16 pages per bank
        lda uc_cnt
        cmp #1
        bne ?full
        ldx uc_lastpg       ; last bank may be partial
?full
?page   ldy #0
?lp     lda (zsrc),y
?wr     sta MEMW,y
        iny
        bne ?lp
        inc zsrc+1
        inc ?wr+2
        dex
        bne ?page
        inc uc_bank
        dec uc_cnt
        bne ?nxbank

        ; Disable MEMAC bank before returning
        lda #0
        sta VBXE_BANK_SEL

        lda $D301
        ora #$03
        sta $D301
        lda #$40
        sta $D40E
        rts
.endp
uc_bank   dta 0
uc_cnt    dta 0
uc_lastpg dta 0
