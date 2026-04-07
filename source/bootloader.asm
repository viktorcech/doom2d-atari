;==============================================
; DOOM2D - Custom ATR Boot Loader
; Loaded to $0700 by Atari OS from boot sectors 1-3
; Parses XEX binary from raw ATR sectors via SIO
;==============================================

        opt h+
        opt o+

        org $0700

; === Boot header (6 bytes, read by OS) ===
        dta $00                 ; boot flag
        dta 3                   ; load 3 sectors (384 bytes)
        dta a($0700)            ; load address
        dta a(boot_init)        ; init address (jump here after load)

; === Variables ===
cur_sec     dta a(4)            ; current sector number (XEX starts at 4)
buf_pos     dta 128             ; position in buffer (128 = force first read)
seg_lo      dta 0
seg_hi      dta 0
end_lo      dta 0
end_hi      dta 0

; Zero page pointer for indirect store (must be in ZP)
zp_dest     = $E0              ; 2 bytes: destination pointer (free ZP area)

SECBUF      = $0800             ; 128-byte sector read buffer

; === Boot entry point ===
boot_init
        ; Disable screen for fast loading
        lda #0
        sta $22F                ; SDMCTL off
        sta $D400               ; DMACTL off

        ; Skip $FF $FF XEX header
        jsr get_byte
        jsr get_byte

; === Parse next segment ===
parse_seg
        jsr get_byte
        sta seg_lo
        jsr get_byte
        sta seg_hi

        ; Check $FF $FF separator
        lda seg_lo
        and seg_hi
        cmp #$FF
        beq parse_seg           ; skip $FF $FF, re-read

        ; Read end address
        jsr get_byte
        sta end_lo
        jsr get_byte
        sta end_hi

        ; Check INIT vector ($02E2)
        lda seg_hi
        cmp #$02
        bne data_seg
        lda seg_lo
        cmp #$E2
        beq do_init
        cmp #$E0
        beq do_run

; === Load data segment to memory ===
data_seg
        lda seg_lo
        sta zp_dest
        lda seg_hi
        sta zp_dest+1

?lp     jsr get_byte
        ldy #0
        sta (zp_dest),y
        ; Check dest == end
        lda zp_dest
        cmp end_lo
        bne ?next
        lda zp_dest+1
        cmp end_hi
        beq parse_seg           ; segment done, next
?next   inc zp_dest
        bne ?lp
        inc zp_dest+1
        jmp ?lp

; === INIT segment: load 2-byte address, JSR there ===
do_init
        jsr get_byte
        sta jsr_tgt+1
        jsr get_byte
        sta jsr_tgt+2
        jsr jsr_tgt             ; call INIT routine
        jmp parse_seg

; === RUN segment: load 2-byte address, JMP there ===
do_run
        jsr get_byte
        sta jmp_tgt+1
        jsr get_byte
        sta jmp_tgt+2
jmp_tgt jmp $0000               ; patched with RUN address

; === Indirect JSR (self-modifying) ===
jsr_tgt jmp $0000               ; patched, called via JSR

; === Get next byte from sector buffer ===
get_byte
        ldx buf_pos
        cpx #128
        bcc ?ok
        jsr read_sec
        ldx #0
?ok     lda SECBUF,x
        inx
        stx buf_pos
        rts

; === Read one sector via SIO ===
read_sec
        lda #$31
        sta $0300               ; DDEVIC (disk)
        lda #$01
        sta $0301               ; DUNIT (drive 1)
        lda #$52
        sta $0302               ; DCOMND (read)
        lda #$40
        sta $0303               ; DSTATS (receive)
        lda #<SECBUF
        sta $0304               ; DBUFLO
        lda #>SECBUF
        sta $0305               ; DBUFHI
        lda #$0F
        sta $0306               ; DTIMLO (timeout)
        lda #128
        sta $0308               ; DBYTLO
        lda #0
        sta $0309               ; DBYTHI
        lda cur_sec
        sta $030A               ; DAUX1 (sector lo)
        lda cur_sec+1
        sta $030B               ; DAUX2 (sector hi)
        jsr $E459               ; SIOV
        inc cur_sec
        bne ?done
        inc cur_sec+1
?done   lda #0
        sta buf_pos
        rts
