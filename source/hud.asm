;==============================================
; DOOM2D - HUD rendering (HP, Ammo)
; hud.asm
;==============================================

; HUD digit storage (NOT in zero page - zt/zt2 get clobbered by calc_dst)
hd_d0   dta 0                   ; ones digit
hd_d1   dta 0                   ; tens digit
hd_d2   dta 0                   ; hundreds digit

; ============================================
; NUM TO DIGITS: A (0-255), or num16_digits: A lo / Y hi (< 1000)
; ============================================
; Exit: A = ones digit, X = tens digit, C=1, Y=$FF. A borrow with Y >= 0 is
; a hi-byte step; the final one leaves C=0 and the adc undoes it (C=1 out).
.proc num_to_digits
        ldy #0
.endp
        ert *<>num16_digits
.proc num16_digits
        ldx #$FF
?s      sec
?h      inx
        sbc #100
        bcs ?h
        dey
        bpl ?s
        adc #100
        stx hd_d2
        ldx #$FF
?d      inx
        sbc #10
        bcs ?d
        adc #10
        stx hd_d1
        sta hd_d0
        rts
.endp

; ============================================
; BLIT HUD CHAR 8x8 (transparent)
; Input: A = char index (0-41: digits, icons, A-Z, : . -), zdx/zdxh = X, zdy = Y
; Source: VRAM $019000 + char*64 (precomputed LUT, replaces 8 shifts)
; Clobbers Y (calc_dst does anyway); X preserved.
; ============================================
NUM_HUD_CHARS = 44             ; + 38 a block, 39 :, 40 ., 41 -, 42 /, 43 ! (prepare_hud_font.py)
hudch_src_lo                            ; (idx & 3) * 64
        :NUM_HUD_CHARS dta [[#&3]*64]
hudch_src_mid                           ; >HUD_FONT_ADDR + idx/4
        :NUM_HUD_CHARS dta [>HUD_FONT_ADDR]+[#/4]

; MENU_CHAR - blit_hud_char drawn at once (menus, save slots: no frame
; list runs there). Keeps X.
.proc menu_char
        stx ?x+1
        pha
        jsr ls_stamp            ; the slots' bank: menus flip zbuf_hi themselves
        pla
?x      ldx #0                  ; (patched)
        jsr blit_hud_char
        jmp spl_flush
.endp

; ============================================
; HUD HELPER: draw char A at X position X; zdy must be set. Exit X = the
; position (blit_hud_char preserves X); falls into blit_hud_char.
; ============================================
.proc hud_char_x
        stx zdx
        ldy #0
        sty zdxh
.endp
        ert *<>blit_hud_char

; BLIT_HUD_CHAR - char A at zdx/zdxh, zdy: an opaque 8x8 copy appended to
; the sprite list (the frame's one list; no wait, no START). Keeps X.
.proc blit_hud_char
        tay                             ; Y = char index
        jsr spl_room                    ; C=1: the list is full (skipped)
        bcs ?r
        lda hudch_src_mid,y
        pha
        lda hudch_src_lo,y
        ldy #0
        sta (spl_ptr),y                 ; +0 src
        pla
        iny
        sta (spl_ptr),y                 ; +1
        lda #$01                        ; bank $01 ($01xxxx)
        iny
        sta (spl_ptr),y                 ; +2
        lda #HUD_CHAR_W
        iny
        sta (spl_ptr),y                 ; +3 src step = 8 (+4 0: template)
        lda #1
        ldy #5
        sta (spl_ptr),y                 ; +5 src step x
        ldy zdy                         ; dst = y_addr[zdy] + zdx + buffer
        lda y_addr_lo,y
        clc
        adc zdx
        ldy #6
        sta (spl_ptr),y                 ; +6
        ldy zdy                         ; (ldy keeps C)
        lda y_addr_hi,y
        adc zdxh
        ldy #7
        sta (spl_ptr),y                 ; +7
        lda #HUD_CHAR_W-1
        ldy #12
        sta (spl_ptr),y                 ; +12 (+13 0: template)
        lda #HUD_CHAR_H-1
        ldy #14
        sta (spl_ptr),y                 ; +14
md      lda #$08                        ; MODE 0 (opaque) + NEXT (msg_frame:
        jmp spl_end                     ; BLT_TRANS while it draws)
?r      rts
.endp

; HUD cache (previous frame values)
hud_prev_hp   dta $FF         ; force redraw on first frame
hud_prev_ammo dta $FF
hud_prev_amhi dta $FF
hud_prev_weap dta $FF
hud_prev_armor dta $FF
hud_frames    dta 2           ; frames left to draw (2 = both buffers)
hud_full_clear dta 2          ; >0 = clear armor/keys areas (2 = both buffers) [RESTART-TEMP]

; ============================================
; HUD HELPER: draw 3 digits (hd_d2/d1/d0) at X position in A
; zdy must be set before calling. hud_xpos is the digit counter. Exit X = A+24.
; ============================================
hud_xpos dta 0
.proc hud_draw_3dig
        tax
        lda #2                  ; hd_d2, hd_d1, hd_d0 (adjacent, hd_d0 first)
        sta hud_xpos
?dig    ldy hud_xpos
        lda hd_d0,y
        jsr hud_char_x
        txa                     ; X = position (blit_hud_char preserves X)
        clc
        adc #8
        tax
        dec hud_xpos
        bpl ?dig
        rts
.endp
        ert hd_d1<>hd_d0+1 || hd_d2<>hd_d0+2

; ============================================
; HUD HELPER: clear 24x8 area at X position in A (3 char slots), zdxh := 0
; zdy must be set before calling. Falls into hud_clear_icon with the width.
; ============================================
.proc hud_clear_3slots
        sta zdx
        lda #0
        sta zdxh
        ldy #23                 ; width-1: 24px (3 chars)
        dta $2C                 ; bit abs (RAM $0FA0): skips the ldy #15 below
.endp
        ert *<>hud_clear_icon

; ============================================
; CLEAR 16x8 AREA (black at zdx/zdxh/zdy), or Y+1 wide from above: a copy
; of one zero byte (HUD_ZERO, both source steps 0) appended to the sprite
; list. Preserves X.
; ============================================
.proc hud_clear_icon
        ldy #15                 ; width-1: 16px
w       lda #7                  ; entry with Y = width-1: 8 rows
        sta hgt+1
        lda #<HUD_ZERO
        ert >HUD_ZERO<>$FA
        ert ^HUD_ZERO<>0
; .SOLID - A = the low byte of a one-byte colour source ($00FAxx), Y =
; width-1, hgt+1 = height-1 (fps_comma)
solid   sty ?w+1
        sta ?s+1
        jsr spl_room            ; C=1: the list is full (skipped)
        bcs ?r
        jsr calc_dst            ; zva (keeps X)
?s      lda #0                  ; (patched: src lo; src = $00FAxx)
        ldy #0
        sta (spl_ptr),y         ; +0
        lda #$FA
        iny
        sta (spl_ptr),y         ; +1
        lda #0
        iny
        sta (spl_ptr),y         ; +2
        iny
        sta (spl_ptr),y         ; +3 src step 0 (+4 0: template)
        ldy #5
        sta (spl_ptr),y         ; +5 src step x 0: the byte over and over
        lda zva
        iny
        sta (spl_ptr),y         ; +6
        lda zva+1
        iny
        sta (spl_ptr),y         ; +7
?w      lda #0                  ; (patched: width-1)
        ldy #12
        sta (spl_ptr),y         ; +12
hgt     lda #7                  ; (patched: height-1)
        ldy #14
        sta (spl_ptr),y         ; +14
        lda #$08                ; MODE 0 (opaque) + NEXT
        jmp spl_end
?r      rts
.endp
HUD_ZERO  = $00FA00             ; a 0 past screen 0 (frame.asm lists_init writes it)
HUD_COMMA = $00FA10             ; FPS_COL (fps_comma writes it)

; ============================================
; RENDER HUD
; Two parts:
;  1) EVERY FRAME: weapon icon + key icons. They are 16px tall at Y=184-199,
;     so their top halves are inside the game area which composite_frame
;     overwrites every frame. 1-4 tiny blits, blitter does the work.
;  2) ON CHANGE: text band (Y=192-199). It persists in both buffers, so the
;     chars are cached and redrawn only when a value changes (hud_frames=2
;     covers both buffers).
; ============================================
.proc render_hud
        ; === 1) Per-frame icons ===
        ; Weapon changed? Clear the band part under the icon in both buffers
        ; (transparent blit alone would leave the old weapon's pixels there).
        ; zdx/zdxh of the weapon icon set once: hud_clear_icon (calc_dst)
        ; only reads them. blit_sprite with spr_cam=0 never writes zdx/zdxh/
        ; zdy, so zdxh stays 0 for the key icons below.
        lda #[HUD_WP_DX+10]
        sta zdx
        lda #0
        sta zdxh
        lda zpwcur
        cmp hud_prev_wspr
        beq ?same_w
        sta hud_prev_wspr
        lda #2
        sta hud_wclear
?same_w lda hud_wclear
        beq ?no_wclear
        dec hud_wclear
        lda #HUD_Y
        sta zdy
        ldy #31                 ; 32 px: the widest weapon icon
        jsr hud_clear_icon.w
?no_wclear
        ; Weapon icon (the pickup texture, <= 32 wide, bottom on the screen's
        ; last line; spr_cam=0 -> clips at SCR_H)
        ldx zpwcur
        ldy weap_hud_spr,x
        iny
        beq ?no_wicon           ; $FF: the fist has none
        dey
        lda #SCR_H
        sec
        sbc spr_h,y
        sta zdy
        tya
        jsr blit_sprite
?no_wicon
        lda #HUD_Y              ; the key icons' row (8x8, in the band)
        sta zdy

        ; Key area band clear on restart/level change (keys reset to 0,
        ; their band stubs must go; 2x 24px covers all 3 key slots)
        lda hud_full_clear
        beq ?no_kclear
        dec hud_full_clear
        lda #HUD_KEY_DX
        jsr hud_clear_3slots    ; (writes zdx, zdxh=0; never zdy)
        lda #[HUD_KEY_DX+24]
        jsr hud_clear_3slots
?no_kclear
        ; Key icons (only owned ones; zpkeys=0 -> no blits at all)
        ; zdxh = 0 and zdy = HUD_Y here on every path (see the weapon icon
        ; above; blit_sprite with spr_cam=0 never writes zdy)
        lda zpkeys
        and #$01
        beq ?no_red
        lda #HUD_KEY_DX
        sta zdx
        lda #SPR_KEYRED
        jsr blit_sprite
?no_red
        lda zpkeys
        and #$02
        beq ?no_blue
        lda #[HUD_KEY_DX+16]
        sta zdx
        lda #SPR_KEYBLUE
        jsr blit_sprite
?no_blue
        lda zpkeys
        and #$04
        beq ?no_yellow
        lda #[HUD_KEY_DX+32]
        sta zdx
        lda #SPR_KEYYELLOW
        jsr blit_sprite
?no_yellow

        ; === 2) Cached text band ===
        lda zphp
        cmp hud_prev_hp
        bne ?changed
        jsr get_cur_ammo
        lda gca_lo
        cmp hud_prev_ammo
        bne ?changed
        lda gca_hi
        cmp hud_prev_amhi
        bne ?changed
        lda zpwcur
        cmp hud_prev_weap
        bne ?changed
        lda zparmor
        cmp hud_prev_armor
        bne ?changed
        ; Nothing changed - still need to draw for both buffers?
        lda hud_frames
        beq ?skip
        dec hud_frames
        bpl ?draw               ; hud_frames <= 2 (every writer stores 1 or 2): N=0
?skip   rts
?changed
        lda zphp
        sta hud_prev_hp
        jsr get_cur_ammo
        lda gca_lo
        sta hud_prev_ammo
        lda gca_hi
        sta hud_prev_amhi
        lda zpwcur
        sta hud_prev_weap
        lda zparmor
        sta hud_prev_armor
        lda #1
        sta hud_frames

?draw   lda #HUD_Y              ; zdy stays HUD_Y below: nothing here writes it
        sta zdy

        ; --- Heart icon + HP ---
        ldx #HUD_HP_IX
        lda #HUD_CHR_HEART
        jsr hud_char_x
        lda zphp
        jsr num_to_digits
        lda #HUD_HP_DX
        jsr hud_draw_3dig

        ; --- Armor ---
        lda #56
        jsr hud_clear_3slots
        lda zparmor
        beq ?no_armor
        jsr num_to_digits       ; A = zparmor
        lda #56
        jsr hud_draw_3dig
?no_armor

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
        bmi ?ammo_done          ; N=1: hud_clear_icon ends lda #$FF / sta / rts
?show_ammo
        ldx #HUD_AM_IX
        lda #HUD_CHR_BULLET
        jsr hud_char_x
        jsr get_cur_ammo
        lda gca_lo
        ldy gca_hi
        jsr num16_digits
        lda #HUD_AM_DX
        jsr hud_draw_3dig
?ammo_done

        ; --- Weapon number ---
        ldx #HUD_WP_DX
        ldy zpwcur
        iny
        cpy #WP_SAW+1
        bne ?wn
        ldy #WP_FIST+1          ; the saw is on key 1
?wn     tya
        jmp hud_char_x          ; tail call (jsr/rts -> jmp)
.endp
hud_prev_wspr dta $FF         ; weapon whose icon is in the band ($FF = none)
hud_wclear    dta 0           ; frames left to clear icon band area (2 = both buffers)

; ============================================
; SHOW LEVEL STATS
; Black screen with KILLS: X/Y and TIME: MM:SS
; Waits for fire button, then returns.
; ============================================

; Char indices: 0-9 = digits, 10 = heart, 11 = bullet, 12+ = A(12)..Z(37)
CH_A = 12
CH_SLASH = 11                   ; reuse bullet char as separator
CH_COLON = 39
CH_DOT   = 40
CH_DASH  = 41
CH_DIV   = 42                  ; a real slash (CH_SLASH is the bullet)
CH_EXCL  = 43

; ============================================
; FPS COUNTER (key F): exact average over the last FPS_N shown frames,
; fps*10 = FPS_N * vblank_rate * 10 / vblanks_taken (rounded), shown as
; "dd,d" in the free part of the HUD band (x 124..155), on change only
; (both buffers). A new value about once a second.
; ============================================
FPS_X     = 124
FPS_COL   = 176                 ; HUD digit colour (prepare_hud_font COL_DIGIT)
FPS_N     = 64                  ; frames per measurement
fps_on    dta 0                 ; 1 = shown
fps_dirty dta 0                 ; buffers left to redraw (2 = both)
fps_last  dta 0                 ; RTCLOK3 at the previous frame
fps_cnt   dta FPS_N             ; frames left in the current measurement
fps_vb    dta 0,0               ; vblanks in the current measurement
fps_sum   dta 0,0               ; result: fps*10
fps_rem   dta 0,0               ; division remainder

; FPS_TICK - once per shown frame (main loop, after the buffer flip)
.proc fps_tick
        lda RTCLOK3
        tax
        sec
        sbc fps_last            ; vblanks since the previous frame (8-bit wrap)
        stx fps_last
        clc
        adc fps_vb
        sta fps_vb
        bcc ?v1
        inc fps_vb+1
?v1     dec fps_cnt
        beq ?calc
        rts
        ; fps*10 = (FPS_N*rate*10 + vb/2) / vb   (rate = fps_thr: 50 or 60)
?calc   ldx #0                  ; X = ?k_lo/?k_hi entry: 0 for 50, 1 for 60
        ldy fps_thr
        cpy #60
        bne ?k
        inx
?k      lda fps_vb+1            ; + vb/2: round to nearest
        lsr
        tay
        lda fps_vb
        ror
        clc
        adc ?k_lo,x
        sta fps_sum
        tya
        adc ?k_hi,x
        sta fps_sum+1
        lda #0                  ; 16/16 division: fps_sum /= fps_vb
        sta fps_rem
        sta fps_rem+1
        ldx #16
?dl     asl fps_sum
        rol fps_sum+1
        rol fps_rem
        rol fps_rem+1
        lda fps_rem
        sec
        sbc fps_vb
        tay
        lda fps_rem+1
        sbc fps_vb+1
        bcc ?ds
        sta fps_rem+1
        sty fps_rem
        inc fps_sum             ; quotient bit (bit 0 is 0 after the asl)
?ds     dex
        bne ?dl
        stx fps_vb              ; next measurement (X = 0 after the loop)
        stx fps_vb+1
        lda #FPS_N
        sta fps_cnt
        lda fps_on
        beq ?r
        lda #2
        sta fps_dirty           ; new value: redraw in both buffers
?r      rts
?k_lo   dta <[FPS_N*500], <[FPS_N*600]
?k_hi   dta >[FPS_N*500], >[FPS_N*600]
.endp

; FPS_DRAW - clear the FPS area, then (if on) draw "dd,d" from fps_sum.
; Called with fps_dirty <> 0.
.proc fps_draw
        dec fps_dirty
        lda #HUD_Y
        sta zdy
        lda #FPS_X
        jsr hud_clear_3slots    ; x 124..147 (leaves zdxh=0)
        lda #FPS_X+16
        sta zdx
        jsr hud_clear_icon      ; x 140..155
        lda fps_on
        beq ?r
        ; fps_sum (0..600) = hundreds (fps tens) + rest 0..99
        lda fps_sum
        ldx fps_sum+1
        ldy #0
?h      cpx #0
        bne ?sub                ; taken: C=1 (cpx #0)
        cmp #100
        bcc ?hd                 ; not taken: C=1
?sub    sbc #100
        bcs ?h1
        dex
?h1     iny
        bne ?h                  ; (always: Y <= 6)
?hd     tax                     ; rest
        tya
        pha                     ; tens digit of the fps value
        txa
        jsr num_to_digits       ; hd_d1 = fps ones, hd_d0 = tenths
        pla
        beq ?no_t               ; no leading zero
        ldx #FPS_X
        jsr hud_char_x
?no_t   ldx #FPS_X+8
        lda hd_d1
        jsr hud_char_x
        jsr fps_comma
        ldx #FPS_X+24
        lda hd_d0
        jmp hud_char_x
?r      rts
.endp

; FPS_COMMA - 2x3 comma at (FPS_X+17, HUD_Y+5): the FPS_COL byte at
; HUD_COMMA copied over it (sprite list, hud_clear_icon.solid)
.proc fps_comma
        lda #BANK_EN+[HUD_COMMA>>12]
        sta VBXE_BANK_SEL
        lda #FPS_COL            ; the source byte (a screen clear may reach it)
        sta MEMW+[HUD_COMMA&$FFF]
        lda #FPS_X+17
        sta zdx                 ; (zdxh = 0: fps_draw's clears)
        lda #HUD_Y+5
        sta zdy
        lda #2
        sta hud_clear_icon.hgt+1
        ldy #1
        lda #<HUD_COMMA
        jsr hud_clear_icon.solid
        lda #HUD_Y              ; the digits' row again
        sta zdy
        rts
.endp

; ============================================
; SHOW_LEVEL_STATS - the level's end (g_game.pas STATE_INTERSINGLE,
; DrawSingleStat): "LEVEL COMPLETE", then Time h:mm:ss, Kills x / y,
; Kills-per-minute ##.#, Secrets found x / y; the values red (_RGB(255,0,0):
; MODE 7 through VRAM_LUT page 3). Every char a blit at once (no frame list
; runs here). Waits for FIRE.
; ============================================
SLS_KX  = 60                    ; the keys' column: 17 chars + 8 + " 9999.9"
SLS_VX  = SLS_KX+17*8+8         ; centred in 320 (key_x / val_x)
.proc show_level_stats
        jsr wait_blit
        jsr clear_full_black
        jsr ls_stamp            ; slot 0's bank (+8): blit_hud_char skips it
        lda #0
        sta zdxh                ; (blit_hud_char only reads it)
        sta ?red
        lda #16                 ; "LEVEL COMPLETE", centred
        sta zdy
        lda #[320-14*8]/2
        sta zdx
        ldx #?s_lc-?txt
        jsr ?str
        lda #32                 ; Time: h:mm:ss
        ldx #?s_tm-?txt
        jsr ?key
        lda stat_time_lo
        sta ?dn
        lda stat_time_hi
        sta ?dn+1
        lda #<3600
        ldx #>3600
        jsr ?div
        jsr ?num                ; the hours
        lda #CH_COLON
        jsr ?ch
        lda ?dr                 ; the rest: minutes, seconds
        sta ?dn
        lda ?dr+1
        sta ?dn+1
        lda #60
        ldx #0
        jsr ?div
        lda ?dn
        jsr ?n2
        lda #CH_COLON
        jsr ?ch
        lda ?dr
        jsr ?n2
        lda #56                 ; Kills: x / y
        ldx #?s_kl-?txt
        jsr ?key
        lda stat_kills
        ldx stat_total_en
        jsr ?pair
        lda #72                 ; Kills-per-minute: kills*60 / s, one decimal
        ldx #?s_kp-?txt
        jsr ?key
        lda #0                  ; kills * 60 = (kills * 16 - kills) * 4: the low
        sta ?dn+1               ; byte in A, stored once (6502-idioms)
        lda stat_kills
        asl
        rol ?dn+1
        asl
        rol ?dn+1
        asl
        rol ?dn+1
        asl
        rol ?dn+1               ; * 16
        sec
        sbc stat_kills          ; * 15
        bcs ?k15
        dec ?dn+1
?k15    asl
        rol ?dn+1
        asl
        rol ?dn+1               ; * 60 (<= 15300)
        sta ?dn
        lda stat_time_lo        ; a time of 0: kills (the original's else)
        ora stat_time_hi
        bne ?kt
        lda stat_kills
        sta ?dn
        lda #0
        sta ?dn+1
        sta ?dr
        beq ?kq                 ; (always)
?kt     lda stat_time_lo
        ldx stat_time_hi
        jsr ?div
        lda #0                  ; the tenth: rest * 10 / s (0 past 6553 s:
        ldx stat_time_hi        ; rest * 10 would leave 16 bits)
        cpx #>6554
        bcs ?kz
        lda ?dn                 ; (the quotient kept)
        pha
        lda ?dn+1
        pha
        lda ?dr+1               ; rest * 10 = (rest * 4 + rest) * 2 (< 65536:
        sta ?dn+1               ; the rest < the time < 6554)
        lda ?dr
        asl
        rol ?dn+1
        asl
        rol ?dn+1               ; * 4 (C=0)
        adc ?dr
        sta ?dn
        lda ?dn+1
        adc ?dr+1
        sta ?dn+1               ; * 5
        asl ?dn
        rol ?dn+1               ; * 10
        lda stat_time_lo
        ldx stat_time_hi
        jsr ?div
        lda ?dn                 ; the tenth 0..9
        sta ?dr
        pla
        sta ?dn+1
        pla
        sta ?dn
        lda ?dr
        dta $2C                 ; bit abs: skips the lda
?kz     lda #0
        sta ?dr
?kq     jsr ?num
        lda #CH_DOT
        jsr ?ch
        lda ?dr
        jsr ?ch
        lda #88                 ; Secrets found: x / y
        ldx #?s_sc-?txt
        jsr ?key
        lda stat_secrets
        ldx stat_tsec
        jsr ?pair
        jsr wait_blit           ; slot 0 a plain copy again (the sprites'
        lda #0                  ; table page / cmask 0)
        sta SPRL_W+17
        lda #BANK_EN+BANK_XDL   ; show it
        sta VBXE_BANK_SEL
        lda zbuf_hi
        sta MEMW+[VRAM_XDL&$FFF]+8
?rel    lda TRIG0               ; wait for FIRE released, then pressed
        beq ?rel
?wait   lda TRIG0
        bne ?wait
        rts
; ?KEY - the key string X at row A, then the values' column, red
?key    sta zdy
        lda #SLS_KX
        sta zdx
        lda #0
        sta ?red
        sta zdxh
        jsr ?str
        lda #SLS_VX+8           ; (" %d": a space first)
        sta zdx
        inc ?red
        rts
; ?PAIR - " A / X": the values red, the slash not
?pair   stx ?py+1
        jsr ?b8
        lda #0
        sta ?red
        jsr ?adv
        lda #CH_DIV
        jsr ?ch
        jsr ?adv
        inc ?red
?py     lda #0                  ; (patched)
?b8     sta ?dn                 ; a byte as ?num
        lda #0
        sta ?dn+1
; ?NUM - ?dn in decimal, no leading zeros
?num    ldy #4                  ; 10000, 1000, 100, 10, 1
        lda #0
        sta ?z
?nd     ldx #0                  ; X = this digit
?ns     lda ?dn
        sec
        sbc ?p10l,y
        sta ?t
        lda ?dn+1
        sbc ?p10h,y
        bcc ?ne
        sta ?dn+1
        lda ?t
        sta ?dn
        inx
        bne ?ns                 ; (always)
?ne     txa
        ora ?z
        beq ?nz                 ; a leading zero (not the last digit)
        sta ?z
        txa
        jsr ?ch
?nz     dey
        bpl ?nd
        lda ?z
        bne ?r
        lda #0                  ; the value 0: one digit
        beq ?ch                 ; (always)
; ?N2 - A (0..99) as two digits
?n2     ldx #0
?n2l    cmp #10
        bcc ?n2e
        sbc #10
        inx
        bne ?n2l                ; (always)
?n2e    pha
        txa
        jsr ?ch
        pla
; ?CH - char A at zdx (?red: through the red table), zdx += 8; keeps X, Y
?ch     stx ?xs+1
        sty ?ys+1
        jsr blit_hud_char       ; slot 0 (spl_flush empties the list again)
        lda ?red
        beq ?cw
        lda #3                  ; MODE 7, AUX = VRAM_LUT's bank, page 3
        sta SPRL_W+17
        lda #[[VRAM_LUT>>16]<<4]+7
        sta SPRL_W+20
?cw     jsr spl_flush
        jsr ?adv
?xs     ldx #0                  ; (patched)
?ys     ldy #0                  ; (patched)
?r      rts
; ?STR - the string at ?txt+X ($FE a space, $FF the end) from zdx
?str    lda ?txt,x
        cmp #$FF
        beq ?r
        cmp #$FE
        beq ?sp
        jsr ?ch
        jmp ?sn
?sp     jsr ?adv
?sn     inx
        bne ?str                ; (always)
; ?ADV - zdxh:zdx += 8 (the values run past x = 255)
?adv    lda zdx
        clc
        adc #8
        sta zdx
        bcc ?ar
        inc zdxh
?ar     rts
; ?DIV - ?dn / A:X (16-bit): ?dn = the quotient, ?dr = the rest
?div    sta ?dd
        stx ?dd+1
        lda #0
        sta ?dr
        sta ?dr+1
        ldy #16
?dl     asl ?dn
        rol ?dn+1
        rol ?dr
        rol ?dr+1
        lda ?dr
        sec
        sbc ?dd
        tax
        lda ?dr+1
        sbc ?dd+1
        bcc ?dk
        sta ?dr+1
        stx ?dr
        inc ?dn
?dk     dey
        bne ?dl
        rts
?red    dta 0
?z      dta 0
?dn     dta 0,0
?dd     dta 0,0
?dr     dta 0,0
?t      dta 0,0
?p10l   dta <1, <10, <100, <1000, <10000
?p10h   dta >1, >10, >100, >1000, >10000
?txt
?s_lc   dta CH_A+11,CH_A+4,CH_A+21,CH_A+4,CH_A+11,$FE                   ; LEVEL
        dta CH_A+2,CH_A+14,CH_A+12,CH_A+15,CH_A+11,CH_A+4,CH_A+19,CH_A+4,$FF ; COMPLETE
?s_tm   dta CH_A+19,CH_A+8,CH_A+12,CH_A+4,CH_COLON,$FF                  ; TIME:
?s_kl   dta CH_A+10,CH_A+8,CH_A+11,CH_A+11,CH_A+18,CH_COLON,$FF         ; KILLS:
?s_kp   dta CH_A+10,CH_A+8,CH_A+11,CH_A+11,CH_A+18,CH_DASH              ; KILLS-
        dta CH_A+15,CH_A+4,CH_A+17,CH_DASH                              ; PER-
        dta CH_A+12,CH_A+8,CH_A+13,CH_A+20,CH_A+19,CH_A+4,CH_COLON,$FF  ; MINUTE:
?s_sc   dta CH_A+18,CH_A+4,CH_A+2,CH_A+17,CH_A+4,CH_A+19,CH_A+18,$FE    ; SECRETS
        dta CH_A+5,CH_A+14,CH_A+20,CH_A+13,CH_A+3,CH_COLON,$FF          ; FOUND:
.endp

; ============================================
; The console message of g_player.pas GetSecret ("%s found a secret!",
; g_console.pas: top left, MsgTime 144 ticks = 4 s): drawn every frame
; while it is on. msg_on hooks msg_frame into the main loop's frame_chain
; call (2026-11-02 6502-loops-tables-smc.md "patch an operand to switch
; behaviour": no cost while no message is on).
; In the RAM the ANTIC sky's display lists had ($0C00, data.asm).
; ============================================
MSG_TIME = 200                  ; 4 s at 50 frames/s
msg_save = *
        org $0C00
msg_t   dta 0                   ; frames left
.proc msg_on
        lda #MSG_TIME
        sta msg_t
        lda #<msg_frame
        sta main.fc_call+1
        lda #>msg_frame
        sta main.fc_call+2
        rts
.endp
.proc msg_frame
        dec msg_t
        bne ?d
        lda #<frame_chain       ; the last frame: unhook
        sta main.fc_call+1
        lda #>frame_chain
        sta main.fc_call+2
?d      lda #BLT_TRANS+$08      ; transparent, as the console's font
        sta blit_hud_char.md+1
        lda #0                  ; from (0, 0)
        sta zdy
        sta zdxh
        tax
?lp     txa                     ; zdx = 8 * the char's index (< 256)
        asl
        asl
        asl
        sta zdx
        lda ?txt,x
        bpl ?ch
        lsr                     ; $FF the end: C=1; $FE a space: C=0
        bcs ?end
        bcc ?nx                 ; (always)
?ch     jsr blit_hud_char       ; keeps X
?nx     inx
        bne ?lp                 ; (always)
?end    lda #$08                ; opaque again (the HUD, the menus)
        sta blit_hud_char.md+1
        jmp frame_chain
?txt    dta CH_A+15,CH_A+11,CH_A+0,CH_A+24,CH_A+4,CH_A+17,$FE           ; PLAYER
        dta CH_A+5,CH_A+14,CH_A+20,CH_A+13,CH_A+3,$FE,CH_A+0,$FE        ; FOUND A
        dta CH_A+18,CH_A+4,CH_A+2,CH_A+17,CH_A+4,CH_A+19,CH_EXCL,$FF    ; SECRET!
        ert *-?txt>32           ; zdx = 8 * index stays below 256
.endp
        ert *>$0C00+582         ; mon_anims (data.asm)
        org msg_save

