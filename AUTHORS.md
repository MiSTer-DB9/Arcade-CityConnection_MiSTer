# Authors and Credits

## CityConnection_MiSTer core

**Author**: Umberto Parisi ([rmonic79](https://github.com/rmonic79))

The original RTL source files for the City Connection-specific logic (under
`rtl/citycon/` and the project wrapper `Template.sv`) are copyright
Umberto Parisi and distributed under GNU GPL v3 or later.

## Third-party components

This core builds on top of excellent open-source projects. All third-party
sources retain their original copyright and license. The core as a whole
is distributed under **GNU GPL v3 or later** to stay compatible with the
most restrictive upstream (JTFRAME / JTCORES).

| Component | Author | Project | License |
|-----------|--------|---------|---------|
| **MC6809** — Motorola 6809 cycle-accurate core | Greg Miller | [cavnex/mc6809](https://github.com/cavnex/mc6809) | GPL-3 |
| **T80** — Z80 core | Daniel Wallner, MikeJ | [MiSTer-devel/T80](https://github.com/MiSTer-devel/T80) | BSD / GPL |
| **JTFRAME / JTCORES** — framework, filters, tilemap, etc. | Jose Tejada ([@topapate](https://twitter.com/topapate)) | [jotego/jtcores](https://github.com/jotego/jtcores) | GPL-3 |
| **JT03** — YM2203 FM + PSG synthesizer | Jose Tejada | [jotego/jt12](https://github.com/jotego/jt12) | GPL-3 |
| **JT49** — AY-3-8910 PSG | Jose Tejada | [jotego/jt49](https://github.com/jotego/jt49) | GPL-3 |
| **sdram.sv** — SDRAM controller | Sorgelig ([sorgelig](https://github.com/sorgelig)) | [MiSTer-devel](https://github.com/MiSTer-devel) | GPL-3 |
| **sys/ framework** — MiSTer HPS/IO, OSD, video scaler, audio | Sorgelig / MiSTer-devel | [MiSTer-devel/Main_MiSTer](https://github.com/MiSTer-devel/Main_MiSTer) | GPL-3 |

## Reference

- **City Connection arcade hardware** — Jaleco, 1985. This FPGA core is a
  reimplementation from hardware documentation, MAME source code, and
  observation of real hardware behavior (PCB video footage). ROMs are
  **not** included and must be provided by the user.
- **MAME project** — invaluable reference for memory maps, timing,
  and driver behavior. [mamedev/mame](https://github.com/mamedev/mame)
- **Janet PCB video** — for the discovery that real hardware outputs 247
  visible pixels (not the 240 shown by MAME).
