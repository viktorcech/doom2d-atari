;==============================================
; DOOM2D - HUD rendering (HP, Ammo)
; hud.asm
;==============================================

; HUD digit storage (NOT in zero page - zt/zt2 get clobbered by calc_dst)
hd_d0   dta 0                   ; ones digit
hd_d1   dta 0                   ; tens digit
hd_d2   dta 0                   ; hundreds digit

; ============================================
; NUM TO DIGITS: A (0-255) -> hd_d2/hd_d1/hd_d0
; ============================================
.proc num_to_digits
        ldx #0
?s      cmp #100
        bcc ?t
        sbc #100                ; carry already set from bcc
        inx
        bne ?s
?t      stx hd_d2
        ldx #0
?d      cmp #10
        bcc ?j
        sbc #10
        inx
        bne ?d
?j      stx hd_d1
        sta hd_d0
        rts
.endp

; ============================================
; BLIT HUD CHAR 8x8 (transparent)
; Input: A = char index (0-11), zdx/zdxh = X, zdy = Y
; Source: VRAM $019000 + char*64
; ============================================
.proc blit_hud_char
        ; Calculate source: $019000 + A*64
        ; A*64: shift left 6 = high nybble is A>>2, low byte is (A&3)<<6
        sta hc_idx
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL

        ; src_lo = (idx & 3) << 6
        lda hc_idx
        and #$03
        asl
        asl
        asl
        asl
        asl
        asl
        sta MEMW+[VRAM_BCB&$FFF]+0     ; src addr low

        ; src_mid = (HUD_FONT_ADDR>>8) + (idx >> 2)
        lda hc_idx
        lsr
        lsr
        clc
        adc #>HUD_FONT_ADDR             ; base within bank
        sta MEMW+[VRAM_BCB&$FFF]+1      ; src addr mid

        lda #$01                        ; bank $01 ($01xxxx)
        sta MEMW+[VRAM_BCB&$FFF]+2      ; src addr high

        ; src step = 8 (width)
        lda #HUD_CHAR_W
        sta MEMW+[VRAM_BCB&$FFF]+3
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+4
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+5

        ; dst = calc_dst (uses zdx, zdxh, zdy, zbuf_hi)
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        ; dst step [9-11], AND [15], XOR [16-19] pre-filled
        ; size 8x8
        lda #HUD_CHAR_W-1
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #HUD_CHAR_H-1
        sta MEMW+[VRAM_BCB&$FFF]+14
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+20     ; mode=0 (opaque)
        jsr run_blit
        rts
hc_idx  dta 0
.endp

; HUD cache (previous frame values)
hud_prev_hp   dta $FF         ; force redraw on first frame
hud_prev_ammo dta $FF
hud_prev_weap dta $FF
hud_prev_keys dta $FF
hud_prev_armor dta $FF
hud_frames    dta 2           ; frames left to draw (2 = both buffers)
hud_full_clear dta 2          ; >0 = clear armor/keys areas (2 = both buffers) [RESTART-TEMP]

; ============================================
; HUD HELPER: draw char A at X position given in hud_xpos
; zdy must be set before calling
; ============================================
.proc hud_char_at
        pha             ; save char index
        ldx hud_xpos
        stx zdx
        lda #0
        sta zdxh
        pla             ; restore char index
        jsr blit_hud_char
        rts
.endp
hud_xpos dta 0

; ============================================
; HUD HELPER: draw 3 digits (hd_d2/d1/d0) at X position in A
; zdy must be set before calling
; ============================================
.proc hud_draw_3dig
        sta hud_xpos
        lda hd_d2
        jsr hud_char_at
        lda hud_xpos
        clc
        adc #8
        sta hud_xpos
        lda hd_d1
        jsr hud_char_at
        lda hud_xpos
        clc
        adc #8
        sta hud_xpos
        lda hd_d0
        jsr hud_char_at
        rts
.endp

; ============================================
; HUD HELPER: clear 24x8 area at X position in A (3 char slots)
; zdy must be set before calling
; ============================================
.proc hud_clear_3slots
        sta zdx
        lda #0
        sta zdxh
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #$00
        sta MEMW+[VRAM_BCB&$FFF]+0
        lda #$FA
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda #$00
        sta MEMW+[VRAM_BCB&$FFF]+2
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+3
        sta MEMW+[VRAM_BCB&$FFF]+4
        sta MEMW+[VRAM_BCB&$FFF]+5
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        lda #23                 ; 24px wide (3 chars)
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #7
        sta MEMW+[VRAM_BCB&$FFF]+14  ; height-1 = 7
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND=0 → black
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode=0
        jsr run_blit
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15  ; restore AND
        rts
.endp

; ============================================
; RENDER HUD (only redraws changed elements)
; ============================================
.proc render_hud
        ; Check if anything changed
        lda zphp
        cmp hud_prev_hp
        bne ?changed
        jsr get_cur_ammo
        cmp hud_prev_ammo
        bne ?changed
        lda zpwcur
        cmp hud_prev_weap
        bne ?changed
        lda zpkeys
        cmp hud_prev_keys
        bne ?changed
        lda zparmor
        cmp hud_prev_armor
        bne ?changed
        ; Nothing changed - still need to draw for both buffers?
        lda hud_frames
        beq ?skip
        dec hud_frames
        jmp ?draw
?skip   rts
?changed
        lda zphp
        sta hud_prev_hp
        jsr get_cur_ammo
        sta hud_prev_ammo
        lda zpwcur
        sta hud_prev_weap
        lda zpkeys
        sta hud_prev_keys
        lda zparmor
        sta hud_prev_armor
        lda #1
        sta hud_frames

?draw   lda #HUD_Y
        sta zdy

        ; --- Heart icon + HP ---
        lda #HUD_HP_IX
        sta hud_xpos
        lda #HUD_CHR_HEART
        jsr hud_char_at
        lda zphp
        jsr num_to_digits
        lda #HUD_HP_DX
        jsr hud_draw_3dig

        ; --- Armor ---
        lda #HUD_Y
        sta zdy
        lda #56
        jsr hud_clear_3slots
        lda zparmor
        beq ?no_armor
        lda #HUD_Y
        sta zdy
        lda zparmor
        jsr num_to_digits
        lda #56
        jsr hud_draw_3dig
?no_armor
        lda #HUD_Y
        sta zdy

        ; --- Bullet icon + ammo (skip for fist) ---
        ldx zpwcur
        lda weap_ammotype,x
        cmp #AMMO_NONE
        bne ?show_ammo
        ; Fist: clear ammo area
        lda #HUD_AM_IX
        jsr hud_clear_3slots
        lda #HUD_AM_DX
        jsr hud_clear_3slots
        jmp ?ammo_done
?show_ammo
        lda #HUD_Y
        sta zdy
        lda #HUD_AM_IX
        sta hud_xpos
        lda #HUD_CHR_BULLET
        jsr hud_char_at
        jsr get_cur_ammo
        jsr num_to_digits
        lda #HUD_AM_DX
        jsr hud_draw_3dig
?ammo_done

        ; --- Weapon number ---
        lda #HUD_WP_DX
        sta hud_xpos
        lda zpwcur
        clc
        adc #1
        jsr hud_char_at

        ; --- Weapon sprite (16x16, above HUD) ---
        lda #[HUD_WP_DX+10]
        sta zdx
        lda #0
        sta zdxh
        lda #HUD_Y
        sta zdy
        jsr hud_clear_icon
        lda #[HUD_WP_DX+10]
        sta zdx
        lda #0
        sta zdxh
        lda #[HUD_Y-8]
        sta zdy
        ldx zpwcur
        lda weap_hud_spr,x
        jsr blit_sprite

        ; --- Key icons ---
        lda hud_full_clear
        beq ?no_kclear
        lda #HUD_Y
        sta zdy
        lda #HUD_KEY_DX
        jsr hud_clear_3slots
        dec hud_full_clear
?no_kclear
        lda zpkeys
        and #$01
        beq ?no_red
        lda #HUD_KEY_DX
        sta zdx
        lda #0
        sta zdxh
        lda #[HUD_Y-8]
        sta zdy
        lda #SPR_KEYRED
        jsr blit_sprite
?no_red
        lda zpkeys
        and #$02
        beq ?no_blue
        lda #[HUD_KEY_DX+16]
        sta zdx
        lda #0
        sta zdxh
        lda #[HUD_Y-8]
        sta zdy
        lda #SPR_KEYBLUE
        jsr blit_sprite
?no_blue
        lda zpkeys
        and #$04
        beq ?no_yellow
        lda #[HUD_KEY_DX+32]
        sta zdx
        lda #0
        sta zdxh
        lda #[HUD_Y-8]
        sta zdy
        lda #SPR_KEYYELLOW
        jsr blit_sprite
?no_yellow
        rts
.endp

; ============================================
; CLEAR 16x16 AREA (black fill at zdx/zdy)
; Uses blitter AND=0 to force all pixels black
; ============================================
.proc hud_clear_icon
        jsr wait_blit
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        ; src = $00FA00 (known zeros)
        lda #$00
        sta MEMW+[VRAM_BCB&$FFF]+0
        lda #$FA
        sta MEMW+[VRAM_BCB&$FFF]+1
        lda #$00
        sta MEMW+[VRAM_BCB&$FFF]+2
        ; src step = 0
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+3
        sta MEMW+[VRAM_BCB&$FFF]+4
        sta MEMW+[VRAM_BCB&$FFF]+5
        ; dst
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        ; dst step [9-11] pre-filled
        ; size 16x8
        lda #15
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #7
        sta MEMW+[VRAM_BCB&$FFF]+14  ; height-1 = 7
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND=0 → black
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode=0
        jsr run_blit
        ; Restore AND=$FF for next blit
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15
        rts
.endp


; ============================================
; CLEAR HUD AREA (320x8 at Y=192, fill black)
; Uses current zbuf_hi for buffer selection
; ============================================
.proc clear_hud_area
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+0
        sta MEMW+[VRAM_BCB&$FFF]+1
        sta MEMW+[VRAM_BCB&$FFF]+2
        sta MEMW+[VRAM_BCB&$FFF]+3   ; src step = 0
        sta MEMW+[VRAM_BCB&$FFF]+4
        sta MEMW+[VRAM_BCB&$FFF]+5
        sta MEMW+[VRAM_BCB&$FFF]+15  ; AND = 0
        sta MEMW+[VRAM_BCB&$FFF]+16  ; XOR = 0
        sta MEMW+[VRAM_BCB&$FFF]+17
        sta MEMW+[VRAM_BCB&$FFF]+18
        sta MEMW+[VRAM_BCB&$FFF]+19
        sta MEMW+[VRAM_BCB&$FFF]+20  ; mode 0 (fill)
        ; dst step = 320 (must set BEFORE blit!)
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11
        lda #0
        sta zdx
        sta zdxh
        lda #HUD_Y
        sta zdy
        jsr calc_dst
        lda zva
        sta MEMW+[VRAM_BCB&$FFF]+6
        lda zva+1
        sta MEMW+[VRAM_BCB&$FFF]+7
        lda zva+2
        sta MEMW+[VRAM_BCB&$FFF]+8
        lda #<[SCR_W-1]
        sta MEMW+[VRAM_BCB&$FFF]+12
        lda #>[SCR_W-1]
        sta MEMW+[VRAM_BCB&$FFF]+13
        lda #7                  ; 8 rows
        sta MEMW+[VRAM_BCB&$FFF]+14
        jsr run_blit
        jsr wait_blit
        ; Restore normal BCB state
        lda #BANK_EN+BANK_BCB
        sta VBXE_BANK_SEL
        lda #<SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+9
        lda #>SCR_W
        sta MEMW+[VRAM_BCB&$FFF]+10
        lda #1
        sta MEMW+[VRAM_BCB&$FFF]+11
        lda #$FF
        sta MEMW+[VRAM_BCB&$FFF]+15
        lda #0
        sta MEMW+[VRAM_BCB&$FFF]+16
        lda #BLT_TRANS
        sta MEMW+[VRAM_BCB&$FFF]+20
        rts
.endp

; ============================================
; 2026-04-08: SHOW LEVEL STATS
; Black screen with KILLS: X/Y and TIME: MM:SS
; Waits for fire button, then returns.
; ============================================

; Char indices: 0-9 = digits, 10 = heart, 11 = bullet, 12+ = A(12)..Z(37)
CH_A = 12
CH_SLASH = 11                   ; reuse bullet char as separator

.proc show_level_stats
        ; Clear screen to black
        jsr wait_blit
        jsr clear_full_black

        ; --- Draw "LEVEL X" centered at Y=48 ---
        lda #48
        sta zdy
        lda #0
        sta zdxh
        ; L E V E L
        lda #56
        sta zdx
        lda #CH_A+11            ; L
        jsr blit_hud_char
        lda #64
        sta zdx
        lda #CH_A+4             ; E
        jsr blit_hud_char
        lda #72
        sta zdx
        lda #CH_A+21            ; V
        jsr blit_hud_char
        lda #80
        sta zdx
        lda #CH_A+4             ; E
        jsr blit_hud_char
        lda #88
        sta zdx
        lda #CH_A+11            ; L
        jsr blit_hud_char
        ; Level number (current_level + 1, 1-based)
        lda #104
        sta zdx
        lda current_level
        clc
        adc #1                  ; 0-based → 1-based
        jsr num_to_digits
        lda hd_d0
        jsr blit_hud_char

        ; --- Draw "KILLS" at Y=72 ---
        lda #72
        sta zdy
        lda #0
        sta zdxh

        lda #56                 ; X = 56
        sta zdx
        lda #CH_A+10            ; K
        jsr blit_hud_char
        lda #64
        sta zdx
        lda #CH_A+8             ; I
        jsr blit_hud_char
        lda #72
        sta zdx
        lda #CH_A+11            ; L
        jsr blit_hud_char
        lda #80
        sta zdx
        lda #CH_A+11            ; L
        jsr blit_hud_char
        lda #88
        sta zdx
        lda #CH_A+18            ; S
        jsr blit_hud_char

        ; Draw kills count: stat_kills
        lda #104
        sta zdx
        lda stat_kills
        jsr num_to_digits
        ; Skip leading zeros for tens
        lda hd_d2
        beq ?no_h
        jsr blit_hud_char       ; hundreds
        lda #112
        sta zdx
?no_h   lda hd_d1
        ora hd_d2
        beq ?no_t
        lda #112
        sta zdx
        lda hd_d1
        jsr blit_hud_char       ; tens
?no_t   lda #120
        sta zdx
        lda hd_d0
        jsr blit_hud_char       ; ones

        ; Draw "/" separator
        lda #128
        sta zdx
        lda #CH_SLASH
        jsr blit_hud_char

        ; Draw total: stat_total_en
        lda stat_total_en
        jsr num_to_digits
        lda #136
        sta zdx
        lda hd_d1
        ora hd_d2
        beq ?no_tt
        lda hd_d2
        beq ?no_th
        jsr blit_hud_char
        lda #144
        sta zdx
?no_th  lda hd_d1
        jsr blit_hud_char
?no_tt  lda #144
        sta zdx
        lda hd_d0
        jsr blit_hud_char

        ; --- Draw "TIME" at row 8 ---
        lda #96                 ; Y = 96
        sta zdy

        lda #56
        sta zdx
        lda #CH_A+19            ; T
        jsr blit_hud_char
        lda #64
        sta zdx
        lda #CH_A+8             ; I
        jsr blit_hud_char
        lda #72
        sta zdx
        lda #CH_A+12            ; M
        jsr blit_hud_char
        lda #80
        sta zdx
        lda #CH_A+4             ; E
        jsr blit_hud_char

        ; Calculate minutes and seconds from 16-bit time (stat_time_hi:stat_time_lo)
        ; Repeated subtraction: divide by 60 to get minutes, remainder = seconds
        lda stat_time_lo
        sta sl_secs             ; sl_secs = working lo byte
        lda stat_time_hi
        sta sl_mins             ; sl_mins = working hi byte (reused as temp)
        ldx #0                  ; X = minutes counter
?div60  lda sl_mins             ; hi byte
        bne ?sub60              ; if hi > 0, definitely >= 60
        lda sl_secs             ; hi == 0, check lo
        cmp #60
        bcc ?got_min            ; < 60, done
?sub60  lda sl_secs
        sec
        sbc #60
        sta sl_secs
        lda sl_mins
        sbc #0
        sta sl_mins
        inx
        cpx #100                ; cap at 99 minutes (safety)
        bcc ?div60
?got_min
        lda sl_secs             ; remainder = seconds (0-59)
        sta sl_secs
        stx sl_mins             ; quotient = minutes

        ; Draw MM:SS
        lda #104
        sta zdx
        lda sl_mins
        jsr num_to_digits
        lda hd_d1
        jsr blit_hud_char       ; minutes tens
        lda #112
        sta zdx
        lda hd_d0
        jsr blit_hud_char       ; minutes ones

        ; Colon (:) — no colon char, skip 8px gap
        lda #128
        sta zdx
        lda sl_secs
        jsr num_to_digits
        lda hd_d1
        jsr blit_hud_char       ; seconds tens
        lda #136
        sta zdx
        lda hd_d0
        jsr blit_hud_char       ; seconds ones

        ; Show on screen (swap to display this buffer)
        jsr wait_blit
        lda #BANK_EN+BANK_XDL
        sta VBXE_BANK_SEL
        lda zbuf_hi
        sta MEMW+[VRAM_XDL&$FFF]+8

        ; Wait for fire release (TRIG0: 0=pressed, 1=released)
?rel    lda TRIG0
        beq ?rel                ; wait while pressed
        ; Wait for fire press
?wait   lda TRIG0
        bne ?wait               ; wait while released
        rts

sl_mins dta 0
sl_secs dta 0
.endp
