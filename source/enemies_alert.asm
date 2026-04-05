;==============================================
; DOOM2D - Enemy alert system (sound-based)
; enemies_alert.asm
;==============================================

; ============================================
; ALERT ENEMIES BY SOUND (player fired weapon)
; All alive enemies within earshot turn to face player
; ============================================
.proc alert_enemies_sound
        ldx #0
?lp     lda en_act,x
        cmp #1              ; only alive enemies
        bne ?nx
        ; Check if sound can reach enemy (no solid wall between)
        stx aes_idx
        jsr can_hear
        pha                 ; save result
        ldx aes_idx
        pla                 ; restore A (sets Z flag)
        beq ?nx             ; Z=1 → blocked by wall
        ; Turn to face player (16-bit compare)
        lda enxhi,x
        cmp zpx_hi
        bcc ?fr
        bne ?fl
        lda en_x,x
        cmp zpx
        bcc ?fr
?fl     lda #1              ; player is left
        bne ?sd
?fr     lda #0              ; player is right
?sd     sta en_dir,x
        lda #1
        sta en_cooldown,x   ; mark as alerted
?nx     inx
        cpx #MAX_ENEMIES
        bcc ?lp
        rts
aes_idx dta 0
.endp

; ============================================
; CAN HEAR - check if sound travels from player to enemy
; Walk tile-by-tile horizontally at enemy's row.
; If any solid tile blocks the path → can't hear.
; Input: X = enemy index
; Output: Z=0 (can hear), Z=1 (blocked)
; ============================================
.proc can_hear
        jsr get_enemy_tile_col
        sta ch_ecol
        jsr get_player_tile_col
        sta ch_pcol
        ; Rows
        lda en_y,x
        lsr
        lsr
        lsr
        lsr
        sta ch_erow
        ; Enable map access
        lda #BANK_EN+BANK_MAP
        sta VBXE_BANK_SEL
        ; --- Horizontal scan (on enemy's FEET row) ---
        ldy ch_erow
        jsr ?hscan_row
        beq ?h2
        jmp ?blocked
?h2     ; --- Horizontal scan (on enemy's CHEST row = feet-1) ---
        lda ch_erow
        beq ?hok            ; row 0 = can't go higher
        sec
        sbc #1
        tay
        jsr ?hscan_row
        beq ?hok
        jmp ?blocked
?hok    ; Can hear — restore bank and return
        lda #0
        sta VBXE_BANK_SEL
        lda #1              ; Z=0 → can hear
        rts
; Scan horizontal row Y for solid tiles between ecol and pcol
; Input: Y = row to scan
; Output: Z=1 (clear), Z=0 (blocked)
?hscan_row
        lda map_row_lo,y
        sta ztptr
        lda map_row_hi,y
        sta ztptr+1
        ; Sort: ch_cur = min(ecol,pcol)+1, ch_end = max(ecol,pcol)
        lda ch_ecol
        ldy ch_pcol
        cpy ch_ecol
        bcs ?hr_s
        tya                 ; swap: A=smaller
        ldy ch_ecol         ; Y=larger
?hr_s   clc
        adc #1
        sta ch_cur
        sty ch_end
?hr_lp  lda ch_cur
        cmp ch_end
        bcs ?hr_ok
        tay
        lda (ztptr),y
        tay
        lda tile_solid,y
        bne ?hr_blk
        inc ch_cur
        jmp ?hr_lp
?hr_ok  lda #0              ; Z=1 → clear
        rts
?hr_blk lda #1              ; Z=0 → blocked
        rts

?blocked
        lda #0
        sta VBXE_BANK_SEL
        lda #0              ; Z=1 → blocked
        rts
ch_ecol dta 0
ch_pcol dta 0
ch_erow dta 0
ch_cur  dta 0
ch_end  dta 0
.endp
