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
        org $0690           ; after generic_upload ($0630-$0688)
.proc early_init
        lda #0
        sta SDMCTL          ; disable ANTIC DMA (OS shadow)
        sta $D400           ; DMACTL hardware register
        sta COLOR4          ; black background
        lda $D301
        ora #$02            ; BASIC off ($A000-$BFFF = RAM for the sky data)
        sta $D301
        ; Rapidus ('6S' at $FF0000): the MEMAC windows' 16K blocks slow (MCR
        ; bits 1-2), a fast block reads the card's SRAM instead of VRAM.
        ; Z after the decimal adc: CMOS only; after rep: 65816 only.
        lda #$99
        clc
        sed
        adc #1
        cld
        bne ?no
        opt c+
        rep #$02
        beq ?no
        lda.l $FF0000
        cmp #'6'
        bne ?no
        lda.l $FF0001
        cmp #'S'
        bne ?no
        lda.l $FF0080           ; (no tsb long)
        ora #$06
        sta.l $FF0080
        opt c-
?no     rts
.endp
        ert *>$0700             ; the boot loader
        ini early_init


;==============================================
; ASSET UPLOADS — INI segments that run during XEX load
; Each loads data at $6000, uploads to VRAM, then next overwrites $6000.
; Must come BEFORE main segment so main code above $6000 isn't clobbered.
;==============================================
        icl 'uploads.asm'
        icl 'uploads_title.asm'


;==============================================
        org $2000
;==============================================
        icl 'sound.asm'         ; first: its IRQ handlers in page $20 (MEMAC-B)

.proc main
        sei

        ; Black screen during init (no ANTIC DMA, black background)
        lda #0
        sta SDMCTL
        sta COLOR4

        ; --- VBXE detection: an FX core (CORE_TYPE $10) of revision 1.27..1.2F
        ; (the blitter's containers and MODE 7) on this XEX's page VBXE_PAGE
        ; (the boot loader loaded the XEX built for the page it found) ---
        lda VBXE_VCTL           ; CORE_TYPE
        cmp #$10
        bne ?no_fx
        lda VBXE_XDL0           ; CORE_REVISION
        and #$7F
        clc                     ; C=1: $27..$2F (2026-11-02 6502-loops-tables-smc.md
        adc #$FF-$2F            ; "Range test: clc / adc #$FF-hi / adc #hi-lo+1")
        adc #$2F-$27+1
        bcs ?vbxe_ok
        lda #<old_core_msg      ; an older core: say so instead
        sta ?pm+1
        lda #>old_core_msg
        sta ?ph+1
        lda #old_core_len
        sta ?pl+1

?no_fx  ; VBXE not found / too old: restore default Atari screen
        lda #$22
        sta SDMCTL          ; enable ANTIC DMA
        ; COLOR4 (black border) is still 0 from the top of main
        lda #0
        sta $034B           ; ICAX2 for the OPEN below (nothing between writes it)
        lda #$94
        sta COLOR2          ; blue text bg
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
        jsr CIOV
        ; Print message
        ldx #0
        lda #$09            ; PUT RECORD
        sta $0342           ; ICCOM
?pm     lda #<no_vbxe_msg       ; (patched: old_core_msg)
        sta $0344           ; ICBAL
?ph     lda #>no_vbxe_msg
        sta $0345           ; ICBAH
?pl     lda #<no_vbxe_len
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
        jsr lists_init          ; both list sets (frame.asm)
        ; Note: no init_clear here - title graphic is already in screen buffers

        ; Everything ready: NOW enable XDL display. ANTIC DMA stays OFF for
        ; good (the sky is blitted, sky.asm): colour-0 overlay pixels show
        ; the black border colour.
        lda #VC_XDL_ON
        sta VBXE_VCTL
        lda #$00
        sta VBXE_XDL0
        lda #$F0
        sta VBXE_XDL1
        lda #$07
        sta VBXE_XDL2

        ; Detect PAL/NTSC
        lda PAL             ; GTIA PAL register: bits 1-3 = %000 PAL, %111 NTSC
        ldx #50             ; PAL = 50 fps
        and #$0E            ; (Z for the beq: ldx is before it)
        beq ?thr_ok
        ldx #60             ; NTSC = 60 fps
?thr_ok stx fps_thr         ; precomputed once: main loop compares directly

        ; Digital sound engine init (POKEY + Timer 1 IRQ hook)
        jsr snd_init

        ; Init double buffer: draw to screen 1, display screen 0
        lda #SCR1_HI            ; $02
        sta zbuf_hi

        cli

; =============================================
; TITLE SCREEN (menu logic in menu.asm)
; =============================================
        jsr menu_title_screen

        ; Check if LOAD GAME was selected
        lda menu_result
        cmp #2
        beq ?loaded_game

?new_game
        lda start_level         ; mapedit: play from level N
        sta current_level
        jsr load_level
        jsr init_game
        bne ?loaded_game        ; Z=0: init_game ends on lda #$FF / sta

        ; --- NEXT LEVEL: keep player weapons/hp/armor ---
?next_level
        jsr load_level          ; (writes no level_complete / stat_*)
        jsr init_level_ents     ; level_complete + stats = 0, stat_total_en,
                                ; enemies, pickups (zpkeys = 0), decorations
        jsr player_spawn        ; level spawn, at rest (keep everything else)

?loaded_game
        jsr init_render         ; also forces the HUD full redraw

; =============================================
; MAIN GAME LOOP — double-buffered, 1 frame per VBLANK
;
; Each frame:
;   1. Handle ESC (pause menu)
;   2. Update game logic (player, enemies, projectiles, items, doors)
;   3. Restore dirty tiles (erase sprites from last frame)
;   4. Render all sprites and HUD to back buffer
;   5. Wait for blitter + VBLANK
;   6. Swap display/draw buffers (XDL shows back, draw to front)
;
; Double buffering: zbuf_hi alternates between $00 (buffer 0)
; and $02 (buffer 1, at VRAM $020000). One buffer is displayed
; while the other is drawn to, eliminating flicker.
; =============================================
?loop
        ; --- ESC = open pause menu ---
        lda CH                  ; keyboard scan code register
        cmp #$1C                ; ESC key
        bne ?chk_f
        lda #$FF
        sta CH                  ; clear key
        jsr menu_pause          ; A = menu_result, N/Z from it
        beq ?new_game           ; A=0: user chose New Game
        bpl ?loaded_game        ; A=2: user loaded a save
                                ; A=$FF (resume) falls in: $FF <> $38 -> ?no_esc
?chk_f  cmp #$3D                ; G key: god mode (testing; D2DF FGodMode:
        bne ?chk_f2             ; no damage)
        lda #$FF
        sta CH
        lda pl_god
        eor #1
        sta pl_god
        bpl ?no_esc             ; (always: 0 / 1)
?chk_f2 cmp #$38                ; F key: toggle the FPS counter
        bne ?no_esc
        lda #$FF
        sta CH                  ; clear key
        lda fps_on
        eor #1
        sta fps_on
        lda #2
        sta fps_dirty           ; draw / clear it in both buffers
?no_esc                         ; (an_tk, the last frame's animation ticks: lg_pre)
        inc zfr                 ; global frame counter (used for animations)

        ; D2DF g_window: as many logic steps as the time passed (a step = a
        ; vblank, its speeds are 50 Hz ones), then one draw; the last step
        ; below with the camera and the window blit, the others first
        lda RTCLOK3
        tax
        sec
        sbc lg_last
        stx lg_last
        bne ?lg1
        lda #1                  ; (the first frame)
?lg1    cmp #LG_MAX+1
        bcc ?lg2
        lda #LG_MAX
?lg2    sta lg_n
?lgs    jsr stat_tick           ; level time: one vblank
        dec lg_n
        beq ?lgl                ; the last step: the frame's own logic
        lda zphp
        beq ?lgl                ; dead: no player steps
        jsr logic_step
        lda level_complete
        beq ?lgs
?lgl

        ; --- LOGIC PHASE ---
        ; The camera + background composite start right after player+enemy
        ; updates (the camera only needs the player position): the 320x192
        ; window blit then runs in parallel with the rest of the logic
        ; instead of stalling the CPU before the sprite phase.
        jsr read_input
        lda zphp
        bne ?alive
        jsr player_dead         ; death animation (no player control)
        jsr update_camera
        jsr composite_frame          ; parallax sky + tile window
        jsr update_enemies           ; after the window blit started (fire early)
        lda dc_exp_cnt          ; inlined update_decorations idle test
        beq ?skip_logic
        jsr update_decorations
        jmp ?skip_logic
?alive
        jsr player_update
        jsr update_camera
        ; the 320x192 window blit is the frame's longest blitter job: start it
        ; before the enemy AI (vbxe-blitter: fire early); update_enemies reads
        ; no camera.
        jsr composite_frame          ; parallax sky + tile window (async)
        jsr update_enemies
        jsr proj_update         ; player projectiles
        jsr eproj_update        ; enemy projectiles (imp/caco fireballs)
        jsr update_pickups
        lda dc_exp_cnt          ; inlined update_decorations idle test
        beq ?no_dc
        jsr update_decorations
?no_dc  jsr update_triggers     ; (map changes are patched into the canvas NEXT
                                ;  frame - composite already ran this frame)
        jsr sound_update
        ; --- EXIT SWITCH CHECK ---
        lda level_complete
        beq ?no_exit
        ; 2026-04-08: Show end-level stats before advancing
        jsr show_level_stats
        ; Advance to next level (wrap if last)
        inc current_level
        lda current_level
        cmp num_levels
        bcc ?next_ok
        lda #0
        sta current_level       ; wrap to level 0
?next_ok
        jmp ?next_level
?no_exit
?skip_logic

        ; --- RENDER PHASE: world sprites over the composited background ---
        ; Draw all world sprites with camera offset (spr_cam=1)
        lda #1
        sta spr_cam
        jsr fore_restore             ; last frame's foreground slots back to sprites
        lda #0
        sta zdy_hi                   ; 8-bit-Y entities: world Y hi = 0 (player sets its own)
        sta sr_n                     ; no world sprite rect yet (fore_part's reject)
        jsr render_static            ; all pickups + decorations
        jsr render_exploding
        jsr render_enemies
        lda #0
        sta zdy_hi                   ; enemies set 16-bit zdy_hi; reset for 8-bit-Y projectiles
        jsr render_projs
        jsr render_eproj
        jsr render_player
        jsr render_tele              ; the teleport flash (g_GFX_Draw: before the liquids)
        jsr bl_draw                  ; the blood (blood.asm)
        jsr liq_filter              ; water / acid over all of them (liquid.asm)
        jsr render_fore              ; PANEL_FORE over every world sprite
        ; HUD overlay (screen-fixed, no camera offset)
        lda #0
        sta spr_cam
        jsr render_hud
        lda fps_dirty           ; FPS counter changed / toggled?
        beq ?no_fps
        jsr fps_draw            ; (into the sprite list too)
?no_fps
fc_call jsr frame_chain         ; this frame's lists, chained (frame.asm); a
                                ; message on: jsr msg_frame (hud.asm, SMC)

        ; --- SYNC PHASE (Wolfette's pipeline): frame N, STARTed a frame
        ; ago, drew while the CPU built this one ---
        jsr lg_pre              ; the owed logic step, in the wait; wait_blit

        ; VBLANK wait
        lda RTCLOK3             ; frame count kept as the cmp # operand (SMC):
        sta ?vs_t+1             ; X/Y stay untouched
?vsync  lda RTCLOK3
?vs_t   cmp #0
        beq ?vsync

        ; Show what frame N drew (the other buffer), then START this frame
        ; into the one shown until now: it is hidden from this vblank on
        lda #BANK_EN+BANK_XDL
        sta VBXE_BANK_SEL
        lda zbuf_hi
        eor #SCR1_HI
        sta MEMW+[VRAM_XDL&$FFF]+8
        lda zbuf_hi             ; flip the draw target: $00 <-> $02 (before
        eor #SCR1_HI            ; frame_go: its ls_stamp stamps the next
        sta zbuf_hi             ; frame's bank into the other set)
        jsr frame_go            ; START, then build the next in the other set
        jsr fps_tick            ; count this shown frame (FPS counter)
        jmp ?loop
.endp

; --- VBXE not detected message ---
no_vbxe_msg
        dta c'VBXE NOT DETECTED!'
        dta $9B                    ; EOL
no_vbxe_len = *-no_vbxe_msg
old_core_msg
        dta c'VBXE FX CORE 1.27 REQUIRED!'
        dta $9B
old_core_len = *-old_core_msg

; --- Modules ---
        icl 'vbxe.asm'
        icl 'camera.asm'
        icl 'sky.asm'
fore_save = *
        org FORE_RAM+FORE_SECTORS*128   ; code past its rects, below $C000
        icl 'fore.asm'
        ert *>$BE00
; The RAM the ANTIC sky had ($A000-$B68F): the liquid rects + their code,
; the frame's list sets
        org LIQ_CODE
        icl 'liquid.asm'
        icl 'frame.asm'
        icl 'blood.asm'
; LG_PRE - before the vsync wait (the frame's lists are built): the frame's
; animation ticks end here (an_tk: anim_tick's), and if a vblank has passed
; since the frame's logic and the next is far enough (VCOUNT outside
; LG_VC..123: 88 scan lines left at least; measured: 80 the best of 60 /
; 80 / 95 / 105), the logic step the next frame owes runs now, in the
; wait, not after the flip.
LG_VC   = 80
.proc lg_pre
        lda an_cnt
        sta an_tk
        lda #0
        sta an_cnt
        lda RTCLOK3
        cmp lg_last
        beq ?r                  ; within a vblank: nothing owed
        lda zphp
        beq ?r                  ; dead: no player steps
        lda VCOUNT              ; C=1 inside LG_VC..123 (6502-loops-tables-smc:
        clc                     ; the range test)
        adc #$FF-123
        adc #123-LG_VC+1
        bcs ?r
        inc lg_last             ; the step's vblank is counted
        jsr stat_tick
        jsr logic_step
?r      jmp wait_blit           ; (the main loop's wait: its call is this one)
.endp

; LK_ROW / LK_COL - en_look's map looks (enemies_ai.asm: no room there), as
; check_solid16 does them, split: lk_row = the row of gt_py_hi:gt_py: its
; bank on and ztptr = its base, C=1 off the map; lk_col = the cell of
; gt_px_hi:gt_px in that row: Z=0 a wall (off the map too). Keep X.
.proc lk_row
        ldy gt_py
        lda gt_py_hi            ; row = hi*32 | lo/8 (get_tile_at16)
        lsr
        ror
        ror
        ror
        ora div8_lut,y
        cmp #MAP_H
        bcs ?r
        tay
        lda map_row_bank,y
        sta VBXE_BANK_SEL
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
?r      rts
.endp
.proc lk_col
        ldy gt_px
        lda gt_px_hi
        lsr
        ror
        ror
        ror
        ora div8_lut,y
        cmp #MAP_W
        bcs ?w
        tay
        lda (ztptr),y
        bmi ?p                  ; a background tile: clear
        tay
        lda tile_solid,y
        rts
?p      lda #0
        rts
?w      lda #1                  ; off the map: a wall
        rts
.endp
        ert *>sr_x0
; Y-address LUT (Y*320 lo/hi, 200 rows): one page each, no page crossing
        org $BE00
y_addr_lo
:200    dta <[#*320]
        ert *>$BEC8
        org $BEC8                       ; the rest of the page: the main loop's steps
; LOGIC_STEP - one more 50 Hz step of the world (main loop: the time passed
; beyond the frame's own step); no camera, no window blit
LG_MAX = 4                      ; steps a frame at most (no spiral)
lg_last dta 0                   ; RTCLOK3 at the previous frame
lg_n    dta 0
.proc logic_step
        jsr player_update
        jsr update_enemies
        jsr proj_update
        jsr eproj_update
        jsr update_pickups
        lda dc_exp_cnt
        beq ?nd
        jsr update_decorations
?nd     jsr update_triggers
        jmp sound_update        ; the lock counts steps as zpwcool does: the
.endp                           ; next shot's sound is not skipped

; STAT_TICK - the level timer: one vblank (seconds = fps_thr vblanks)
.proc stat_tick
        inc stat_frames
        lda stat_frames
        cmp fps_thr             ; 60 NTSC / 50 PAL (precomputed at init)
        bcc ?r
        lda #0
        sta stat_frames
        inc stat_time_lo
        bne ?r
        inc stat_time_hi
?r      rts
.endp

        ert *>$BF00
        org $BF00
y_addr_hi
:200    dta >[#*320]
        icl 'pj_shot.asm'
        ert *>$C000                     ; (the OS ROM; enemy arrays: LVL_BUF)
        org fore_save
        icl 'game.asm'
        icl 'weapons.asm'
        icl 'weapons_hitscan.asm'
        icl 'player.asm'
        icl 'player_proj.asm'
        icl 'pickups.asm'
        icl 'decorations.asm'
        icl 'barrel.asm'
        icl 'enemies.asm'
        icl 'enemies_ai.asm'
        icl 'enemies_render.asm'
        icl 'enemies_proj.asm'
        icl 'renderer.asm'
        icl 'hud.asm'
        icl 'menu.asm'
        icl 'menu_draw.asm'
        icl 'triggers.asm'
        icl 'anim.asm'
        icl 'diskio.asm'
        icl 'savegame.asm'
        icl 'data.asm'

;==============================================
; INIT PROCEDURES — now part of main segment
; No longer need separate org: main segment extends past $6000
; up to $8FFF (MEMAC-A window starts at $9000).
; Called at runtime (New Game, level transition, death restart).
;==============================================

.proc init_enemies
        ldx #0
?lp     cpx num_en
        bcs ?done
        lda #1                  ; alive; every monster starts asleep (D2DF)
        sta en_act,x
        lda enemy_spawn_type,x  ; (stores to distinct arrays: order is free)
        sta en_type,x
        tay
        lda en_hp_tab,y
        sta en_hp,x
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
        lda enemy_spawn_yhi,x
        adc #0                  ; 16-bit: carry from +16
        sta en_y_hi,x
        txa                     ; the sleepers' 1 s look (th_sleep: 18 AI ticks)
        and #15                 ; starts out of step: no frame with every
        sta en_sleep,x          ; monster's en_look at once
        lda #0                  ; ES_SLEEP and every counter/velocity at rest
        sta en_state,x
        sta en_ammo,x
        sta en_pain,x
        sta en_vx,x
        sta en_vxf,x
        sta en_vyf,x
        sta en_xf,x
        sta en_yf,x
        sta en_hit,x
        sta en_tick,x
        sta en_tgt,x            ; the target: the player
        sta en_ttm,x
        sta en_atk,x
        sta envely,x
        sta en_gib,x
        sta envelx,x
        sta en_anim,x           ; ANIM_SLEEP, frame 0
        sta en_afr,x
        sta en_acnt,x
        ert ES_SLEEP<>0 .or ANIM_SLEEP<>0
        lda enemy_spawn_dir,x
        sta en_dir,x
        inx
        bne ?lp                 ; X = 1..num_en (<= 255) here: never 0
?done   lda #0
?clr    cpx #MAX_ENEMIES
        bcs ?ret
        sta en_act,x
        inx
        bne ?clr                ; X <= MAX_ENEMIES: never 0
?ret    rts
.endp

.proc init_pickups
        lda #0
        sta zparmor
        sta zpkeys
        tax                     ; X = 0
?lp     cpx num_pk
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
        lda pickup_spawn_yhi,x
        adc #0                  ; 16-bit: carry from +16
        sta pk_y_hi,x
        lda pickup_spawn_type,x
        sta pk_type,x
        txa
        tay
        jsr pk_set_tile         ; keeps X, Y
        inx
        bne ?lp                 ; X = 1..num_pk (<= 255) here: never 0
?done   stx pk_end              ; X = num_pk
        lda #0
?clr    cpx #MAX_PICKUPS
        bcs ?ret
        sta pk_act,x
        inx
        bne ?clr                ; X <= MAX_PICKUPS: never 0
?ret    sta pf_n                ; A = 0: nothing falls yet
        ldx #PF_MAX-1           ; every fall slot free
        lda #$FF
?pf     sta pf_i,x
        dex
        bpl ?pf
        jmp pk_wake             ; items in the air fall (D2DF: Fallable)
.endp

; INIT LEVEL ENTITIES - shared by a new game and the next level:
; level_complete + end-level stats = 0, enemy total, enemies/pickups/decorations
.proc init_level_ents
        lda #0
        sta level_complete
        sta stat_kills
        sta stat_time_lo
        sta stat_time_hi
        sta stat_frames
        lda num_en
        sta stat_total_en       ; remember total enemies for % calc
        jsr init_enemies
        jsr init_pickups
        ert *<>init_decorations ; falls through (was jmp init_decorations)
.endp

.proc init_decorations
        lda #0
        sta dc_exp_cnt
        tax                     ; X = 0
?lp     cpx num_dc
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
        lda decor_spawn_yhi,x
        adc #0                  ; 16-bit: carry from +16
        sta dc_y_hi,x
        lda #0
        sta dc_timer,x
        lda #BARREL_HP
        sta dc_hp,x
        jsr barrel_set_solid    ; preserves X (the loop relied on it already)
        inx
        bne ?lp                 ; X = 1..num_dc (<= 255) here: never 0
?done   lda #0
?clr    cpx #MAX_DECOR
        bcs ?ret
        sta dc_act,x
        inx
        bne ?clr                ; X <= MAX_DECOR: never 0
?ret    rts
.endp

.proc init_render
        jsr pl_reset            ; drop the old level's unstarted pre lists (a
                                ; frame copy would hit the new tileset)
        ; Full black clear of both buffers (320x200, kills all garbage)
        lda #$00
        sta zbuf_hi
        jsr clear_full_black
        lda #SCR1_HI
        sta zbuf_hi
        jsr clear_full_black
        ; Per-level horizontal camera limit from the map's actual width
        jsr compute_max_cam
        lda #1
        sta cam_vsnap           ; snap camera Y (don't dead-zone a stale cam_y)
        jsr update_camera
        ; New map in BANK_MAP -> the bg canvas is stale even if cam_tcol
        ; happens to match the previous level; force a full rebuild.
        lda #$FF
        sta last_cam_tcol
        ; Prime both buffers' background so first swap is clean
        lda #$00
        sta zbuf_hi
        jsr composite_frame
        jsr frame_now           ; run it at once (frame.asm)
        lda #SCR1_HI
        sta zbuf_hi             ; stays SCR1_HI: the loop's first frame draws
        jsr composite_frame     ; it, shows buffer 0 first
        jsr frame_now
        jsr ls_stamp            ; the loop's first set: its slots' bank (frame.asm)
        ; Force HUD full redraw (both callers did this right after)
        lda #$FF
        sta hud_prev_hp
        sta hud_prev_ammo
        sta hud_prev_amhi
        sta hud_prev_weap
        sta hud_prev_armor
        lda #2
        sta hud_frames
        sta hud_full_clear
        rts
.endp

; --- Build guard: main code/data must stay below LVL_BUF ($8400) ---
; load_level writes the .lvl into $8400+, so anything here would be clobbered
; at runtime (KIL). If this fires, the program grew too big — shrink code/data.
        ert *>$8400, 'MAIN segment overflowed into LVL_BUF ($8400) - reduce code size'

        run main
