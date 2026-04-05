;==============================================
; DOOM2D - Digital sample playback engine (VRAM via MEMAC-B)
; sound.asm
;
; Sounds in VRAM, read via MEMAC-B ($4000-$7FFF window).
; MEMAC-B is INDEPENDENT from MEMAC-A (map/blitter).
; No BANK_SEL conflicts, no buffer needed.
;==============================================

; Sound state: snd_active/snd_cur_byte/snd_lock/snd_bank moved to ZP ($C9-$CC)

; Saved original VIMIRQ
old_iir         dta a(0)
snd_enabled     dta 1               ; 1=sounds on, 0=sounds off

; ============================================
; SND_INIT
; ============================================
.proc snd_init
        lda #0
        sta SKCTL
        nop
        nop
        lda #3
        sta SKCTL

        lda #0
        sta AUDCTL
        sta AUDC1
        sta AUDC2
        sta $D205
        sta AUDC4

        lda #15
        sta AUDF1

        lda #0
        sta snd_active
        sta snd_cur_byte
        sta snd_lock
        sta snd_bank
        sta snd_phase
        sta VBXE_MEMAC_B
        lda #$FF
        sta snd_queue

        sei
        lda $0216
        sta old_iir
        lda $0217
        sta old_iir+1
        lda #<snd_irq
        sta $0216
        lda #>snd_irq
        sta $0217
        cli
        rts
.endp

; ============================================
; PLAY_SFX_UNLOCK - Clear snd_lock, play sound, preserve X
; Input: A = SFX index
; ============================================
.proc play_sfx_unlock
        stx zt2
        tax
        lda #0
        sta snd_lock
        jsr snd_play
        ldx zt2
        rts
.endp

; ============================================
; SND_PLAY - Start playing a sound from VRAM
; Input: X = SFX index (0-13)
; ============================================
.proc snd_play
        lda snd_enabled
        beq ?skip
        lda snd_lock
        bne ?skip

        sei
        lda sfx_vptr_lo,x
        sta snd_ptr
        lda sfx_vptr_hi,x
        sta snd_ptr+1
        lda sfx_vbank,x
        sta snd_bank

        lda sfx_vend_lo,x
        sta snd_end
        lda sfx_vend_hi,x
        sta snd_end+1
        lda sfx_vbank_end,x
        sta snd_end_bank

        lda #0
        sta snd_phase
        ; Pre-read first byte (hi nibble IRQ won't read)
        jsr snd_memac_read
        lda #1
        sta snd_active

        lda POKMSK
        ora #$01
        sta POKMSK
        sta IRQEN
        sta STIMER
        cli
?skip   rts

snd_end_bank dta 0
.endp

; Sound queue: plays next sound when lock expires
snd_queue       dta $FF         ; $FF = empty, else SFX index
snd_queue_lock  dta 0           ; lock value for queued sound

; ============================================
; SOUND UPDATE - decrement priority lock + play queue
; ============================================
.proc sound_update
        lda snd_lock
        beq ?chk_queue
        dec snd_lock
        bne ?done
?chk_queue
        ; Lock expired — check queue
        lda snd_queue
        cmp #$FF
        beq ?done
        ; Play queued sound
        tax
        lda #$FF
        sta snd_queue           ; clear queue
        lda #0
        sta snd_lock
        jsr snd_play
        lda snd_queue_lock
        sta snd_lock
?done   rts
.endp

; ============================================
; IRQ HANDLER (MEMAC-B)
; ~65 cycles, no BANK_SEL conflict with graphics
; ============================================
.proc snd_irq
        pha

        lda IRQEN
        and #$01
        beq ?is_ours
        jmp ?not_ours
?is_ours
        lda POKMSK
        and #$FE
        sta IRQEN
        lda POKMSK
        sta IRQEN

        lda snd_active
        beq ?silent

        lda snd_phase
        bne ?lo

        ; --- Hi nibble: just output (no VRAM read = fast!) ---
        lda snd_cur_byte
        lsr
        lsr
        lsr
        lsr
        ora #$10
        sta AUDC4
        inc snd_phase          ; 0 → 1
        pla
        rti

?lo     ; --- Lo nibble: output + advance + read next byte ---
        lda snd_cur_byte
        and #$0F
        ora #$10
        sta AUDC4
        dec snd_phase          ; 1 → 0

        inc snd_ptr
        bne ?nc
        inc snd_ptr+1
        lda snd_ptr+1
        cmp #$80
        bne ?nc
        lda #$40
        sta snd_ptr+1
        inc snd_bank
?nc
        ; End check
        lda snd_bank
        cmp snd_play.snd_end_bank
        bne ?read
        lda snd_ptr+1
        cmp snd_end+1
        bne ?read
        lda snd_ptr
        cmp snd_end
        bne ?read

        ; Sound finished
        lda #0
        sta snd_active
        sta AUDC4
        lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN
        pla
        rti

?read   ; Pre-read next byte via trampoline (for next hi nibble)
        sty snd_save_y
        jsr snd_memac_read
        ldy snd_save_y
        pla
        rti

?silent lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN
        pla
        rti

?not_ours
        pla
        jmp (old_iir)
.endp

; ============================================
; PLAY ENEMY DEATH SOUND
; ============================================
.proc play_enemy_death
        lda en_type,x
        tay
        lda en_death_sfx,y
        cmp #$FF
        beq ?skip
        ; If sound locked, queue instead of dropping
        stx zt2
        lda snd_lock
        beq ?play_now
        ; Queue death sound for later
        lda en_death_sfx,y
        sta snd_queue
        lda #8
        sta snd_queue_lock
        ldx zt2
        rts
?play_now
        lda en_death_sfx,y
        tax
        jsr snd_play
        lda #8
        sta snd_lock
        ldx zt2
?skip   rts
.endp

; ============================================
; PLAY ENEMY SIGHT SOUND
; ============================================
.proc play_enemy_sight
        lda en_type,x
        tay
        lda en_sight_sfx,y
        cmp #$FF
        beq ?skip
        stx zt2
        lda #0
        sta snd_lock
        ; Zombie/shotgun: randomly pick 1 of 3 sight sounds
        lda en_type,x
        cmp #EN_ZOMBIE
        beq ?rnd_posit
        cmp #EN_SHOTGUN
        beq ?rnd_posit
        ; Other enemies: use table directly
        lda en_sight_sfx,y
        jmp ?play
?rnd_posit
        ; Random 0-2 from frame counter
        lda zfr
        eor RTCLOK3
        and #$03
        cmp #3
        bne ?rok
        lda #0             ; 3 -> 0 (keep range 0-2)
?rok    cmp #0
        bne ?p2
        lda #SFX_POSIGHT
        jmp ?play
?p2     cmp #1
        bne ?p3
        lda #SFX_POSIGHT2
        jmp ?play
?p3     lda #SFX_POSIGHT3
?play   tax
        jsr snd_play
        lda #8
        sta snd_lock
        ldx zt2
?skip   rts
.endp

; ============================================
; VRAM SOUND ADDRESS TABLES (auto-generated)
; ============================================
        icl '../data/sound_tables.asm'
