# Arcade-CityConnection_MiSTer

FPGA core for **City Connection** (Jaleco, 1985) targeting the
[MiSTer FPGA](https://github.com/MiSTer-devel) platform (Terasic DE10-Nano).

City Connection is a horizontal driving/action arcade game running on a
single MC6809 main + MC6809 sound CPU board with a 32×32 tilemap, 5bpp
foreground with virtual palette per-scanline (the famous "trail" effect),
4bpp background with half-rate scrolling, 4bpp sprites, and AY-3-8910 +
YM2203 audio. This core reimplements the hardware in SystemVerilog from
MAME references and pixel-accurate validation against original PCB footage.

## Status

**Current version: 1.0** (May 2026) — first public release.

The core runs the full game with audio and has been validated pixel-by-pixel
against the original Jaleco PCB (reference video courtesy of Janet's channel,
see Acknowledgements).

**Features**
- MC6809 main CPU @ 2 MHz (Greg Miller's cycle-accurate core)
- MC6809E audio CPU @ 625 kHz (separate sound subsystem)
- AY-3-8910 (jt49) and YM2203 (jt03) sound chips with MAME-accurate mixer
- 247×224 active video area (PCB-accurate, **not** MAME's 240×224 clip)
- Tilemap with virtual palette per-scanline writeback FSM (the "trail")
- Sprite line buffer with PCB-accurate wrap behavior
- 6 PAL16L8 chips decompiled (h7, l5, u7) with gate-level reimplementation
- Inputs (P1/P2 8-way joystick + 2 buttons) and full DIP support
- MiSTer OSD with video offset knobs

**ROM sets supported**
- City Connection (set 1) — reference set (citycon)
- City Connection (set 2) — alternate set (citycona, c11b variant)
- City Connection (Cruisin) — Kitkorp license variant (cruisin)

## The 15-day positioning bug

Two weeks of pixel hunt: sprites and the platform "trail" effect were all
consistently a few pixels off vs MAME. Every offset added (sprite +4X, sy
−1, FG +1, BG +1) felt like a band-aid. After disassembling the original
6809 ROM and mapping every routine that touched the spriteram and tilemap,
none of the formulas matched.

The breakthrough came from a YouTube video of the **real PCB on a Supergun**
by Janet's channel "Janet의 고전게임오락실". One frame revealed it:
the PCB outputs **247 pixels wide**, not 240 as MAME's clipping suggests.
MAME crops 7 pixels and adjusts everything internally to fit. Once the
RTL matched the actual PCB width and the sprite line buffer used proper
PCB-style wrap, every offset suddenly made sense.

Reference video: <https://www.youtube.com/watch?v=9D2OQHAQmV8>

## Hardware emulated

| Component        | Spec                                                |
|------------------|-----------------------------------------------------|
| Master clock     | 20 MHz crystal                                      |
| Main CPU         | HD68B09 (MC6809) @ 2 MHz (MASTER/4 internal E)      |
| Audio CPU        | HD68A09EP (MC6809E) @ 625 kHz (MASTER/32)           |
| Sound chip 1     | AY-3-8910 (jt49) @ 1.25 MHz (MASTER/16)             |
| Sound chip 2     | YM2203 (jt03) @ 1.25 MHz (MASTER/16)                |
| Video resolution | 247×224 active, 320×262 total                       |
| Refresh rate     | 59.63 Hz                                            |
| FG layer         | 5bpp tilemap with virtual palette per-scanline      |
| BG layer         | 4bpp tilemap with scroll/2 ratio                    |
| Sprites          | 4bpp 8×16, 64 slots, PCB-accurate line buffer wrap  |

## Hardware requirements

- Terasic DE10-Nano
- MiSTer I/O board (recommended)
- HDMI display (recommended), or HDMI→VGA adapter for 31 kHz VGA monitors

## Building from source

Requires Quartus Prime 17.0 (free Lite Edition).

```
Open CityConnection.qpf in Quartus → Processing → Start Compilation
```

Output bitstream is generated in `output_files/CityConnection.rbf` (~3.5 MB).

## Running on MiSTer

The [releases/](releases/) folder contains the pre-built bitstream and
the parent MRA for the reference ROM set:

- `CityConnection.rbf` — pre-built core bitstream
- `City Connection (set 1).mra` — parent MRA (reference set)

Alternative ROM sets are provided in [releases/alternatives/](releases/alternatives/):

- `City Connection (set 2).mra` — citycona (c11b variant)
- `City Connection (Cruisin).mra` — Kitkorp license

Following the MiSTer-devel convention, the alternative sets are also
mirrored to the official [MRA-Alternatives_MiSTer](https://github.com/MiSTer-devel/MRA-Alternatives_MiSTer)
repository, where they are picked up automatically by **Update_All**.

Steps:

1. Copy the `.rbf` to `_Arcade/cores/` on the MiSTer SD card.
2. Copy the desired `.mra` file(s) to `_Arcade/` on the MiSTer SD card.
3. Provide your legally-owned City Connection ROM files where each MRA
   expects them (usually in `games/mame/`).

**ROMs are NOT included in this repository.** You must provide them yourself.

## Repository layout

```
Arcade-CityConnection_MiSTer/
├── rtl/
│   ├── citycon/      City Connection-specific core RTL
│   │   └── pld/      Decompiled PAL16L8 + TTL gate-level support
│   ├── jt03/         YM2203 + AY-3-8910 (Jose Tejada)
│   ├── jtframe/      JTFRAME framework modules
│   ├── mc6809/       MC6809 cycle-accurate core (Greg Miller)
│   ├── pll/          Clock PLL
│   └── sdram.sv      SDRAM controller (Sorgelig)
├── sys/              MiSTer framework (Sorgelig / MiSTer-devel)
├── releases/         Pre-built .rbf + parent MRA
│   └── alternatives/ MRA files for alternate ROM sets
├── docs/             Documentation
├── CityConnection.qpf  Quartus project
├── CityConnection.qsf  Quartus assignments
├── Template.sv       Top-level wrapper
├── Template.sdc      Timing constraints
├── files.qip         HDL file list
├── build_id.v        Build version stamp
└── README.md         This file
```

## Acknowledgements

- **Janet** ([Janet의 고전게임오락실](https://www.youtube.com/@user-vy9zg2ub2c))
  for the invaluable PCB reference video that revealed the actual 247-pixel
  output of the original hardware. This single piece of footage solved
  weeks of pixel-positioning mysteries.
- **Greg Miller** for the cycle-accurate MC6809 core used as both main and
  audio CPU.
- **Jose Tejada** ([@jotego](https://github.com/jotego)) for JT03 (YM2203)
  and JT49 (AY-3-8910) sound chip implementations.
- **Sorgelig** and the **MiSTer-devel team** for the framework, SDRAM
  controller and Template.
- The **MAME** project for invaluable hardware reference.

## Support this project

If you enjoy this core and want to support its development:

- [Ko-fi](https://ko-fi.com/ibecerivideoludici) — one-time support
- [Patreon](https://www.patreon.com/IBeceriVideoludici) — monthly support
- [PayPal](https://www.paypal.me/IBeceriVideoludici) — one-time donation

## Follow

- [Twitch](https://twitch.tv/ibecerivideoludici) — live streams
- [YouTube](https://www.youtube.com/c/IBeceriVideoludici/playlists) — playlists and videos

## License

The RTL source code in this repository is provided as-is for educational
and preservation purposes. Original ROM data is not included; users must
provide their own legally obtained copies.

Original City Connection arcade hardware © Jaleco Co., Ltd., 1985.
