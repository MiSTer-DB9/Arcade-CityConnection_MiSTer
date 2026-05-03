# Cross-reference MAME source ↔ RTL City Connection

Reference: `_dev/mame_src/mame_repo/src/` (MAME 0.286+ master).

## 1. Screen timing
| Param | MAME (`citycon.cpp:391-396`) | RTL (`citycon_video.sv`) | Note |
|---|---|---|---|
| HTOTAL | 320 | 320 (hcnt 0..319) | ✓ |
| HBEND  | 8  | 24 (hblank fino hcnt<24, screen_x = hcnt-16 → primo visibile screen_x=8) | ✓ equivalente |
| HBSTART | 248 | 264 (hblank ≥ 264 = screen_x ≥ 248) | ✓ |
| VTOTAL | 262 | 262 | ✓ |
| VBEND  | 16 | 16 (vblank fino vcnt<16) | ✓ |
| VBSTART | 240 | 240 (vblank ≥ 240) | ✓ |
| PIXEL_CLOCK | 5 MHz | clk_sys/8 (= 5 MHz se clk_sys=40 MHz) | dipende dal PLL |

**Note**: MAME ammette HBEND/HBSTART sono "guess" (`// guess`). Le PAL16L8A sul board reale potrebbero avere timing leggermente diversi.

## 2. Tilemap mapper (FG e BG)
MAME `citycon.cpp:89-93` `TILEMAP_MAPPER_MEMBER(scan)`:
```cpp
return (col & 0x1f) + ((row & 0x1f) << 5) + ((col & 0x60) << 5);
```
Tilemap: 128 col × 32 rows = 1024×256 px.

RTL `citycon_video.sv:158`:
```verilog
fg_vram_addr_nxt = { fg_col_next[6:5], fg_row[4:0], fg_col_next[4:0] };
```
✓ Match: `{col[6:5], row[4:0], col[4:0]}` ≡ `(col & 0x60) << 5 | (row & 0x1f) << 5 | (col & 0x1f)`.

## 3. Tilemap scroll (FG)
MAME `citycon.cpp:207-208`:
```cpp
for (int offs = 6; offs < 32; offs++)
    m_fg_tilemap->set_scrollx(offs, scroll);
```
Righe tile 0..5 → scroll=0 (default), righe 6..31 → scroll.

RTL `citycon_video.sv:124-125`:
```verilog
fg_scroll = (fg_row_idx < 5'd6) ? 16'd0 : scroll_x;
fg_lineshift = (fg_row_idx < 5'd6) ? 12'd0 : 12'd2;  // ← OFFSET CUSTOM
```
✓ Match base. **MA**: `fg_lineshift = 2` è custom RTL, non in MAME. Compensa qualcosa di pipeline.

## 4. Direzione scroll (verifica anti-inversione)
MAME `tilemap.cpp:36`: `value = m_dx - m_rowscroll[index]` con `m_dx=0` → `value = -scroll`.
Loop `tilemap.cpp:1100`: `for (xpos = scrollx - m_width; xpos <= cliprect.right(); xpos += m_width)`.
A scroll positivo, xpos negativo iniziale, copia "principale" del tilemap a xpos = -(-scroll) = scroll? No: xpos = effective_scroll - m_width = (-scroll mod 1024) - 1024.

Es scroll=16: effective = 1008. xpos = 1008-1024 = -16. Tilemap pixel 0 a bitmap_x=-16. **Tilemap pixel 24 a bitmap_x=8.**

RTL `citycon_video.sv:140`: `fg_col_pix = screen_x + scroll`. A scroll=16, screen_x=8, fg_col_pix=24. Mostra tilemap pixel 24. **Match.**

✓ **No inversione segno scroll** (la negazione di MAME `m_dx - rowscroll` è compensata dal `xpos = scroll - m_width` loop wrap).

## 5. BG scroll
MAME `citycon.cpp:206`: `m_bg_tilemap->set_scrollx(0, scroll >> 1);`

RTL `citycon_video.sv:291`: `bg_col_pix = screen_x + scroll_x[11:1];` ✓ Match.

## 6. FG tile info
MAME `citycon.cpp:95-101`:
```cpp
tileinfo.set(0,
    m_videoram[tile_index],
    (tile_index & 0x03e0) >> 5,  // color = row tile [4:0]
    0);
```
Color = `(tile_index & 0x3E0) >> 5` = bits [9:5] di tile_index. Nel mapper `{col[6:5], row[4:0], col[4:0]}`, bits [9:5] = row[4:0]. **Color = row tile.**

RTL: la color del FG è gestita via virtual palette `palette[640+4*y+pen[1:0]]` dove y = row pixel. Il rendering RTL in `citycon_video.sv:781`:
```verilog
fg_opaque ? (11'd512 + {1'b0, linecol_q, 2'd0} + {9'd0, fg_pen[1:0]})
```
**MAME crea virtual palette per scanline, RTL legge palram[512+4*linecolor[y]+pen]** — equivalenti se `linecolor[y]` è scritto correttamente dalla CPU.

## 7. BG tile info
MAME `citycon.cpp:103-111`:
```cpp
int code = rom[0x1000 * m_bg_image + tile_index];
tileinfo.set(3 + m_bg_image, code,
    rom[0xc000 + 0x100 * m_bg_image + code], 0);
```

RTL `citycon_video.sv:332-334`:
```verilog
3'd4, 3'd5: bgmap_addr = {bg_image, bg_tile_next};                  // code
3'd6, 3'd7: bgmap_addr = 16'hC000 + {4'd0, bg_image, bg_code_nxt};  // pal
```
✓ Match: code = ROM[0x1000*bg_image + tile_idx], pal_code = ROM[0xC000 + 0x100*bg_image + code].

## 8. Sprite
MAME `citycon.cpp:164-184`:
```cpp
for (offs = bytes-4; offs >= 0; offs -= 4) {
    sx = spriteram[offs+3];
    sy = 239 - spriteram[offs];
    flipx = ~spriteram[offs+2] & 0x10;
    if (flip_screen()) {
        sx = 240 - sx;
        sy = 238 - sy;          // ← 238 NON 239 in flip mode
        flipx = !flipx;
    }
    gfx(spriteram[offs+1] & 0x80 ? 2 : 1)->transpen(...,
        spriteram[offs+1] & 0x7f,   // idx
        spriteram[offs+2] & 0x0f,   // color
        flipx, flip_screen(),
        sx, sy, 0);
}
```

RTL `citycon_video.sv` SS_LATCH_SY:
```verilog
sy_new = 239 - sprite_q + 2;       // ← +2 OFFSET CUSTOM
```
**DIVERGENZE**:
- MAME usa `238 - sprite_q` solo se flip; RTL non differenzia
- Il `+2` su sy_new è custom RTL, non in MAME

## 9. Palette virtual (linecolor)
MAME `citycon.cpp:194-201`:
```cpp
for (offs = 0; offs < 256; offs++) {
    int indx = m_linecolor[offs];
    for (int i = 0; i < 4; i++)
        changecolor_RRRRGGGGBBBBxxxx(640+4*offs+i, 512+4*indx+i);
}
```
Setup virtual palette ogni frame. Range 256 scanline (offs 0..255).

RTL: legge direttamente `palram[512 + 4*linecol_q + pen[1:0]]` = equivalente, ma **bypassa write-back** del virtual palette in palram. Funziona se la CPU non legge `palram[640+4*y+i]` (read-back). Da verificare se la CPU lo fa.

## 10. Init `init_citycon` 2bpp→5bpp
MAME `citycon.cpp:538-558`. RTL `Template.sv:317-329` fa expansion on-the-fly. **Algoritmo identico** verificato byte per byte.

## 11. PALs (`pal16l8a.h7/l5/u7`)
MAME ammette equazioni non estratte (`// also a guess`). PALs definiscono timing video preciso e address decoder. Decodifica binary fuse map possibile ma richiede pin mapping board (non disponibile).

## DIVERGENZE PRINCIPALI

| # | Item | MAME | RTL | Impatto |
|---|---|---|---|---|
| A | `fg_lineshift = 2` | non c'è | aggiunto su righe scrollate | Sposta linea FG di 2px |
| B | `+2` su `sy_new` sprite | non c'è | aggiunto | Sposta sprite Y di 2px |
| C | `+ 10'sd4` su `spr_sx_shift` | non c'è | aggiunto hardcoded | Sposta sprite X di 4px |
| D | sprite Y in flip (238 vs 239) | 238 in flip | sempre 239 | 1px off in cocktail |
| E | `fg_col_next = +2` (prefetch tile) | n/a | scelta pipeline RTL | Necessaria per timing |
| F | virtual palette write-back | sì (ogni frame) | bypassed (lettura diretta) | OK se CPU non rilegge |
| G | Audio CPU + YM2203 + AY8910 | sì | non implementato | No audio |
| H | PORT_IMPULSE(2) coin | sì | no | Coin counter |

I (A), (B), (C) sono compensazioni custom per matchare comportamento osservato. Senza, il rendering RTL ha shift visibili.
