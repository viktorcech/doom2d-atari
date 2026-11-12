;==============================================
; DOOM2D - Save/Load game (SIO sector write/read)
; savegame.asm
;
; 3 save slots, each SAVE_SECTORS sectors on ATR.
; Slot submenu shown before save/load.
;==============================================

SAVE_MAGIC1     = $44           ; 'D'
SAVE_MAGIC2     = $32           ; '2'
; Slot layout: SV_BYTES (30 B header + the arrays of sv_tab_len) in
; SV_SECTORS through a VRAM bank (BANK_SV, the MEMAC window MEMW), then the
; map's VRAM image (map_sio). LVL_BUF stays untouched during a game.
; Keep SAVE_SECTORS in step with build_doom2d.py.
SV_BYTES        = 30+24*MAX_ENEMIES+8*MAX_PICKUPS+1+11*MAX_DECOR+7*TR_MAX+DP_MAX+SP_MAX+LF_MAX+AM_BYTES
SV_SECTORS      = [SV_BYTES+127]/128
SAVE_SECTORS    = SV_SECTORS+MAP_BYTES/128 ; sectors per slot
        ert SV_SECTORS*128>$1000        ; one MEMAC bank
BANK_SV         = $1C           ; VRAM $01C000: the slot buffer (free: past VRAM_ANIM,
                                ; before the HUD font; $1E-$1F: frame.asm pre lists)
        ert SAVE_SECTORS>128            ; SAVE_SLOT_MAX in build_doom2d.py
NUM_SLOTS       = 3
SLOT_MENU_Y     = 80
SLOT_MENU_X     = 104

; Slot info (read from disk headers)
slot_level  dta 0,0,0           ; level number per slot (0-based)
slot_valid  dta 0,0,0           ; 1=has save, 0=empty
slot_sel    dta 0               ; current slot selection (0-2)
slot_prev   dta 0               ; previous selection (for redraw)
slot_mode   dta 0               ; 0=save, 1=load

;==============================================
; LOAD GAME MENU — show slot submenu, load from chosen slot
; Returns: A=0 success, A=1 cancel/error (N/Z from A on both exits)
;==============================================
.proc load_game_menu
        lda #1                  ; mode=load
        jsr slot_open           ; C=1: user cancelled
        bcc load_game           ; A=0 on success (exits via pla)
        lda #1                  ; cancelled
done    rts
.endp

;==============================================
; SAVE GAME MENU — show slot submenu, save to chosen slot
; Returns: nothing (stays in pause menu after). Falls into save_game.
;==============================================
.proc save_game_menu
        lda #0                  ; mode=save
        jsr slot_open           ; C=1: user cancelled
        bcs load_game_menu.done
        ert *<>save_game
.endp

;==============================================
; SAVE GAME — serialize state to LVL_BUF, write to selected slot
; Returns: A=0 success, A=1 error
;==============================================
.proc save_game
        jsr sio_quiet_scr       ; display, sound IRQ off for clean SIO
        clc                     ; C=0: save (arrays -> slot buffer)
        jsr sv_walk_all
        jsr calc_slot_sector
        lda #BANK_EN+BANK_SV
        sta vram_sio.vs_bank
        lda #SV_SECTORS
        sec                     ; C=1: write
        jsr vram_sio.go         ; C=1: SIO error
        bcs ret_c
        sec                     ; C=1: write the map (DAUX = its first sector)
        jsr map_sio
ret_c   lda #0                  ; (load_game's SIO errors enter here, C=1)
        adc #0                  ; A = C: 0 success, 1 error
        jmp sio_end_scr
.endp

;==============================================
; LOAD GAME — the slot's level (static data: spawns, bg overrides), then
; the slot: header + arrays, then its map over the level's.
; Returns: A=0 success, A=1 error
;==============================================
.proc load_game
        jsr sio_quiet_scr       ; display, sound IRQ off
        ldx slot_sel
        lda slot_level,x
        sta current_level
        jsr load_level          ; (the sound IRQ stays masked)
        jsr calc_slot_sector
        lda #BANK_EN+BANK_SV
        sta vram_sio.vs_bank
        lda #SV_SECTORS
        clc                     ; C=0: read
        jsr vram_sio.go         ; C=1: SIO error
        bcs save_game.ret_c     ; A = 1 (exit C=0, unread: callers test Z)
        sec                     ; C=1: load (slot buffer -> arrays)
        jsr sv_walk_all
        lda #0                  ; the enemy arrays not in the slot: LVL_BUF
        ldx #MAX_ENEMIES-1      ; held the level file (load_level); the
?z      sta en_acnt,x           ; target: the player
        sta en_hit,x
        sta en_tgt,x
        sta en_ttm,x
        dex
        bpl ?z
        clc                     ; C=0: read the map (DAUX = its first sector)
        jsr map_sio
        bcs save_game.ret_c     ; A = 1

        ; dc_exp_cnt is derived, not saved - rebuild it from the restored
        ; dc_act array (keeps old save files loadable)
        jsr decor_recount_exp

        ; --- Clear projectiles ---
        lda #0
        ldx #MAX_PROJ-1
?clr_p  sta proj_a,x
        dex
        bpl ?clr_p
        ldx #MAX_EPROJ-1
?clr_e  sta eproj_a,x
        dex
        bpl ?clr_e
        jmp sio_end_scr         ; A=0: success
.endp

; SLOT_OPEN - A = slot_mode, read the slot headers, run the slot submenu
.proc slot_open
        sta slot_mode
        jsr read_slot_headers
        ert *<>slot_submenu
.endp

;==============================================
; SLOT SUBMENU — joystick/keyboard slot selection
; Returns: C=0 slot chosen (slot_sel), C=1 cancelled
;==============================================
.proc slot_submenu
        lda #0
        sta slot_sel
        sta slot_prev
        sta CH               ; clear keyboard
        ; Play enter sound (after SIO in read_slot_headers)
        ldx #SFX_PISTOL
        jsr snd_play
        ; Draw on both buffers
        jsr slot_draw_both

?loop   jsr menu_vsync

        ; ESC = cancel
        lda CH
        cmp #$1C
        jeq ?esc
        ; RETURN = confirm
        cmp #$0C
        jeq ?ret
        ; Keyboard up/down
        and #$7F                ; $0E/$8E -> $0E (up), $0F/$8F -> $0F (down)
        clc
        adc #$FF-$0F
        adc #$0F-$0E+1          ; C=1 inside [$0E,$0F]: A = 0 up, 1 down
        bcc ?joy
        ldy #$FF
        sty CH
        lsr                     ; C = down
        jsr ?step
        jmp ?loop

        ; Joystick
?joy    lda PORTA
        eor #$FF
        tay                     ; Y = stick, 1 = pressed
        lda sm_prev
        eor #$FF
        sty sm_prev             ; sm_prev = this frame's stick (sty: no flags)
        and sm_prev             ; A = newly pressed
        tay
        and #J_UP
        beq ?no_jup
        jsr ?up                 ; keeps Y
?no_jup tya
        and #J_DOWN
        beq ?no_jdn
        jsr ?dn

?no_jdn ; Fire = confirm
        lda TRIG0
        bne ?no_fire
        ; wait release
?fr_rel lda TRIG0
        beq ?fr_rel
        bne ?confirm            ; Z=0 from the release loop
?no_fire
        ; Redraw if selection changed (cursor only, not the whole menu)
        lda slot_sel
        cmp slot_prev
        beq ?loop
        ldx #SFX_PISTOL
        jsr snd_play
        jsr slot_move_cursor
        lda slot_sel
        sta slot_prev
        jmp ?loop

?ret    lda #$FF
        sta CH
?confirm
        ; In load mode, check if selected slot is valid
        lda slot_mode
        beq ?ok                 ; save mode: any slot is fine
        ldx slot_sel
        lda slot_valid,x
        jeq ?loop               ; empty slot, can't load — stay in menu
?ok     ldx #SFX_PISTOL
        jsr snd_play
        clc                     ; C=0 = confirmed
        rts

?esc    jsr menu_esc_snd
        sec                     ; C=1 = cancelled
        rts

; C=0 up, C=1 down (slot_sel stays in 0..NUM_SLOTS-1); A only
?step   bcs ?dn
?up     lda slot_sel
        beq ?r
        dec slot_sel
?r      rts
?dn     lda slot_sel
        cmp #NUM_SLOTS-1
        bcs ?r
        inc slot_sel
        rts

sm_prev dta 0
.endp

;==============================================
; SLOT_MOVE_CURSOR - cursor-only redraw on slot change (both buffers).
; Replaces a full clear+text redraw per cursor move.
;==============================================
.proc slot_move_cursor
        jsr both_bufs           ; the rest runs once per buffer
        lda slot_prev
        jsr cpos
        jsr menu_clear_char     ; erase old cursor
        lda slot_sel
        jsr cpos
        lda #11                 ; cursor char
        jmp menu_char
cpos    ldy #SLOT_MENU_X-16     ; slot -> zdy = SLOT_MENU_Y+16 + slot*16 =
        clc                     ; menu row slot+1 (<= 3); keeps X
        adc #1
        jmp move_cursor.cpos_y
.endp
        ert SLOT_MENU_Y<>MENU_Y

;==============================================
; DRAW SLOT MENU ON BOTH BUFFERS
;==============================================
.proc slot_draw_both
        jsr both_bufs           ; the rest runs once per buffer
        jsr clear_menu_area
        jsr slot_draw
        jmp wait_blit
.endp

;==============================================
; DRAW SLOT MENU (title + 3 slot lines + cursor)
;==============================================
.proc slot_draw
        ; Title: "SAVE" or "LOAD"
        ldx #dl_save_t-dl_tab
        lda slot_mode
        beq ?t
        ldx #dl_load_t-dl_tab
?t      jsr draw_list

        ; 3 slot lines (X = slot; menu_char and draw_text keep X)
        ldx #0
?slot_lp
        txa
        jsr slot_move_cursor.cpos ; zdy = row, zdx = cursor column, zdxh = 0

        ; Cursor for selected slot
        cpx slot_sel
        bne ?no_cursor
        lda #11                 ; cursor char '>'
        jsr menu_char
?no_cursor

        ; Slot number: "1 " / "2 " / "3 "
        txa
        clc
        adc #'1'
        sta sd_numbuf
        lda #<sd_numbuf
        sta txt_ptr
        lda #>sd_numbuf
        sta txt_ptr+1
        lda #SLOT_MENU_X
        sta zdx                 ; zdxh = 0 from cpos (menu_char only reads it)
        jsr draw_text           ; "1 ": zdx 104 -> 120, no carry: zdxh stays 0

        ; Slot status: "EMPTY" or "MAP X" (slot_valid is 0 or 1)
        ldy slot_valid,x
        beq ?empty
        ; Valid save: "MAP " + digit
        lda slot_level,x
        clc
        adc #'1'                ; level 0 = "MAP 1"
        sta sd_mapnum
?empty  lda ?st_lo,y
        sta txt_ptr
        lda ?st_hi,y
        sta txt_ptr+1
        lda #SLOT_MENU_X+24
        sta zdx
        jsr draw_text

        inx
        cpx #NUM_SLOTS
        jcc ?slot_lp
        rts

?st_lo  dta <txt_empty_slot, <sd_mapstr
?st_hi  dta >txt_empty_slot, >sd_mapstr
sd_numbuf dta '1',' ',0
sd_mapstr dta 'MAP '
sd_mapnum dta '1',0
.endp

;==============================================
; READ SLOT HEADERS — read first sector of each slot, check magic
;==============================================
.proc read_slot_headers
        jsr sio_quiet           ; disable sound IRQ for SIO

        ldx #0
?slot_lp
        jsr calc_sector_x       ; DAUX = sector of slot X (keeps X)
        txa
        pha
        lda #BANK_EN+BANK_SV    ; 1 sector into the slot buffer
        sta vram_sio.vs_bank
        lda #1
        clc
        jsr vram_sio.go         ; C=1: SIO error (bank 0 after)
        pla
        tax                     ; (pla/tax keep C)
        bcs ?inv                ; SIO error: mark slot as empty
        lda #BANK_EN+BANK_SV    ; check magic
        sta VBXE_BANK_SEL
        lda MEMW
        cmp #SAVE_MAGIC1
        bne ?inv
        lda MEMW+1
        cmp #SAVE_MAGIC2
        bne ?inv
        ; Valid save
        lda MEMW+2
        sta slot_level,x
        lda #1
        dta $2C                 ; bit $00A9 (RAM; V is read nowhere): skips lda #0
?inv    lda #0
        sta slot_valid,x
        lda #0
        sta VBXE_BANK_SEL
        inx
        cpx #NUM_SLOTS
        bcc ?slot_lp
        rts
.endp

;==============================================
; Calculate sector number for selected slot → DAUX1/DAUX2
; Sector = SAVE_SEC1 + slot_sel * SAVE_SECTORS (calc_sector_x: slot in X,
; kept)
;==============================================
.proc calc_slot_sector
        ldx slot_sel
        ert *<>calc_sector_x
.endp
.proc calc_sector_x
        lda ?lo,x
        sta DAUX1
        lda ?hi,x
        sta DAUX2
        rts
?lo     dta <[SAVE_SEC1], <[SAVE_SEC1+SAVE_SECTORS], <[SAVE_SEC1+SAVE_SECTORS*2]
?hi     dta >[SAVE_SEC1], >[SAVE_SEC1+SAVE_SECTORS], >[SAVE_SEC1+SAVE_SECTORS*2]
        ert NUM_SLOTS<>3
.endp

; ============================================
; SAVED ARRAY TABLE - the single source of truth for what a save slot holds.
;
; save_game and load_game used to each carry their own hand-written copy of
; this list (45 entries, 8 bytes of code per entry). They had to stay in the
; same order or a slot would load garbage into the wrong arrays, and nothing
; checked that. One table, walked in both directions, makes drift impossible.
; The first SV_NHDR entries are the 30-byte slot header (save only; load
; skips them): magic, level, player vars (runs of adjacent cells), counts.
; ============================================
sv_magic dta SAVE_MAGIC1, SAVE_MAGIC2
        ert zpvx<>zpy+1
        ert zpvy<>zpy+2
        ert zpdir<>zpy+3
        ert zpst<>zpy+4
        ert zpan<>zpy+5
        ert zphp<>zpy+6
        ert zpammo<>zpy+7
        ert zpgnd<>zpy+8
        ert zpkeys<>zparmor+1
        ert zpweap<>zparmor+2
        ert zpshells<>zparmor+3
        ert zprockets<>zparmor+4
        ert zpcells<>zparmor+5
        ert zpwcur<>zparmor+6
        ert pl_pain_timer<>pl_dead_timer+1
        ert num_pk<>num_en+1
        ert num_dc<>num_en+2
SV_NHDR = 12
sv_tab_lo
        dta <sv_magic, <current_level, <zpx, <zpx_hi, <zpy, <zparmor
        dta <zpwcool, <pl_dead_timer, <num_en, <stat_kills, <stat_secrets, <level_complete
        dta <en_x, <enxhi, <en_y, <en_y_hi, <en_dir, <en_act
        dta <en_hp, <en_type, <en_anim, <envely, <en_gib, <envelx
        dta <en_atk, <en_afr, <en_state, <en_sleep, <en_ammo, <en_pain
        dta <en_vx, <en_vxf, <en_vyf, <en_xf, <en_yf, <en_tick
        dta <pk_act, <pk_x, <pk_xhi, <pk_y, <pk_y_hi, <pk_type, <pk_col, <pk_row, <pk_end
        dta <dc_act, <dc_x, <dc_xhi, <dc_orig_tile, <dc_y, <dc_y_hi
        dta <dc_hp, <dc_timer
        dta <tr_flag, <tr_type, <tr_act, <tr_to, <tr_dt, <tr_pt, <tr_pc
        dta <dp_state, <sp_state, <lf_type, <am_hi
sv_tab_hi
        dta >sv_magic, >current_level, >zpx, >zpx_hi, >zpy, >zparmor
        dta >zpwcool, >pl_dead_timer, >num_en, >stat_kills, >stat_secrets, >level_complete
        dta >en_x, >enxhi, >en_y, >en_y_hi, >en_dir, >en_act
        dta >en_hp, >en_type, >en_anim, >envely, >en_gib, >envelx
        dta >en_atk, >en_afr, >en_state, >en_sleep, >en_ammo, >en_pain
        dta >en_vx, >en_vxf, >en_vyf, >en_xf, >en_yf, >en_tick
        dta >pk_act, >pk_x, >pk_xhi, >pk_y, >pk_y_hi, >pk_type, >pk_col, >pk_row, >pk_end
        dta >dc_act, >dc_x, >dc_xhi, >dc_orig_tile, >dc_y, >dc_y_hi
        dta >dc_hp, >dc_timer
        dta >tr_flag, >tr_type, >tr_act, >tr_to, >tr_dt, >tr_pt, >tr_pc
        dta >dp_state, >sp_state, >lf_type, >am_hi
sv_tab_len
        dta 2, 1, 1, 1, 9, 7, 1, 2, 3, 1, 1, 1   ; header: 30 bytes
        dta MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES
        dta MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES
        dta MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES
        dta MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES, MAX_ENEMIES
        dta MAX_PICKUPS, MAX_PICKUPS, MAX_PICKUPS, MAX_PICKUPS, MAX_PICKUPS, MAX_PICKUPS
        dta MAX_PICKUPS, MAX_PICKUPS, 1
        dta MAX_DECOR, MAX_DECOR, MAX_DECOR, 4*MAX_DECOR, MAX_DECOR, MAX_DECOR
        dta MAX_DECOR, MAX_DECOR
        dta TR_MAX, TR_MAX, TR_MAX, TR_MAX, TR_MAX, TR_MAX, TR_MAX
        dta DP_MAX, SP_MAX, LF_MAX, AM_BYTES
SV_NARRAYS = 52
SV_NTAB = SV_NHDR+SV_NARRAYS
        ert *-sv_tab_len<>SV_NTAB
        ert sv_tab_hi-sv_tab_lo<>SV_NTAB
        ert MAX_ENEMIES>128
        ert MAX_PICKUPS>128
        ert 4*MAX_DECOR>128
        ert TR_MAX>128

; ============================================
; SV_WALK_ARRAYS - copy table entries between their array and the slot
; buffer (at zsrc, zsrc advances). C=0 -> save (array to buffer), C=1 ->
; load (buffer to array). X = 256 - number of entries to walk (the walk
; ends with the table: X counts up to 0).
; Each array is copied top down (len <= 128): same bytes, distinct memory.
; SV_WALK_ALL: the whole table (header + arrays) from MEMW; keeps C.
; ============================================
.proc sv_walk_all
        lda #BANK_EN+BANK_SV    ; the slot buffer in the MEMAC window
        sta VBXE_BANK_SEL       ; (lda/sta keep C)
        lda #<MEMW
        sta zsrc
        lda #>MEMW
        sta zsrc+1
        ldx #256-SV_NTAB
        ert *<>sv_walk_arrays
.endp
.proc sv_walk_arrays
        lda #ztptr              ; save: read (ztptr), write (zsrc)
        ldy #zsrc
        bcc ?s
        lda #zsrc               ; load: read (zsrc), write (ztptr)
        ldy #ztptr
?s      sta ?rd+1
        sty ?wr+1
?lp     lda sv_tab_lo+SV_NTAB-256,x
        sta ztptr
        lda sv_tab_hi+SV_NTAB-256,x
        sta ztptr+1
        ldy sv_tab_len+SV_NTAB-256,x
        dey
?rd     lda (ztptr),y
?wr     sta (zsrc),y
        dey
        bpl ?rd
        lda sv_tab_len+SV_NTAB-256,x    ; zsrc += len (nothing else in the
        clc                             ; walk writes zsrc)
        adc zsrc
        sta zsrc
        bcc ?nc
        inc zsrc+1
?nc     inx
        bne ?lp
        lda #0                  ; MEMAC bank off
        sta VBXE_BANK_SEL
        rts
.endp

;==============================================
; Text data (titles: txt_save / txt_load in menu_draw.asm)
;==============================================
txt_empty_slot  dta c'EMPTY',0
