;==============================================
; DOOM2D - Digital sample playback engine (VRAM via MEMAC-B)
; sound.asm
;
; 4-bit samples, two nibbles a byte, SND_NV voices at once (doom/sound.asm:
; a voice on each POKEY channel, volume only - POKEY sums the four). The
; POKEY timer 1 IRQ (AUDF1 = 15: ~4 kHz a nibble) plays one nibble of every
; live voice, read straight from VRAM; it sits below the MEMAC-B window.
;==============================================

SND_NV  = 4                     ; voices: POKEY's four channels

; ============================================
; TIMER 1 IRQ - two handlers swapped through VIMIRQ's lo byte (one page), all
; voices in step: snd_hi reads every live voice's byte (MEMAC-B) and plays
; its hi nibble, leaving the lo one in snd_lo's lda # operand; snd_lo plays
; those and steps the pointers. A voice is an unrolled block in each, its
; first instruction its state: a jmp past it when idle (snd_play / snd_idle
; patch it). Only A is used, kept in the handler's own lda # operand
; (6502-nmos-atari: save only what is used; the OS IRQ entry saves nothing).
; In the RAM past tr_pl (OS LBUFF: only its floating point uses it, and page
; 6: the boot's upload code ran there, the main segment loads after it).
; ============================================
snd_save = *
        org tr_pl+PL_MAX
.proc snd_hi
go      sta a+1                 ; (VIMIRQ: the entry)
        lda IRQST               ; bit 0 = 0: timer 1 pending (ours)
        lsr
        bcs no
m0      lda #0                  ; (patched: POKMSK without timer 1)
        sta IRQEN               ; acknowledge timer 1 ...
m1      lda #0                  ; (patched: POKMSK, timer 1 on: snd_play)
        sta IRQEN               ; ... re-enable
        .rept SND_NV, #
hb%%1   jmp ht                  ; (live: lda snd_bk+%%1, MEMAC-B: enable + bank;
                                ;  idle: jmp the next live block or ht, snd_link)
        sta VBXE_MEMAC_B
hp%%1   lda $4000               ; (patched: the byte)
        sta snd_lo.lv%%1+1      ; its lo nibble: the next tick
        lsr
        lsr
        lsr
        lsr
        ora #$10                ; volume only
        sta AUDC1+2*%%1
        .endr
ht      lda #0                  ; MEMAC-B off: the main code is in its window
        sta VBXE_MEMAC_B
        lda #<snd_lo.go         ; next tick: the lo nibbles
        sta VIMIRQ
a       lda #0                  ; (patched: A; snd_lo's too)
        rti
no      lda a+1                 ; not timer 1: the OS's (both handlers')
        jmp (old_iir)
.endp

.proc snd_lo
go      sta snd_hi.a+1          ; (VIMIRQ: the entry)
        lda IRQST
        lsr
        bcs snd_hi.no
m0      lda #0                  ; (patched: as snd_hi's)
        sta IRQEN
m1      lda #0
        sta IRQEN
        .rept SND_NV, #
lb%%1   jmp lt                  ; (live: inc snd_hi.hp%%1+1, the next byte;
                                ;  idle: jmp the next live block or lt, snd_link)
        beq lg%%1               ; a page (out of line)
lk%%1   inc snd_cl+%%1          ; -(bytes left) += 1; 0: its hi byte
        beq lz%%1
lv%%1   lda #0                  ; (patched by snd_hi: the byte)
        and #$0F
        ora #$10                ; volume only
        sta AUDC1+2*%%1
ln%%1
        .endr
lt      lda #<snd_hi.go         ; next tick: the bytes' hi nibbles
        sta VIMIRQ
        lda snd_hi.a+1          ; A back
        rti
        .rept SND_NV, #
lg%%1   lda #%%1                ; the page: snd_pg, then on at lk
        jmp snd_pg
lz%%1   lda #%%1                ; the count's hi byte: snd_cz, then lv / the end
        jmp snd_cz
        .endr
.endp
        ert >snd_lo.go<>>snd_hi.go      ; VIMIRQ switches only its lo byte
        ert *>dp_c0                     ; (triggers' door panels from $0700)
snd_lo_end = *                          ; (blood.asm: bl_shell after it)
        org snd_save

SND_HB  = snd_hi.hb1-snd_hi.hb0 ; the blocks (snd_hbo / snd_lbo)
SND_LB  = snd_lo.lb1-snd_lo.lb0
        ert snd_hi.hb2-snd_hi.hb1<>SND_HB
        ert snd_hi.hb3-snd_hi.hb2<>SND_HB
        ert snd_lo.lb2-snd_lo.lb1<>SND_LB
        ert snd_lo.lb3-snd_lo.lb2<>SND_LB

; per voice (X = 0..3)
snd_hbo dta 0, SND_HB, 2*SND_HB, 3*SND_HB       ; its hi block's offset
snd_lbo dta 0, SND_LB, 2*SND_LB, 3*SND_LB       ; its lo block's offset
snd_bk  dta 0, 0, 0, 0          ; MEMAC-B: enable + its sample's bank
snd_cl  dta 0, 0, 0, 0          ; -(bytes left): counts up to 0
snd_ch  dta 0, 0, 0, 0

old_iir         dta a(0)
snd_enabled     dta 1
snd_nact        dta 0           ; live voices (the last one stops timer 1)

; The IRQ's rare paths (below the MEMAC-B window: sound.asm is first at
; $2000). They keep X, Y; A = the voice; back into snd_lo at the voice's lk
; (snd_pg), lv or ln (snd_cz).

; SND_PG - the voice's pointer ran into the next page (past $7FFF: the next
; 16K bank)
.proc snd_pg
        stx snd_cz.xs+1
        sty snd_cz.ys+1
        sta ?v+1
        tax
        lda snd_hbo,x
        tax
        inc snd_hi.hp0+2,x
        lda snd_hi.hp0+2,x
        bpl ?c                  ; (< $80)
        lda #$40
        sta snd_hi.hp0+2,x
?v      ldx #0                  ; (patched: the voice)
        inc snd_bk,x
?c      ldx ?v+1
        lda #<snd_lo.lk0
        ldy #>snd_lo.lk0
        bne snd_cz.go           ; (always: >lk0 <> 0)
.endp

; SND_CZ - the count's lo byte ran out: its hi byte; at 0 the sample is
; over: the voice idle, the last one stops timer 1
.proc snd_cz
        stx xs+1
        sty ys+1
        tax
        inc snd_ch,x
        bne ?on
        jsr snd_idle            ; keeps X
        jsr snd_link            ; keeps X
        dec snd_nact
        bne ?n
        lda POKMSK              ; no voice left: timer 1 off
        and #$FE
        sta POKMSK
        sta IRQEN
?n      lda #<snd_lo.ln0
        ldy #>snd_lo.ln0
        bne go                  ; (always)
?on     lda #<snd_lo.lv0
        ldy #>snd_lo.lv0
go      clc                     ; Y:A + the voice's lo block offset
        adc snd_lbo,x
        sta ?j+1
        tya
        adc #0
        sta ?j+2
xs      ldx #0                  ; (patched: X)
ys      ldy #0                  ; (patched: Y)
?j      jmp $FFFF               ; (patched)
.endp

; SND_IDLE - voice X idle: both its blocks a jmp (snd_link: where), silence.
; Keeps X. (Its jmps' operands are stale until snd_link: no tick between.)
.proc snd_idle
        lda #$4C                ; jmp
        ldy snd_hbo,x
        sta snd_hi.hb0,y
        ldy snd_lbo,x
        sta snd_lo.lb0,y
        txa                     ; its AUDC: AUDC1 + 2 * voice
        asl
        ora #<AUDC1
        sta ?s+1
        lda #0
?s      sta AUDC1               ; (patched)
        rts
.endp

; SND_LINK - each idle block's jmp to the next live block (or the handler's
; tail): a tick jumps once past a run of idle voices, none after the last
; live one (snd_play fills the voices from 0). Keeps X.
.proc snd_link
        stx ?x+1
        lda #<snd_hi.ht         ; past the last voice: the tails
        sta ?th
        lda #>snd_hi.ht
        sta ?th+1
        lda #<snd_lo.lt
        sta ?tl
        lda #>snd_lo.lt
        sta ?tl+1
        ldx #SND_NV-1
?v      ldy snd_hbo,x
        lda snd_hi.hb0,y
        cmp #$4C
        bne ?live
        lda ?th                 ; idle: on to the next live block
        sta snd_hi.hb0+1,y
        lda ?th+1
        sta snd_hi.hb0+2,y
        ldy snd_lbo,x
        lda ?tl
        sta snd_lo.lb0+1,y
        lda ?tl+1
        sta snd_lo.lb0+2,y
        bne ?n                  ; (always: a handler address' high byte)
?live   tya                     ; live: the target for the idle ones before it
        clc
        adc #<snd_hi.hb0
        sta ?th
        lda #>snd_hi.hb0
        adc #0
        sta ?th+1
        lda snd_lbo,x
        clc
        adc #<snd_lo.lb0
        sta ?tl
        lda #>snd_lo.lb0
        adc #0
        sta ?tl+1
?n      dex
        bpl ?v
?x      ldx #0                  ; (patched: X)
        rts
?th     dta 0,0
?tl     dta 0,0
.endp
        ert *>$4000                     ; below the MEMAC-B window
        ert <AUDC1<>1

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

        lda #0                  ; (the IRQ is not hooked yet: order of the
        sta AUDCTL              ;  RAM stores is free; AUDF1 after them)
        sta snd_lock
        sta VBXE_MEMAC_B

        lda #15
        sta AUDF1

        ; Hook VIMIRQ for Timer 1 + chain to OS
        sei
        lda VIMIRQ
        sta old_iir
        lda VIMIRQ+1
        sta old_iir+1
        lda #<snd_hi.go
        sta VIMIRQ
        lda #>snd_hi.go
        sta VIMIRQ+1
        cli
.endp
        ert *<>snd_stop         ; falls into snd_stop: every voice idle

; ============================================
; SND_STOP - every voice idle and silent, timer 1 off (SIO: it uses the
; POKEY timers; the menus). The next sound starts on a hi tick.
; ============================================
.proc snd_stop
        lda POKMSK
        and #$FE
        sta POKMSK
        sta IRQEN
        ldx #SND_NV-1
?l      jsr snd_idle
        dex
        bpl ?l
        sta snd_nact            ; (A = 0: snd_idle's)
        lda #<snd_hi.go
        sta VIMIRQ
        jmp snd_link            ; every jmp to the tails
.endp

; ============================================
; PLAY_SFX - A = sfx (snd_play). Keeps X.
; ============================================
.proc play_sfx
        stx zt2
        tax
        jsr snd_play
        ldx zt2
        rts
.endp

; ============================================
; SND_PLAY - X = sfx: a free voice plays it, else the one nearest its end
; (doom snd_alloc: the largest -(bytes left)). Keeps X; ends Y = 0 (callers
; had it).
; ============================================
.proc snd_play
        lda snd_enabled
        bne ?go
        tay                     ; (A = 0)
        rts
?go     stx ?sx+1
        ldx #0                  ; the lowest idle voice (snd_link: the live
?f      ldy snd_hbo,x           ; ones first, no jmp after them); idle: its
        lda snd_hi.hb0,y        ; hi block starts with a jmp
        cmp #$4C
        beq ?new
        inx
        cpx #SND_NV
        bcc ?f
        ldx #SND_NV-1           ; all busy: the nearest its end
        stx ?bi+1
        lda snd_ch,x
        sta ?t
?s      dex
        bmi ?bi
        lda snd_ch,x
        cmp ?t
        bcc ?s
        sta ?t
        stx ?bi+1
        bcs ?s                  ; (always)
?bi     ldx #0                  ; (patched: the voice)
        sei
        jmp ?set                ; a live voice: snd_nact stays
?new    sei
        inc snd_nact
?set    lda snd_hbo,x           ; its pointer's operand: snd_hi.hp + 1
        clc
        adc #<[snd_hi.hp0+1]
        sta ?p0+1
        sta ?p1+1
        lda #>[snd_hi.hp0+1]
        adc #0
        sta ?p0+2
        sta ?p1+2
        inc ?p1+1               ; +1: the pointer's hi byte
        bne ?sx
        inc ?p1+2
?sx     ldy #0                  ; (patched: Y = the sfx)
        lda sfx_vbank,y         ; the sample's first byte and bank
        sta snd_bk,x
        lda sfx_vptr_lo,y
?p0     sta $FFFF               ; (patched: snd_hi.hp + 1)
        lda sfx_vptr_hi,y
?p1     sta $FFFF               ; (patched: snd_hi.hp + 2)
        ; -(bytes to play) = linear(start) - linear(end); a 16K bank is $40
        ; in the high byte (samples < 64 KB): the IRQ counts up to 0
        ; (6502-idioms "Count to zero")
        lda sfx_vptr_lo,y
        sec
        sbc sfx_vend_lo,y
        sta snd_cl,x
        lda sfx_vptr_hi,y
        sbc sfx_vend_hi,y
        sta ?t
        lda sfx_vbank_end,y
        sec
        sbc sfx_vbank,y         ; bank difference 0..3
        asl
        asl
        asl
        asl
        asl
        asl                     ; * $40
        eor #$FF                ; hi - A = hi + ~A + 1
        sec
        adc ?t
        sta snd_ch,x
        ; live: snd_hi's block lda snd_bk+voice, snd_lo's inc its pointer
        ldy snd_hbo,x
        lda #$AD                ; lda abs
        sta snd_hi.hb0,y
        txa
        clc
        adc #<snd_bk
        sta snd_hi.hb0+1,y
        lda #>snd_bk
        adc #0
        sta snd_hi.hb0+2,y
        lda ?p0+1               ; snd_lo: inc snd_hi.hp + 1
        pha
        lda ?p0+2
        ldy snd_lbo,x
        sta snd_lo.lb0+2,y
        pla
        sta snd_lo.lb0+1,y
        lda #$EE                ; inc abs
        sta snd_lo.lb0,y
        lda VIMIRQ              ; a lo tick next: the voice starts one byte
        cmp #<snd_lo.go         ; early (its lo tick steps onto the first),
        bne ?arm                ; a mid nibble
        lda #8
        sta snd_lo.lv0+1,y
        ldy ?sx+1
        lda sfx_vptr_lo,y
        bne ?d
        lda ?p1+1               ; (a page back: snd_lo's step comes back;
        sta ?d2+1               ; $3FFF: the bank's $4000 again, bpl in snd_pg)
        lda ?p1+2
        sta ?d2+2
?d2     dec $FFFF               ; (patched: snd_hi.hp + 2)
?d      lda ?p0+1
        sta ?d1+1
        lda ?p0+2
        sta ?d1+2
?d1     dec $FFFF               ; (patched: snd_hi.hp + 1)
        lda snd_cl,x            ; one byte more to count
        bne ?c
        dec snd_ch,x
?c      dec snd_cl,x
?arm    jsr snd_link            ; the idle jmps past it (keeps X)
        lda POKMSK              ; timer 1 already on: left alone (STIMER
        lsr                     ; would bend the live voices' tick)
        bcs ?on
        lda POKMSK
        ora #$01
        sta POKMSK
        sta IRQEN
        sta snd_lo.m1+1         ; the IRQ acknowledges with constants
        sta snd_hi.m1+1         ; (6502-loops-tables-smc: variables as
        sta STIMER              ; immediate operands)
        and #$FE
        sta snd_lo.m0+1
        sta snd_hi.m0+1
?on     cli
        ldx ?sx+1
        ldy #0
        rts
?t      dta 0
.endp

; ============================================
; SOUND UPDATE - the saw's retrigger lock runs down (player.asm)
; ============================================
.proc sound_update
        lda snd_lock
        beq ?r
        dec snd_lock
?r      rts
.endp


; ============================================
; PLAY ENEMY DEATH SOUND
; ============================================
.proc play_enemy_death
        ldy en_type,x
        lda en_death_sfx,y
        cmp #$FF
        beq ?skip
        stx zt2
        ; Pick sound (random for zombie/shotgun); Y = en_type, A = its sfx
        cpy #EN_ZOMBIE
        beq ?rnd_podth
        cpy #EN_SHOTGUN
        bne ?got_sfx
?rnd_podth
        lda zfr                 ; random 0..3 -> PODEATH 1,2,3,1 (3 counts as 0)
        eor RTCLOK3
        and #$03
        tay
        lda ?pd_tab,y
?got_sfx
        tax
        jsr snd_play
        ldx zt2
?skip   rts
?pd_tab dta SFX_PODEATH,SFX_PODEATH2,SFX_PODEATH3,SFX_PODEATH
.endp

; ============================================
; PLAY ENEMY SIGHT SOUND
; ============================================
.proc play_enemy_sight
        ldy en_type,x
        lda en_sight_sfx,y
        cmp #$FF
        beq ?skip
        stx zt2
        ; Y = en_type, A = its sfx
        cpy #EN_ZOMBIE
        beq ?rnd_posit
        cpy #EN_SHOTGUN
        beq ?rnd_posit
        cpy #EN_IMP
        bne ?play
        lda zfr                 ; imp: random 0..1 -> table entries 4..5
        eor RTCLOK3
        and #$01
        ora #4
        bne ?rnd                ; (always: A >= 4)
?rnd_posit
        lda zfr                 ; random 0..3 -> POSIGHT 1,2,3,1 (3 counts as 0)
        eor RTCLOK3
        and #$03
?rnd    tay
        lda ?si_tab,y
?play   tax
        jsr snd_play
        ldx zt2
?skip   rts
?si_tab dta SFX_POSIGHT,SFX_POSIGHT2,SFX_POSIGHT3,SFX_POSIGHT
        dta SFX_IMPSIGHT,SFX_IMPSIT2
.endp

; ============================================
; VRAM SOUND ADDRESS TABLES (auto-generated)
; ============================================
        icl 'gen/sound_tables.asm'
