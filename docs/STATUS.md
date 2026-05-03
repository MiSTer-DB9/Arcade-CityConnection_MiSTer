# City Connection Core — Status

Data ultimo update: **2026-04-20** (sessione completamento MAME-accurate pipeline video)

## Stato generale

Primo stato "fine sessione" con datapath video **MAME-accurate nella logica**,
basato su audit riga-per-riga di `citycon.cpp`. Compila staticamente (review
agent OK). Non ancora provato in simulazione né hardware.

## Sorgente di verità

- `citycon.cpp` (MAME driver) ← tutta la logica video segue questo file
- Audit documentato per:
  - gfx layouts (char 5bpp, BG 4bpp, sprite 4bpp)
  - init_citycon 2→5bpp expansion (replicato on-the-fly in RTL)
  - Palette format RGBx_444 (640 reali + 1024 virtuali)
  - Virtual palette update per scanline (linecolor)
  - Sprite flip/priority/layout

## File principali

| File | Stato | Commento |
|---|---|---|
| `CityConnection.qpf/.qsf` | ✅ | Progetto Quartus 17.0 |
| `Template.sv` | ✅ | Top + BRAM ROMs (main/char/bgmap/bgpix/sprite) |
| `mra/City Connection (set 1).mra` | ✅ | Layout 256KB |
| `rtl/citycon/citycon_top.sv` | ✅ | CPU 6809, mem map, dual-port RAMs (WRAM/VRAM/linecolor/sprite/palette) |
| `rtl/citycon/citycon_video.sv` | ✅ | FG 5bpp + BG 4bpp + sprite 4bpp, palette mixing, priority |
| `rtl/citycon/citycon_sound.sv` | ❌ | Sound CPU + YM2203 + AY-3-8910: TODO |

## Pipeline video implementato (MAME-fedele)

### FG layer
- **Expansion 2bpp→5bpp** in BRAM char (Template.sv): 4KB source → funzione
  pura che replica init_citycon bit-per-bit (mask = `x | (x<<4) | (x>>4)` +
  gating su bit indice i).
- **Tile scan** MAME: `{col[6:5], row[4:0], col[4:0]}` (12-bit VRAM addr).
- **Scroll per-row**: rows 0..5 scroll=0, rows 6..31 scroll=scroll_x.
- **5-plane extraction**:
  - `base = code*24 + row*3 + (col<4 ? 0 : 0x1800)`
  - `plane0 = byte0[b]`, `plane1 = byte0[b+4]`
  - `plane2 = byte1[b]`, `plane3 = byte1[b+4]`
  - `plane4 = byte2[b]` dove `b = 3 - (col & 3)`
- **Transparent pen 0**: `fg_opaque = |fg_pen`.
- **Palette FG**: `640 + 4*scanline + pen[1:0]` (virtual palette base — la
  scrittura dinamica della virtual palette NON è ancora implementata, quindi
  quelle entries leggono 0 finché non aggiungiamo il writeback HW della
  linecolor→palram).

### BG layer
- **Tile scan** identica a FG (stesso mapper).
- **Scroll**: `scroll_x >> 1` (metà velocità, come cpp L206).
- **Two-level ROM fetch**: tile code @ `bg_image*0x1000 + idx`, palette code
  @ `0xC000 + bg_image*0x100 + code` — entrambi in `bgmap_rom` (56KB c2+c3+c5).
- **4-plane extraction**:
  - `base = (3+bg_image)*0x1000 + code*8 + row + (col<4 ? 0 : 0x800)`
  - `plane0/1 = bgpix_rom[base]`
  - `plane2/3 = bgpix_rom[base + 0xC000]` (96KB c6+c7+c8+c9)
- **Palette BG**: `256 + bg_pal_next[3:0]*16 + bg_pen[3:0]`.
- Sempre opaco (è la base del render stack).

### Sprite layer
- **Line buffer ping-pong 256×(4-bit pen + 4-bit color)**.
- **Scanner FSM**: 19 stati per sprite in match (fetch 4 byte SRAM + 4 byte
  ROM + write 8 pixel), 9 stati per miss.
- **Draw order MAME**: dall'ultimo sprite (idx 63) al primo (idx 0) → primo
  "on top". Implementato con overwrite (non KEEP).
- **Layout 4bpp 8×16**:
  - bit[13] = plane_high (0=p0/1, 1=p2/3) → +0x2000
  - bit[12] = gfxset (attr1[7]) → +0x1000
  - bit[11] = col_half (0=c<4, 1=c>=4) → +0x800
  - bit[10:4] = sprite idx (7 bit)
  - bit[3:0] = row (0..15)
- **flipx**: `~attr2[4]` (bit 4 inverso MAME), `flipy = flip_screen`.
- **Clear buffer**: 256 clocks dopo start_scan, poi scanner busy.

### Palette mixing (priority MAME: sprite > FG > BG)
```
pal_idx = spr_opaque ? (0   + {spr_color, spr_pen})
        : fg_opaque  ? (640 + 4*scanline + fg_pen[1:0])
        :              (256 + {bg_pal[3:0], bg_pen})
```
Fetch 2 byte consecutivi (hi/lo) → word → `pal4bit` (replica nibble).

## Budget BRAM stimato

| Area | Size | M10K blocks (9600-bit util) |
|---|---|---|
| Main CPU ROM | 48 KB | ~40 |
| Char ROM (src 4KB) | 4 KB | ~4 |
| BG map ROM | 56 KB | ~48 |
| BG pixel ROM | 96 KB | ~80 |
| Sprite ROM | 16 KB | ~14 |
| Work RAM | 4 KB | ~4 |
| FG VRAM (dual-port) | 4 KB | ~4 |
| Linecolor (dual-port) | 256 B | 1 |
| Sprite RAM (dual-port) | 256 B | 1 |
| Palette RAM (dual-port) | 4 KB | ~4 |
| Sprite line buf (2× 256×8) | 512 B | 1 |
| **Totale** | **~232 KB** | **~201** |

Cyclone V 5CSEBA6 = 553 M10K → **36% utilizzati**, margine per sound CPU,
YM2203 (PSG+FM+RAM interna), soundlatches, eventuali buffer addizionali.

## Open TODO (per fedeltà MAME completa)

| Priorità | Cosa | Dove |
|---|---|---|
| **Alta** | Virtual palette write (scanline → palram[640+4*y+i]) | `citycon_video.sv` |
| Alta | Sound CPU 6809 + YM2203 + AY-3-8910 + 2× soundlatch | nuovo `citycon_sound.sv` |
| Media | Sprite flipx: inversione di half (col 0..3 ↔ 4..7) | `citycon_video.sv` SS_WRITE_* |
| Media | Sprite budget timing: se 64 sprite saturano si sfora scanline | ottimizzare FSM o pre-scan in VBLANK |
| Bassa | Char expansion: verifica che i bit mask siano allineati come il cpp (edge cases `i bit 0,1,2`) | sim |
| Bassa | Palette fetch 2-clock: sincronizzazione pixel output (oggi ~2 pix di sfasamento) | opzionale |
| Bassa | HTOTAL/VTOTAL MAME dichiarati "guess" — verificare con HW | misura HDMI |

## Come proseguire

1. **Build Quartus su richiesta esplicita** → verifica compilazione, Fmax,
   BRAM utilization effettiva.
2. **Primo test su HW**: dovrebbe partire con BG visibile (colored), FG nero
   (virtual palette assente), sprite colorati ma metà destra mancante se
   flipx=1, no audio.
3. Implementare **virtual palette writeback** (piccolo FSM che per ogni
   scanline copia 4 entries da `palram[512+4*linecolor[y]+i]` a
   `palram[640+4*y+i]`, durante HBLANK).
4. Implementare **audio** (sound CPU 6809 + YM2203 + AY-3-8910).

## Session log (questa sessione)

- Scaffolding completo MiSTer (sys/, rtl/, MRA)
- Moduli jtframe copiati (10) + mc6809 + jt03 (40)
- `citycon_top.sv`: CPU 6809 + memory map completa + dual-port BRAMs
- `citycon_video.sv`: prima stesura incrementale (4 step grezzi) + riscrittura
  MAME-accurate dopo audit del cpp
- Template.sv: BRAM ROMs + char expansion on-the-fly + wiring completo
- Review statico agent: no blocking issues per Quartus 17
