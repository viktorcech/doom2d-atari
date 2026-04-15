;==============================================
; DOOM2D - Digital sample playback engine (VRAM via MEMAC-B)
; sound.asm
;
; 2026-04-08: Timer IRQ + deferred VRAM read + Phase 0 fallback.
; Phase 1 defers VRAM read to snd_poll (saves ~37 cycles/Phase 1).
; Phase 0 falls back to inline read if snd_poll missed it.
; snd_poll called from wait_blit, vsync, and logic phase.
;
; ~17% CPU (down from ~20% original). Clean sound, no artifacts.
;==============================================

; Sound state in ZP ($C4-$CD)

old_iir         dta a(0)
snd_enabled     dta 1
snd_need_read   dta 0           ; 1 = VRAM read pending

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
        sta snd_need_read
        sta VBXE_MEMAC_B
        lda #$FF
        sta snd_queue

        ; Hook VIMIRQ for Timer 1 + chain to OS
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
; PLAY_SFX_UNLOCK
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
; SND_PLAY
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
        sta snd_need_read
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

; Sound queue
snd_queue       dta $FF
snd_queue_lock  dta 0

; ============================================
; SOUND UPDATE
; ============================================
.proc sound_update
        lda snd_lock
        beq ?chk_queue
        dec snd_lock
        bne ?done
?chk_queue
        lda snd_queue
        cmp #$FF
        beq ?done
        tax
        lda #$FF
        sta snd_queue
        lda #0
        sta snd_lock
        jsr snd_play
        lda snd_queue_lock
        sta snd_lock
?done   rts
.endp

; ============================================
; TIMER 1 IRQ — deferred VRAM read
;
; 2026-04-08: Phase 0 outputs hi nibble. If snd_poll missed the
; deferred read, Phase 0 does it inline (fallback — never stale).
; Phase 1 outputs lo nibble, advances pointer, defers VRAM read.
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

        ; --- Phase 0: hi nibble + fallback VRAM read if needed ---
        lda snd_need_read
        beq ?have_byte
        sty snd_save_y
        jsr snd_memac_read
        ldy snd_save_y
        lda #0
        sta snd_need_read
?have_byte
        lda snd_cur_byte
        lsr
        lsr
        lsr
        lsr
        ora #$10
        sta AUDC4
        inc snd_phase
        pla
        rti

?lo     ; --- Phase 1: lo nibble + advance + defer read ---
        lda snd_cur_byte
        and #$0F
        ora #$10
        sta AUDC4
        dec snd_phase

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
        lda snd_bank
        cmp snd_play.snd_end_bank
        bne ?defer
        lda snd_ptr+1
        cmp snd_end+1
        bne ?defer
        lda snd_ptr
        cmp snd_end
        bne ?defer

        lda #0
        sta snd_active
        sta AUDC4
        lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN
        pla
        rti

?defer  lda #1
        sta snd_need_read
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
; SND_POLL — deferred VRAM read
; 2026-04-08: SEI/CLI protects MEMAC-B access (snd_irq at ~$5Axx
; is inside $4000-$7FFF MEMAC-B range).
; ============================================
.proc snd_poll
        lda snd_need_read
        beq ?done
        sei
        lda #0
        sta snd_need_read
        sty snd_save_y
        jsr snd_memac_read
        ldy snd_save_y
        cli
?done   rts
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
        stx zt2
        ; Pick sound (random for zombie/shotgun)
        lda en_type,x
        cmp #EN_ZOMBIE
        beq ?rnd_podth
        cmp #EN_SHOTGUN
        beq ?rnd_podth
        lda en_death_sfx,y
        jmp ?got_sfx
?rnd_podth
        lda zfr
        eor RTCLOK3
        and #$03
        cmp #3
        bne ?drok
        lda #0
?drok   cmp #1
        bcc ?pd1
        beq ?pd2
        lda #SFX_PODEATH3
        jmp ?got_sfx
?pd1    lda #SFX_PODEATH
        jmp ?got_sfx
?pd2    lda #SFX_PODEATH2
?got_sfx
        ; A = sfx index
        ldy snd_lock
        bne ?queue
        tax
        jsr snd_play
        lda #8
        sta snd_lock
        ldx zt2
        rts
?queue  sta snd_queue
        lda #8
        sta snd_queue_lock
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
        lda en_type,x
        cmp #EN_ZOMBIE
        beq ?rnd_posit
        cmp #EN_SHOTGUN
        beq ?rnd_posit
        cmp #EN_IMP
        beq ?rnd_imp
        lda en_sight_sfx,y
        jmp ?play
?rnd_imp
        lda zfr
        eor RTCLOK3
        and #$01
        beq ?imp1
        lda #SFX_IMPSIT2
        jmp ?play
?imp1   lda #SFX_IMPSIGHT
        jmp ?play
?rnd_posit
        lda zfr
        eor RTCLOK3
        and #$03
        cmp #3
        bne ?rok
        lda #0
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
