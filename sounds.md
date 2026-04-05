DOOM 2D - Zvuky (stav 30.3.2026)
==================================

## STAV: FUNGUJE! Digital sample playback cez POKEY

Inspirované analýzou hry Dynakillers (GMG, 1997) a zdrojmi:
- Space Harrier XE sample player (AtariAge)
- DigiCMC (Tajemnice ATARI 6-7/1993)
- Mad Pascal smp.pas (Tebe/Sheddy)
- AtariAge forum: Playing Samples (#123208)
- atarionline.pl forum (#7842)

## PRINCIP

4-bit packed nibbles + POKEY volume-only mode + Timer 1 IRQ:

1. WAV sa skonvertuje na 4-bit nibbles (~4kHz sample rate)
2. Dva samply v jednom bajte (hi nibble + lo nibble)
3. Timer 1 IRQ (VTIMR1 $0210) sa volá na ~3995 Hz
4. IRQ handler zapíše nibble do AUDC4 s volume-only bitom ($10 | nibble)
5. Výstup na kanál 4 (AUDC4 $D207), timer kanál 1 je tichý (AUDC1=0)
6. OS automaticky acknowledge-ne interrupt pred zavolaním handlera
7. Timer 1 sa zapne len počas prehrávania, inak vypnutý (0% CPU idle)

## KĽÚČOVÉ TECHNICKÉ DETAILY

### POKEY registre
- AUDCTL = $00 (64kHz base clock, no channel pairing)
- AUDF1 = 15 → freq = 63921 / 16 = ~3995 Hz
- AUDC1 = $00 (timer kanál tichý - žiadne pískanie!)
- AUDC4 = $10 | nibble (volume-only output)

### IRQ vektor
- VIMIRQ ($0216/$0217) — direct hook (bypasses OS dispatch!)
- OS robí len: CLD → JMP (VIMIRQ), nič viac
- Handler musí: PHA, check IRQST bit 0, acknowledge (POKMSK trick),
  preserve Y, končiť PLA + RTI
- Ak nie Timer 1: PLA + JMP (old_iir) → chain na pôvodný OS IIR
- POKMSK ($0010) MUSÍ byť aktualizovaný (ORA #$01 pred STA IRQEN)!

### On-demand Timer 1
- snd_play: zapne Timer 1 (POKMSK ORA #$01, STA IRQEN, STA STIMER)
- Koniec samplu: vypne Timer 1 (POKMSK AND #$FE, STA IRQEN)
- CPU záťaž len počas prehrávania (~22% pri 4kHz), 0% keď ticho

### Sample formát
- 4-bit unsigned (0-15), packed po 2 v bajte (hi nibble first)
- Sample rate: ~3995 Hz (PAL)
- Veľkosť: ~1KB na 0.5s zvuku
- Konvertor: tools/wav2pokey.py (WAV → bin)

## RAM LAYOUT

### Celková RAM mapa (z build 30.3.2026)
```
$0080-$00D5  Zero page premenné (85B)
$0580-$059x  Upload chunk stubs (reused, ~32B)
$0600-$060A  early_init (11B, temporary)
$2000-$3DCE  Kód - všetky ASM moduly (7631B)
$3DCF-$3F91  Sprite tabuľky (451B)
$3F92-$4791  Mapa (2048B)
$4792-$47CB  Entity spawn tabuľky (58B)
$47CC-$5DCB  Paleta 768B + Tilesheet 4096B + HUD font 768B
$5DCC-$5F5B  Y-address LUT (400B)
$5F5C-$5FB0  Generic upload procedúra (85B)
--- KONIEC HLAVNÉHO PROGRAMU: $5FB0 (16304B) ---
$6000-$91F6  Zvukové sample dáta (12790B) ← PROBLÉM!
$9000-$9FFF  MEMAC-A okno (VBXE VRAM prístup)
```

### Zvukové dáta detail
```
$6000-$63CC  sfx_pistol_data (973B)
$63CD-$6562  sfx_itemup_data (406B)
$6563-$693D  sfx_rocket_data (987B)
$693E-$6DE1  sfx_podeath_data (1188B)
$6DE2-$719F  sfx_posit_data (958B)
$71A0-$7643  sfx_impsit_data (1188B)
$7644-$7B42  sfx_impdth_data (1279B)
$7B43-$7F20  sfx_shotgun_data (990B)
$7F21-$833F  sfx_wpnup_data (1055B)
$8340-$84ED  sfx_punch_data (430B)
$84EE-$91F5  sfx_barexp_data (3336B) ← PRESAHUJE $9000!
             = 12790B použitých
```

### PROBLÉM: MEMAC KOLÍZIA
- Max bezpečný rozsah: $6000-$8FFF = 12288B ($3000)
- Aktuálne použité: 12790B ($31F6) = prekročené o 502B!
- sfx_barexp_data ($84EE-$91F5) zasahuje do MEMAC okna ($9000+)
- IRQ handler `lda (snd_ptr),y` číta VBXE VRAM namiesto sample dát
- Zvuk barrel výbuchu bude poškodený v poslednej štvrtine

### RIEŠENIE: VBXE VRAM pre sample dáta
VBXE má 512KB VRAM, väčšina voľná ($019300+).
Problém: IRQ handler nemôže priamo čítať z VRAM (MEMAC/BANK_SEL
kolízia s blitterom). Potrebný prefetch buffer v main loope.

## VÝKON

VIMIRQ direct hook (bypass OS dispatch):
- IRQ handler: ~83 cyklov/IRQ (bez OS dispatch overhead)
- Pri 4kHz: ~332,000 cyklov/sec = ~17% CPU počas prehrávania
- Timer 1 zapnutý len počas prehrávania, potom 0% CPU
- 20 zvukov v pamäti neovplyvňuje výkon (vždy hrá len 1 naraz)
- Non-Timer1 IRQ (klávesnica atď.): +15 cyklov overhead pre chain

Porovnanie s predchádzajúcim VTIMR1 prístupom:
- VTIMR1 (OS dispatch): ~150 cyklov/IRQ = ~32% CPU ← viditeľné spomalenie
- VIMIRQ (direct hook):  ~83 cyklov/IRQ = ~17% CPU ← takmer bez spomalenia

## SÚBORY

### Zdrojáky
- source/sound.asm — IRQ handler, snd_init, snd_play, sfx tabuľky
- source/constants.asm — POKMSK, VTIMR1, STIMER, IRQEN, AUDC4, SFX_PISTOL

### Nástroje
- tools/wav2pokey.py — konvertor WAV → 4-bit packed nibbles
  ```
  python tools/wav2pokey.py input.wav output.bin [sample_rate]
  ```
  Default rate: 3959 Hz. Robí: trim silence, normalize, resample, quantize.

### Dáta
- data/sfx_pistol_4bit.bin — DSPISTOL 4-bit (973B, 0.49s)
- data/snd_tab_hi.bin — lookup tabuľka (nepoužíva sa, handler robí LSR)
- data/snd_tab_lo.bin — lookup tabuľka (nepoužíva sa)

### Test
- source/test_sound.asm — standalone test (kláves = zvuk)
- bin/test_sound.xex — fungujúci test

## API

```asm
; Inicializácia (raz, v main)
jsr snd_init

; Prehranie zvuku
ldx #SFX_PISTOL     ; X = index zvuku
jsr snd_play
```

## PREDCHÁDZAJÚCE NEFUNKČNÉ POKUSY

1. VQ v hlavnej RAM — program presahol $6000, sprite chunky prepísali kód
2. VQ v extended RAM (PORTB v IRQ) — crash (NMI počas prepnutého PORTB)
3. RAW v extended RAM (PORTB v IRQ) — rovnaký crash
4. Buffered (PORTB len v main loope) — čierny obraz
5. POKEY syntetické tóny — fungovali čiastočne, crash pri streľbe doľava
6. Timer 1 + VTIMR1 + výstup na AUDC1 — pískanie (timer kanál generoval tón)
7. Timer 4 + VIMIRQ — stack overflow (VIMIRQ nie je správny vektor pre timer dispatch)
8. Timer 1 + VTIMR1 (OS dispatch) — fungovalo, ale ~32% CPU overhead (OS dispatch chain ~80 cyklov)

### Prečo predtým nefungovalo
- PORTB banking v IRQ: NMI príde počas prepnutého PORTB → OS vidí zlú pamäť
- POKMSK neaktualizovaný: OS obnoví IRQEN z POKMSK → vypne timer po 1. IRQ
- VIMIRQ ($0216): OS cez neho volá IIR dispatcher, nie priamo timer handler
- Výstup na AUDC1 (timer kanál): AUDF1 generuje počuteľný tón

### Prečo teraz funguje
- Žiadny PORTB banking (dáta v hlavnej RAM $6000+)
- VTIMR1 ($0210) — OS sám acknowledge-ne, pushne A, obnoví X
- POKMSK správne aktualizovaný pred IRQEN
- Timer na kanáli 1 (AUDC1=0 tichý), výstup na kanáli 4 (AUDC4 volume-only)
- Timer zapnutý len počas prehrávania

## MOŽNÉ VYLEPŠENIA VÝKONU

### 1. Znížiť sample rate na ~3kHz (AUDF1=20)
- CPU záťaž: ~36% → ~27% počas prehrávania
- Kvalita: mierne horšia, ale pre výbuchy/strely stále OK
- freq = 63921 / 21 = 3044 Hz
- Veľkosť zvukov klesne o ~25%

### 2. Optimalizovať IRQ handler (minimálna latencia)
- Technika z smp.pas: predpočítaný sample zapísať hneď na začiatku handlera
  (pred akýmkoľvek spracovaním), spracovanie pre ĎALŠÍ IRQ až potom
- Ušetrí ~10-20 cyklov DMA jitter

### 3. Unpacked nibbles (1 byte = 1 sample)
- Dvojnásobná veľkosť dát, ale handler je jednoduchší (žiadna phase logika)
- Handler: LDA (ptr),Y / ORA #$10 / STA AUDC4 / INC ptr = ~25 cyklov
- Menej cyklov na IRQ = menej spomalenie

### 4. 1.79MHz clock + 16-bit timer (AUDCTL=$50)
- Presnejšia kontrola sample rate
- Kanály 1+2 spojené do 16-bit čítača
- AUDF1+AUDF2 = 16-bit divisor pre ľubovoľnú frekvenciu

### 5. Prioritný systém zvukov — HOTOVO
- snd_lock: death/sight/gib zvuky nastavia lock na 8 framov
- Počas locku snd_play ignoruje nové zvuky (okrem priority zvukov)
- Priority zvuky (play_enemy_death, play_enemy_sight): vynulujú lock, prehrajú sa, nastavia nový lock
- Lookup tabulky: en_death_sfx, en_sight_sfx (indexed by enemy type, $FF = no sound)

### 6. RAM optimalizácia
- Kratšie zvuky (agresívnejší trim, orezať chvosty)
- Zdieľané zvuky (chaingun = pistol, plasma ≈ pistol s inou frekvenciou)
- Nižší sample rate pre menej dôležité zvuky (door, pickup)
- Pri 20 zvukoch ~10-15KB z 24KB dostupných ($6000-$BFFF)
- Keby nestačilo: extended RAM ($4000 banking), ale vyžaduje PORTB v main loope

## IMPLEMENTOVANÉ ZVUKY

| # | Konštanta | WAD lump | Veľkosť | Adresa | Použitie |
|---|-----------|----------|---------|--------|----------|
| 0 | SFX_PISTOL | DSPISTOL | 973B | $6000 | streľba pistol + chaingun |
| 1 | SFX_ITEMUP | DSITEMUP | 406B | $63CD | pickup ammo |
| 2 | SFX_ROCKET | DSRLAUNC | 987B | $6563 | streľba rocket launcher |
| 3 | SFX_PODEATH | DSPODTH1 | 1188B | $693E | smrť zombie + shotgun guy |
| 4 | SFX_POSIGHT | DSPOSIT1 | 958B | $6DE2 | sight zombie + shotgun guy |
| 5 | SFX_IMPSIGHT | DSBGSIT1 | 1188B | $71A0 | sight imp |
| 6 | SFX_IMPDEATH | DSBGDTH1 | 1279B | $7644 | smrť imp |
| 7 | SFX_SHOTGUN | DSSHOTGN | 990B | $7B43 | streľba shotgun |
| 8 | SFX_WPNUP | DSWPNUP | 1055B | $7F21 | pickup weapon |
| 9 | SFX_PUNCH | DSPUNCH | 430B | $8340 | fist úder |
| 10 | SFX_BAREXP | DSBAREXP | 994B | - | barrel/rocket explózia (0.5s) |
| 11 | SFX_SLOP | DSSLOP | 697B | - | gib/splat (rocket kill, 0.35s) |
| 12 | SFX_BRSSIT | DSBRSSIT | 994B | - | baron sight (0.5s) |
| 13 | SFX_BRSDTH | DSBRSDTH | 1192B | - | baron death (0.6s) |

Celkom: ~11.5KB z 12KB max ($6000-$8FFF)
MEMAC bug opravený (generic_upload vypína BANK_SEL po uploade)
Priority systém: snd_lock (8 framov) pre death/sight/gib zvuky
Lookup tabulky: en_death_sfx, en_sight_sfx (indexed by enemy type)

## DOOM 1 ZVUKY - REFERENCIA

### Zbrane hráča
| Zbraň | WAD lump | Stav |
|---|---|---|
| Pistol | DSPISTOL | HOTOVO (SFX_PISTOL) |
| Shotgun | DSSHOTGN | HOTOVO (SFX_SHOTGUN) |
| Chaingun | DSPISTOL (zdieľaný) | HOTOVO (SFX_PISTOL) |
| Rocket | DSRLAUNC | HOTOVO (SFX_ROCKET) |
| Plasma | DSPLASMA | TODO |
| BFG | DSBFG | TODO |
| Fist | DSPUNCH | TODO |

### Enemy DEATH zvuky
| Enemy | WAD lump(y) | Stav |
|---|---|---|
| Zombieman | DSPODTH1/2/3 (náhodný z 3) | HOTOVO (SFX_PODEATH, len 1) |
| Shotgun Guy | DSPODTH1/2/3 (zdieľaný so zombie) | HOTOVO (SFX_PODEATH) |
| Imp | DSBGDTH1/2 (náhodný z 2) | HOTOVO (SFX_IMPDEATH, len 1) |
| Pinky | DSDMPAIN (?) / DSDMACT | TODO |
| Cacodemon | DSCACDTH | TODO |
| Baron of Hell | DSBRSDTH | TODO |

### Enemy PAIN zvuky (pri zásahu, nie smrti)
V DOOM 1 existujú len 2 zdieľané pain zvuky:
| Zvuk | Enemies | Pain šanca |
|---|---|---|
| DSPOPAIN | Zombieman (79%), Shotgun Guy (68%), Imp (79%) | "humanoid" |
| DSDMPAIN | Pinky (71%), Cacodemon (50%), Baron (17%) | "demon" |

Pain chance mechanika: pri každom zásahu sa generuje náhodné číslo 0-255.
Ak je menšie ako pain chance enemyho, prehrá sa zvuk. Baron reaguje len v 17%!

### Enemy SIGHT zvuky (pri zbadaní hráča)
| Enemy | WAD lump(y) | Stav |
|---|---|---|
| Zombieman | DSPOSIT1/2/3 (náhodný z 3) | HOTOVO (SFX_POSIGHT, len 1) |
| Shotgun Guy | DSPOSIT1/2/3 (zdieľaný so zombie) | HOTOVO (SFX_POSIGHT) |
| Imp | DSBGSIT1/2 (náhodný z 2) | HOTOVO (SFX_IMPSIGHT, len 1) |
| Pinky | DSSGTSIT | TODO |
| Cacodemon | DSCACSIT | TODO |
| Baron of Hell | DSBRSSIT | TODO |

### Pickup zvuky
| Typ | WAD lump | Stav |
|---|---|---|
| Ammo (bullets/shells/rockets) | DSITEMUP | HOTOVO (SFX_ITEMUP) |
| Weapon (shotgun) | DSWPNUP | HOTOVO (SFX_WPNUP, len shotgun pickup) |
| Health/Medikit | DSGETPOW | TODO |

### Prostredie
| Zvuk | WAD lump | Stav |
|---|---|---|
| Barrel explode | DSBAREXP | TODO |
| Door open | DSBDOPN (DSBDOPNa.wav) | HOTOVO (SFX_DOOROPN) |
| Door close | DSBDCLS | HOTOVO (SFX_DOORCLS) |

### Hráč
| Zvuk | WAD lump | Stav |
|---|---|---|
| Player pain | DSPLPAIN / DSOOF | TODO |
| Player death | DSPLDETH | TODO |

## PLÁN ZVUKOV PRE ATARI VERZIU

Pre Atari stačí minimálna sada (~15 zvukov, ~10-12KB):
- 4 zbrane: pistol✓, shotgun, rocket✓, fist
- 2 pickup: ammo✓, weapon/health
- 2 enemy death: zombie/shotgun✓, imp+pinky+caco+baron (jeden zdieľaný)
- 2 enemy pain: DSPOPAIN (humanoid), DSDMPAIN (demon)
- 2 enemy sight: DSPOSIT1 (zombie/shotgun/imp), DSSGTSIT alebo DSCACSIT (demon)
- 1 barrel: DSBAREXP
- 1 hráč: DSPLPAIN

Odhad veľkosti: ~10-12KB z 24KB dostupných ($6000-$BFFF)

## KONVERZIA NOVÝCH ZVUKOV

```bash
# Jeden zvuk
python tools/wav2pokey.py extracted/sounds/wav/DSSHOTGN.wav data/sfx_shotgun_4bit.bin

# Po konverzii: pridať do main.asm (segment $6000+) a sound.asm (sfx tabuľky)
```

## PRIDANIE NOVÉHO ZVUKU - POSTUP

1. Skonvertovať WAV: `python tools/wav2pokey.py input.wav data/sfx_NAME_4bit.bin`
2. Pridať `ins` do main.asm (segment $6000):
   ```asm
   sfx_NAME_data
       ins '../data/sfx_NAME_4bit.bin'
   sfx_NAME_end
   ```
3. Pridať do sound.asm tabuliek:
   ```asm
   sfx_addr
       dta a(sfx_pistol_data)
       dta a(sfx_NAME_data)     ; nový
   sfx_end
       dta a(sfx_pistol_end)
       dta a(sfx_NAME_end)      ; nový
   ```
4. Pridať konštantu do constants.asm: `SFX_NAME = 1`
5. Zavolať `ldx #SFX_NAME / jsr snd_play` v príslušnom kóde

## ZNÁME BUGY A RIEŠENIA

### Chrčanie zvukov (crackling/garbling)

**Príčina:** Zvukové dáta sú rozdelené do 12KB chunkov (snd_c1..snd_cN) a uploadované
do VRAM cez `generic_upload`. Ak `uc_lastpg` (počet pages v poslednom banku) je nastavený
príliš nízko, posledné bajty sa neuploadnú → zvuk číta garbage z VRAM → chrčanie.

**Diagnostika:**
1. Ak chrčí len druhá polovica/koniec zvuku → upload boundary bug
2. Ak chrčí celý zvuk → WAV konverzia (normalize, anti-alias)
3. Ak chrčí len jeden zvuk a ostatné sú OK → ten zvuk prekračuje chunk boundary

**Príklad (1.4.2026):** DSBDOPN (door open) chrčal, DSBDCLS (door close) nie.
- DSBDOPN bol na konci chunk 3, posledných 296 bajtov presahovalo do chunk 4
- upload_snd3 mal `uc_lastpg=15` (3840B) namiesto `16` (4096B v poslednom banku)
- Posledných 256 bajtov chunk 3 sa neuploadlo do VRAM
- Fix: `uc_lastpg=16` → celý chunk sa uploadne

**Prevencia:**
- Po pridaní nového zvuku vždy skontroluj výstup sounds2vram.py:
  `Chunk N: snd_cN.bin (XXXX bytes, YY pages)`
- Porovnaj pages s `uc_lastpg` v upload_sndN
- Plný chunk (12288B) = 3 banky × 16 pages → uc_cnt=3, uc_lastpg=16
- Čiastočný chunk: uc_lastpg = ceil(zvyšok / 256)

**sounds2vram.py opravy (1.4.2026):**
- Pridaný normalize (peak → ±1.0) pred 4-bit kvantizáciu
- Pridaný anti-alias low-pass filter pred resamplingom
- Zmenený resampling z nearest-neighbor na lineárnu interpoláciu
