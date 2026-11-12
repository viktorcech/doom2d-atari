;==============================================
; Sprite + enemy type definitions
; sprite_defs.asm
;
; Monsters, the player and items: gen/mon_frames.asm + mon_anims.asm;
; HUD icons and projectiles (blit_sprite): gen/spr_small.asm. Both made
; by tools/prepare_sprites.py from the Doom 2D Forever graphics.
;==============================================

        icl 'gen/spr_small.asm'

; Enemy types
EN_ZOMBIE                       equ 0
EN_IMP                          equ 1
EN_PINKY                        equ 2
EN_CACO                         equ 3
EN_SHOTGUN                      equ 4
EN_BARON                        equ 5
EN_LOSTSOUL                     equ 6

; Enemy health (g_monsters.pas MONSTERTABLE.Health)
en_hp_tab
        dta 15  ; zombie
        dta 25  ; imp
        dta 60  ; pinky (demon)
        dta 100 ; caco
        dta 20  ; shotgun (serg)
        dta 150 ; baron
        dta 60  ; lostsoul

; Enemy sound lookup tables (indexed by type, $FF = no sound)
en_death_sfx
        dta SFX_PODEATH    ; zombie
        dta SFX_IMPDEATH   ; imp
        dta SFX_SGTDTH     ; pinky
        dta SFX_CACDTH     ; caco
        dta SFX_PODEATH    ; shotgun (same as zombie)
        dta SFX_BRSDTH     ; baron
        dta SFX_FIRXPL     ; lostsoul (fireball explosion)

; Pain SFX lookup (indexed by enemy type)
en_pain_sfx
        dta SFX_OOF            ; zombie
        dta SFX_OOF            ; imp
        dta SFX_DMPAIN         ; pinky
        dta SFX_DMPAIN         ; caco
        dta SFX_OOF            ; shotgun
        dta SFX_OOF            ; baron
        dta SFX_OOF            ; lostsoul

en_sight_sfx
        dta SFX_POSIGHT    ; zombie
        dta SFX_IMPSIGHT   ; imp
        dta SFX_SGTSIT     ; pinky
        dta SFX_CACSIT     ; caco
        dta SFX_POSIGHT    ; shotgun (same as zombie)
        dta SFX_BRSSIT     ; baron
        dta SFX_SKLATK     ; lostsoul (sight = attack sound, same as DOOM)
