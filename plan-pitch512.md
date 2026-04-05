# Plan: Buffer Pitch 512 pre smooth sky parallax

## Problém
Sky parallax pri horizontálnom pohybe seká — sky sa hýbe 1:1 s kamerou medzi tile hranicami (cez XDL cam_sub), potom skočí dozadu ~11px pri tile boundary. Príčina: sky (pitch 512) a screen buffer (pitch 336) majú rôzny pitch.

## Riešenie
Zväčšiť buffer pitch na 512. Sky a buffer budú mať rovnaký pitch → sky sa renderuje priamo do buffra na parallax pozíciu. XDL scrolluje 320px okno cez 512px buffer. Sky stojí na mieste medzi tile hranicami (správny parallax).

## Prečo to funguje
- Sky blit: `clear_screen` blituje sky na pozíciu `sky_x_lo` v buffri (pitch 512 = sky pitch 512)
- XDL OVADR: `cam_sub` (0-15) posúva 320px okno v 512px buffri
- Na obrazovke: `sky[sky_x_lo + cam_sub]` — sky sa hýbe s kamerou (1:1)
- Pri tile boundary: `sky_x_lo` sa zmení o ~4px (delta) — plynulý skok dopredu
- Medzi tile boundaries: `sky_x_lo` je konštantný, `cam_sub` posúva → sky stojí!
- Výsledok: sky sa hýbe LEN pri tile boundary, ~4px dopredu. Žiadne skoky dozadu!

Wait - toto je ROVNAKÉ ako teraz! Sky sa hýbe 1:1 s cam_sub...

## Prepočet - prečo 512 pitch pomáha

VLASTNE: s pitch 512 je výhoda iná. Sky sa blituje do buffra na pozíciu sky_x_lo.
Buffer[sky_x_lo] = sky[0]. Buffer[sky_x_lo + 1] = sky[1]. Atď.

XDL zobrazuje buffer[cam_sub .. cam_sub+319]. Na obrazovke vidíme:
- Pixel 0 = buffer[cam_sub] = sky[cam_sub - sky_x_lo] (ak cam_sub >= sky_x_lo)

Hmm, to nie je správne. Pozrime sa inak:

clear_screen blituje 320px sky (od sky[sky_x_lo]) do buffer[0..319].
XDL zobrazí buffer[cam_sub..cam_sub+319].
Screen pixel 0 = buffer[cam_sub] = sky[sky_x_lo + cam_sub].

Toto je ROVNAKÉ správanie ako teraz (pitch 336)!

## SKUTOČNÁ výhoda 512 pitch

S pitch 512 a sky pitch 512: clear_screen NEMUSÍ blitovať sky riadok po riadku s konverziou pitchu. Blituje sa 1:1 (src step = dst step = 512).

Ale to je len performance optimalizácia, nie parallax fix.

## REÁLNY parallax fix s 512 pitch

S 512px buffer: `RENDER_COLS = 32` (512/16). Tiles sa renderujú na 32 stĺpcov. Padding = 192px (512-320). XDL cam_sub range = 0-191 (namiesto 0-15)!

ALE: cam_sub je odvodzovaný z camera pixel X: `cam_sub = cam_x & 15`. S 512 pitch by mohol byť `cam_sub = cam_x & (512-320-1)` — no to nedáva zmysel.

Vlastne: s 512 pitch sa nič nemení na tom, ako cam_sub funguje. Tiles sú stále na 16px hraniciach. cam_sub je stále 0-15. Padding je 192 bytov ale cam_sub používa len 0-15.

## ZÁVER: 512 pitch NERIEŠI parallax problém

512 pitch dáva len performance benefit (sky a buffer majú rovnaký pitch). Parallax problem je rovnaký: cam_sub (0-15) posúva sky rovnako ako tiles.

Smooth parallax by vyžadoval buď:
1. Väčší sky (960px+) s väčším delta
2. XDL split (tile misalignment)
3. Per-frame full redraw (25fps)

## Alternatíva: ANTIC + VBXE overlay

Commando používa textový mode. V bitmap mode je OVSCRL ignorovaný.

Čo ak sky zobrazíme cez ANTIC (pod VBXE overlay) a tiles/sprites cez VBXE overlay s transparenciou (index 0)?

ANTIC limity: max 4 farby v mode E, 2 farby v mode F. Nedostatočné pre 256-farebný sky.

## Alternatíva: Väčší sky v existujúcom 336 pitch

Zostaňme pri 336 pitch. Zväčšíme sky na max čo sa zmestí do VRAM.
Problém: sky > 512px vyžaduje iný pitch pre sky a buffer, čo komplikuje address calculations.

## ROZHODNUTIE

Pitch 512 refactor NESTOJÍ za to — nerieši parallax. Treba iný prístup.
