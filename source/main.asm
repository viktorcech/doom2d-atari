;==============================================
; DOOM2D for Atari XE/XL + VBXE
; main.asm - Entry point
;
; Build: mads main.asm -o:doom2d.xex
;==============================================

        opt h+
        opt o+

        icl 'constants.asm'
        icl 'zeropage.asm'

;==============================================
; INIT segment: runs during XEX load, before main data
; Turns off screen to prevent garbage display
;==============================================
        org $0600
.proc early_init
        lda #0
        sta SDMCTL          ; disable ANTIC DMA
        sta $D400           ; DMACTL shadow
        sta COLOR4          ; black background
        rts
.endp
        ini early_init

;==============================================
; MEMAC-B read trampoline (must be below $4000!)
; MEMAC-B maps $4000-$7FFF to VRAM when enabled.
; snd_irq code may be at $4000+, so enable/read/disable
; must execute from here ($0610) to avoid crash.
;==============================================
        org $0610
snd_memac_read
        lda snd_bank
        sta VBXE_MEMAC_B
        ldy #0
        lda (snd_ptr),y
        sty VBXE_MEMAC_B
        sta snd_cur_byte
        rts

;==============================================
        org $2000
;==============================================

.proc main
        sei

        ; Black screen during init (no ANTIC DMA, black background)
        lda #0
        sta SDMCTL
        sta COLOR4

        ; --- VBXE detection ---
        ; Try $D600 first
        lda $D640
        cmp #$10            ; FX core?
        beq ?vbxe_ok
        ; Try $D700
        lda $D740
        cmp #$10
        beq ?vbxe_ok

        ; VBXE not found: restore default Atari screen
        lda #$22
        sta SDMCTL          ; enable ANTIC DMA
        lda #0
        sta COLOR4          ; black border (COLBK)
        lda #$94
        sta $02C6           ; COLOR2 = blue text bg
        cli
        ; Open E: on IOCB #0
        ldx #0
        lda #3              ; OPEN
        sta $0342           ; ICCOM
        lda #<s_edev
        sta $0344           ; ICBAL
        lda #>s_edev
        sta $0345           ; ICBAH
        lda #$0C            ; read+write
        sta $034A           ; ICAX1
        lda #0
        sta $034B           ; ICAX2
        jsr CIOV
        ; Print message
        ldx #0
        lda #$09            ; PUT RECORD
        sta $0342           ; ICCOM
        lda #<no_vbxe_msg
        sta $0344           ; ICBAL
        lda #>no_vbxe_msg
        sta $0345           ; ICBAH
        lda #<no_vbxe_len
        sta $0348           ; ICBLL
        lda #>no_vbxe_len
        sta $0349           ; ICBLH
        jsr CIOV
        jmp *               ; halt

s_edev  dta c'E:',$9B

?vbxe_ok
        ; MEMAC-A: 4KB at $9000, CPU access
        lda #$90+MC_CPU
        sta VBXE_MEMAC_CTRL

        ; Keep VBXE display OFF during init (black screen)
        lda #0
        sta VBXE_VCTL

        ; Palette, tiles, sprites, HUD font, map, title all uploaded via INI segments
        jsr setup_xdl
        ; Note: no init_clear here - title graphic is already in screen buffers

        ; Everything ready: NOW enable XDL display
        lda #VC_XDL_ON+VC_NO_TRANS
        sta VBXE_VCTL
        lda #$00
        sta VBXE_XDL0
        lda #$F0
        sta VBXE_XDL1
        lda #$07
        sta VBXE_XDL2

        ; Detect PAL/NTSC
        lda $D014           ; PAL register
        and #$0E            ; bits 1-3
        sta is_pal          ; 0=NTSC, non-zero=PAL

        ; Digital sound engine init (Timer 1 IRQ + AUDC4)
        jsr snd_init

        ; Init double buffer: draw to screen 1, display screen 0
        lda #SCR1_HI            ; $02
        sta zbuf_hi

        ; Start in title state
        lda #STATE_TITLE
        sta game_state

        cli

; =============================================
; TITLE SCREEN (menu logic in menu.asm)
; =============================================
        jsr menu_title_screen

?start_game
        lda #STATE_PLAYING
        sta game_state
        jsr init_game
        jsr init_render
        ; Force HUD full redraw
        lda #$FF
        sta hud_prev_hp
        sta hud_prev_ammo
        sta hud_prev_weap
        sta hud_prev_keys
        sta hud_prev_armor
        lda #2
        sta hud_frames
        lda #2
        sta hud_full_clear

; --- Game loop (double buffered) ---
?loop
        ; ESC = pause + menu
        lda $02FC
        cmp #$1C
        bne ?no_esc
        lda #$FF
        sta $02FC
        jsr menu_pause
        cmp #1
        beq ?start_game         ; new game requested
?no_esc
        inc zfr

        ; PROFILING: uncomment STA $D01A lines to see border color timing
        ; Colors: $10=gray(logic) $30=red(dirty) $C0=green(render)
        ;         $90=blue(HUD) $50=purple(blit wait) $00=black(idle)
        ; lda #$10
        ; sta $D01A

        jsr read_input
        ; Check player death
        lda zphp
        bne ?alive
        jsr player_dead
        jsr update_enemies
        jsr update_decorations
        jmp ?skip_logic
?alive
        jsr player_update
        jsr update_enemies
        jsr proj_update
        jsr eproj_update
        jsr update_pickups
        jsr update_decorations
        jsr update_doors
        jsr update_switches
        jsr check_floor_triggers
        jsr sound_update
        jsr fps_update
?skip_logic

        ; lda #$30
        ; sta $D01A
        jsr restore_dirty

        ; lda #$C0
        ; sta $D01A
        jsr render_pickups_nodirty
        jsr render_decor_nodirty
        jsr render_exploding
        jsr render_enemies
        jsr render_projs
        jsr render_eproj
        jsr render_player

        ; lda #$90
        ; sta $D01A
        jsr render_hud
        jsr fps_render

        ; lda #$50
        ; sta $D01A
        jsr wait_blit

        ; lda #$00
        ; sta $D01A

        ; Wait VBLANK
        lda RTCLOK3
?vsync  cmp RTCLOK3
        beq ?vsync

        ; Swap: update XDL overlay address to show back buffer
        lda #BANK_EN+BANK_XDL
        sta VBXE_BANK_SEL
        lda zbuf_hi             ; current back buffer high byte
        sta MEMW+[VRAM_XDL&$FFF]+8  ; XDL overlay addr high byte

        ; Flip: toggle zbuf_hi between $00 and $02
        lda zbuf_hi
        eor #SCR1_HI
        sta zbuf_hi

        jmp ?loop
.endp

; --- VBXE not detected message ---
no_vbxe_msg
        dta c'VBXE NOT DETECTED!'
        dta $9B                    ; EOL
no_vbxe_len = *-no_vbxe_msg

; --- Modules ---
        icl 'vbxe.asm'
        icl 'game.asm'
        icl 'weapons.asm'
        icl 'weapons_hitscan.asm'
        icl 'player.asm'
        icl 'player_proj.asm'
        icl 'pickups.asm'
        icl 'decorations.asm'
        icl 'barrel.asm'
        icl 'enemies.asm'
        icl 'enemies_attack.asm'
        icl 'enemies_alert.asm'
        icl 'enemies_render.asm'
        icl 'enemies_proj.asm'
        icl 'renderer.asm'
        icl 'hud.asm'
        icl 'menu.asm'
        icl 'menu_draw.asm'
        icl 'dirty.asm'
        icl 'door.asm'
        icl 'switches.asm'
        icl 'sound.asm'
        icl 'data.asm'

        icl 'uploads.asm'
        icl 'uploads_title.asm'

;==============================================
; INIT OVERLAY SEGMENT ($6000)
; These procs run once during init_game, then memory is free.
; Must be the LAST org $6000 segment (after all uploads).
;==============================================
        org $6000

.proc init_enemies
        ldx #0
?lp     cpx #NUM_ENEMIES
        bcs ?done
        lda #1
        sta en_act,x
        lda enemy_spawn_type,x
        sta en_type,x
        txa
        asl
        tay
        lda enemy_spawn_x,y
        sta en_x,x
        lda enemy_spawn_x+1,y
        sta enxhi,x
        lda enemy_spawn_y,x
        clc
        adc #16
        sta en_y,x
        lda #0
        sta en_cooldown,x
        sta envely,x
        sta en_gib,x
        sta en_tcnt,x
        sta envelx,x
        sta en_pain_tmr,x
        lda #60
        sta en_atk,x
        lda enemy_spawn_dir,x
        sta en_dir,x
        lda enemy_spawn_type,x
        tay
        lda en_hp_tab,y
        sta en_hp,x
        lda en_x,x
        sec
        sbc #40
        bcs ?min_ok
        lda #0
?min_ok sta en_xmin,x
        lda en_x,x
        clc
        adc #40
        bcc ?max_ok
        lda #255
?max_ok sta en_xmax,x
        inx
        jmp ?lp
?done
?clr    cpx #MAX_ENEMIES
        bcs ?ret
        lda #0
        sta en_act,x
        inx
        jmp ?clr
?ret    rts
.endp

.proc init_pickups
        lda #0
        sta zparmor
        sta zpkeys
        ldx #0
?lp     cpx #NUM_PICKUPS
        bcs ?done
        lda #1
        sta pk_act,x
        lda pickup_spawn_x,x
        sta pk_x,x
        lda pickup_spawn_xhi,x
        sta pk_xhi,x
        lda pickup_spawn_y,x
        clc
        adc #16
        sta pk_y,x
        lda pickup_spawn_type,x
        sta pk_type,x
        inx
        jmp ?lp
?done
?clr    cpx #MAX_PICKUPS
        bcs ?ret
        lda #0
        sta pk_act,x
        inx
        jmp ?clr
?ret    rts
.endp

.proc init_decorations
        ldx #0
?lp     cpx #NUM_DECOR
        bcs ?done
        lda #1
        sta dc_act,x
        lda decor_spawn_x,x
        sta dc_x,x
        lda decor_spawn_xhi,x
        sta dc_xhi,x
        lda decor_spawn_y,x
        clc
        adc #16
        sta dc_y,x
        lda decor_spawn_type,x
        sta dc_type,x
        lda #0
        sta dc_hp,x
        sta dc_timer,x
        lda decor_spawn_type,x
        cmp #DC_BARREL
        bne ?nob
        lda #BARREL_HP
        sta dc_hp,x
        jsr barrel_set_solid
?nob    inx
        jmp ?lp
?done
?clr    cpx #MAX_DECOR
        bcs ?ret
        lda #0
        sta dc_act,x
        inx
        jmp ?clr
?ret    rts
.endp

.proc init_doors
        lda #0
        sta num_doors
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        lda #0
        sta id_row
?rlp    lda #0
        sta id_col
?clp    ldy id_row
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ldy id_col
        lda (ztptr),y
        cmp #TILE_DOOR_ID
        beq ?found_door
        cmp #TILE_DOOR_RED
        beq ?found_red
        cmp #TILE_DOOR_BLUE
        beq ?found_blue
        cmp #TILE_DOOR_YEL
        beq ?found_yel
        jmp ?next
?found_red
        lda #1
        jmp ?add_door
?found_blue
        lda #2
        jmp ?add_door
?found_yel
        lda #4
        jmp ?add_door
?found_door
        lda #0
?add_door
        sta id_key
        ldx num_doors
        cpx #MAX_DOORS
        bcs ?next
        lda id_col
        sta door_col,x
        lda id_row
        sta door_row,x
        lda #0
        sta door_state,x
        sta door_timer,x
        lda id_key
        sta door_key,x
        ldy id_col
        lda (ztptr),y
        sta door_tile,x
        inc num_doors
?next   inc id_col
        lda id_col
        cmp #MAP_W
        bcc ?clp
        inc id_row
        lda id_row
        cmp #MAP_H
        bcc ?rlp
        lda #0
        sta VBXE_BANK_SEL
        rts
id_col  dta 0
id_row  dta 0
id_key  dta 0
.endp

.proc init_render
        jsr clear_dirty_all
        lda #$00
        sta zbuf_hi
        jsr clear_hud_area
        lda #SCR1_HI
        sta zbuf_hi
        jsr clear_hud_area
        lda #$00
        sta zbuf_hi
        jsr setup_dirty_ptr
        jsr clear_screen
        jsr render_tiles
        jsr render_static
        jsr wait_blit
        lda #SCR1_HI
        sta zbuf_hi
        jsr setup_dirty_ptr
        jsr clear_screen
        jsr render_tiles
        jsr render_static
        jsr wait_blit
        lda #SCR1_HI
        sta zbuf_hi
        rts
.endp

        run main
