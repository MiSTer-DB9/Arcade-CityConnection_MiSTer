# City Connection Core — Inventario moduli riutilizzati

Tutti i moduli esterni copiati in `rtl/` e le loro origini.

## CPU

| File | Origine | Note |
|---|---|---|
| `rtl/mc6809/mc6809i.v` | `_reference/cores/outrun_baseline/modules/jtframe/hdl/cpu/` | 6809 core (Greg Miller). Usato per main CPU **e** sound CPU. |
| `rtl/mc6809/jtframe_sys6809.v` | idem | Wrapper JTFRAME (non usato — istanza diretta di `mc6809i`). |

## Audio (JT / Jotego)

| File | Origine | Note |
|---|---|---|
| `rtl/jt03/jt03.v` + `jt12_*.v` | `_reference/cores/cave_baseline/quartus/rtl/jt03/` | YM2203 (FM 3 canali + PSG 3 canali). Include `jt49` internamente. |
| `rtl/jt03/jt49*.v` | idem | AY-3-8910 standalone (C.C. ha un AY separato dallo YM2203 sul memory map sound CPU). |

## Video helpers (JTFRAME)

| File | Origine | Uso |
|---|---|---|
| `rtl/jtframe/jtframe_tilemap.v` | `darius_core/rtl/jtframe/` | Tilemap generico. Usato per FG 8×8 e BG 8×8 (map da ROM). |
| `rtl/jtframe/jtframe_scroll.v` | `darius_core/rtl/jtframe/` | Scroll wrapper per tilemap. Serve per scroll per-row del FG. |
| `rtl/jtframe/jtframe_scroll_offset.v` | `darius_core/rtl/jtframe/` | Dip. di `jtframe_scroll`. |
| `rtl/jtframe/jtframe_objdraw_trunc.v` | `_reference/jtcores/modules/jtframe/hdl/video/` | Sprite draw **truncated** (supporta sprite 8 px: City Con ha sprite 8×16). |
| `rtl/jtframe/jtframe_objdraw_gate.v` | idem | Implementazione sottostante di `objdraw_trunc`. |
| `rtl/jtframe/jtframe_objscan.v` | idem | Scansione sprite RAM → stream `draw` + attributi. |
| `rtl/jtframe/jtframe_obj_buffer.v` | `_reference/jtcores/modules/jtframe/hdl/ram/` | Line buffer sprite (dual port). |
| `rtl/jtframe/jtframe_draw.v` | `_reference/jtcores/modules/jtframe/hdl/video/` | Primitiva di disegno usata da `objdraw_gate`. |
| `rtl/jtframe/jtframe_dual_ram.v` | `darius_core/rtl/jtframe/` | Dual port RAM generica (contiene anche `jtframe_dual_ram_cen`). |
| `rtl/jtframe/jtframe_sh.v` | `_reference/jtcores/modules/jtframe/hdl/` | Shift register parametrico, usato da `objdraw_gate`. |

## Framework MiSTer

| Cartella | Origine | Note |
|---|---|---|
| `sys/` | `darius_core/sys/` (Sorgelig) | Framework MiSTer completo (hps_io, sys_top, video mixer, ecc.). |
| `rtl/sdram.sv` | `darius_core/rtl/` | Sorgelig SDRAM controller (non ancora istanziato: C.C. sta tutto in BRAM). |
| `rtl/pll.v` + `.qip` | `darius_core/rtl/` | PLL 20 MHz. |

## File di progetto Quartus

| File | Note |
|---|---|
| `CityConnection.qpf` / `.qsf` | Progetto Quartus 17.0 (partito da Darius, pulito). |
| `Template.sv` | Top-level `emu`: istanzia `citycon_top`, hps_io, video. |
| `Template.sdc` | Constraints base (PLL clocks). |
| `files.qip` | Elenco sorgenti. |

## Moduli custom City Connection (in scrittura)

| File | Stato |
|---|---|
| `rtl/citycon/citycon_top.sv` | ✅ scheletro: main CPU + memory map + VRAM/sprite/linecolor/palette RAM + I/O + IRQ |
| `rtl/citycon/citycon_video.sv` | ⏳ da scrivere (FG + BG + sprite + palette + linecolor lookup) |
| `rtl/citycon/citycon_sound.sv` | ⏳ da scrivere (sound CPU 6809 + YM2203 + AY-3-8910 + soundlatch) |
