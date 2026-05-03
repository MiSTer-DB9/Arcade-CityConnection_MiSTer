/*  This file is part of CityConnection_MiSTer.

    CityConnection_MiSTer is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    CityConnection_MiSTer is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with CityConnection_MiSTer.  If not, see <http://www.gnu.org/licenses/>.

    Author: Umberto Parisi (rmonic79)
    Version: 1.0
    Date: 2026

*/

// City Connection — video renderer (MAME-accurate, versione "step finale")
//
// Implementazione fedele a citycon.cpp:
//   - FG 5bpp via expansion on-the-fly (crom_i/crom_k interface)
//   - FG palette: virtual palette @ 640 + 4*scanline + pen[1:0] (MAME update loop)
//   - BG 4bpp via two-half tilelayout (c6..c9 + planes 2/3 @ +0xC000 offset)
//   - BG palette: c5 byte come pal4bit bank (base 256)
//   - Sprite 4bpp 8×16, two gfxsets (c12 / c13), flipx/flipy, 16 color banks (base 0)
//   - Render order: BG (opaque) → FG (trans pen 0) → sprite (trans pen 0)
//   - Scroll per-row FG: rows 0..5 → scroll=0, rows 6..31 → scroll=scroll_x
//   - BG scroll: scroll_x >> 1
//============================================================================

module citycon_video
(
	input             clk,        // 48 MHz (clk_sys)
	input             reset,
	input             ce_pix,     // 6 MHz (clk/8)

	input             flip_screen,
	input      [15:0] scroll_x,   // {scroll_hi, scroll_lo}
	input       [3:0] bg_image,

	input  signed [5:0] fg_off_x,
	input  signed [5:0] bg_off_x,
	input  signed [5:0] spr_off_x,
	input  signed [5:0] scia_off_x,
	input  signed [5:0] spr_off_y,
	input  signed [5:0] spr_off_x_player,
	input         [3:0] width_lshift,   // 0..8: distribuzione 8 px extra (sx)

	// VRAM FG — 4 KB
	output     [11:0] vram_addr,
	input       [7:0] vram_q,

	// Linecolor RAM — 256 B
	output reg  [7:0] linecol_addr,
	input       [7:0] linecol_q,

	// Sprite RAM — 256 B (64 sprite × 4 byte)
	output      [7:0] sprite_addr,
	input       [7:0] sprite_q,

	// Palette RAM — 4 KB addr space (include virtual palette)
	output reg [11:0] pal_addr,
	output reg        pal_we,        // virtual palette writeback
	output reg  [7:0] pal_data,      // virtual palette writeback data
	input       [7:0] pal_q,

	// Char ROM (expansion on-the-fly)
	output     [11:0] crom_i,
	output      [1:0] crom_k,
	input       [7:0] crom_data,   // latenza 2 clk

	// BG tile maps (c2+c3+c5, 56 KB)
	output reg [15:0] bgmap_addr,
	input       [7:0] bgmap_data,

	// BG tile pixels (c9+c8+c6+c7, 96 KB)
	output reg [16:0] bgpix_addr,
	input       [7:0] bgpix_data,

	// Sprite ROM (c12+c13, 16 KB)
	output     [13:0] sprrom_addr,
	input       [7:0] sprrom_data,

	// Video out
	output reg  [7:0] vga_r,
	output reg  [7:0] vga_g,
	output reg  [7:0] vga_b,
	output reg        vga_hs,
	output reg        vga_vs,
	output reg        vga_hb,
	output reg        vga_vb,
	output reg        vblank_rise,

	// Raster counters per overlay
	output     [9:0]  render_x_out,
	output     [8:0]  render_y_out
);

assign render_x_out = hcnt;
assign render_y_out = vcnt;

// ============================================================
// Raster counters — PCB REALE 248 px attivi (8 px estesi a sinistra)
// HTOTAL=320, HBEND=24 hcnt, HBSTART=272 hcnt → 248 px visibili
// screen_x = hcnt-24 → range 0..247
// VTOTAL=262, VBEND=16, VBSTART=240
// Counter H preset 8, va 8..327. Counter V 0..261.
// ============================================================
reg [9:0] hcnt;
reg [8:0] vcnt;

always @(posedge clk) if (reset) begin
	hcnt        <= 10'd8;
	vcnt        <=  9'd0;
	vblank_rise <=  1'b0;
end else begin
	vblank_rise <= 1'b0;
	if (ce_pix) begin
		if (hcnt == 10'd327) begin
			hcnt <= 10'd8;
			if (vcnt == 9'd261) vcnt <= 9'd0;
			else                vcnt <= vcnt + 9'd1;
			if (vcnt == 9'd239) vblank_rise <= 1'b1;
		end else begin
			hcnt <= hcnt + 10'd1;
		end
	end
end

// Area attiva 247 px estesa a destra (7 px in fondo).
// HBEND=32, HBSTART=279, HSYNC 296..320, screen_x = hcnt-32, range 0..246
wire hblank = (hcnt < 10'd32) || (hcnt >= 10'd279);
wire vblank = (vcnt < 9'd16) || (vcnt >= 9'd240);
wire hsync  = (hcnt >= 10'd296) && (hcnt < 10'd320);
wire vsync  = (vcnt >= 9'd243) && (vcnt < 9'd246);

wire [8:0] x_active = hcnt[8:0] - 9'd32;
wire [8:0] y_active = vcnt[8:0] - 9'd16;

// ============================================================
// CONVENZIONE COORDINATE UNIFICATA (Codex audit fix):
// screen_x = coord X in bitmap MAME (visibile 8..247)
// screen_y = coord Y in bitmap MAME (visibile 16..239)
// Tutti i layer usano queste coord. Match MAME 1:1.
// ============================================================
wire [9:0] screen_x = {1'b0, hcnt} - 10'd32;  // bitmap_x = hcnt-32, range 0..247
wire [8:0] screen_y = vcnt[8:0];              // = bitmap_y MAME

// ============================================================
// SCROLL per-row FG (MAME: rows 0..5 → 0, rows 6..31 → scroll_x)
// ============================================================
wire [8:0] y_fg = screen_y;   // MAME: bitmap_y
wire [4:0] fg_row_idx = y_fg[7:3];  // riga tile 0..27
wire [15:0] fg_scroll = (fg_row_idx < 5'd6) ? 16'd0 : scroll_x;
// scia_off_x: shift solo sulle righe scrollate (la "scia" - linea dipinta).
// Permette di centrare la transizione bianco/verde senza spostare il resto del FG.
wire [11:0] fg_lineshift = (fg_row_idx < 5'd6) ? 12'd0 : {{6{scia_off_x[5]}}, scia_off_x};

// ============================================================
// FG TILEMAP (MAME mapper)
//   scan(col,row) = {col[6:5], row[4:0], col[4:0]}  (12-bit)
// Pixel ROM (5bpp expansion):
//   i_low  = code*8 + r
//   i_high = code*8 + r + 0x800
// Per ogni mezzo-tile servono 3 byte (planes 0/1 in byte0, 2/3 in byte1, 4 in byte2).
//
// Pipeline: prefetch al tile precedente. Finestra di 8 ce_pix (32 clk) per 6 byte.
// ============================================================

// MAME: fg_col = bitmap_x + scroll. Pipeline 3-stage (come BG) si auto-compensa
// con prefetch +2: niente offset esterno necessario.
// SPLIT: VRAM read usa fg_col_pix BASE (no fg_lineshift) → no buco laterale.
//        Pixel extract usa fg_col_pix SHIFTED (con fg_lineshift) → striscia centrata.
wire [11:0] fg_col_pix_base = {2'd0, screen_x} + {1'd0, fg_scroll[10:0]}
                             + {{6{fg_off_x[5]}},   fg_off_x};
                             // scia_off_x NON entra qui — agisce solo via fg_lineshift sulle righe scrollate
wire [11:0] fg_col_pix_raw = fg_col_pix_base + fg_lineshift;
wire [10:0] fg_col_pix = fg_col_pix_raw[10:0];
wire [10:0] fg_col_pix_v = fg_col_pix_base[10:0];   // versione per VRAM (no shift)
wire  [8:0] fg_row_pix = y_fg[8:0];

wire  [7:0] fg_col     = fg_col_pix_v[10:3];        // VRAM read: no shift
wire  [4:0] fg_row     = fg_row_pix[7:3];
wire  [2:0] fg_col_sub = fg_col_pix[2:0];           // pixel extract: con shift
wire  [2:0] fg_row_sub = fg_row_pix[2:0];

// Pipeline FG 3-stage: prefetch +3 tile (3 stage code = 3 tile di delay).
// A sub=7 di tile X latch fg_code_nxt = vram[X+3].
// A sub=7 di tile X+1: fg_code_hold ← fg_code_nxt (= vram[X+3]).
// A sub=7 di tile X+2: fg_code_cur ← fg_code_hold (= vram[X+3]).
// char-ROM fetch durante tile X+2 con fg_code_hold = vram[X+3] riempie _nxt.
// A sub=7 di tile X+2: _nxt → _cur (byte vram[X+3]).
// Display tile X+3 usa _cur = vram[X+3]. Match MAME (tile pipeline=X+3 ↔ vram[X+3]).
wire  [7:0] fg_col_next     = fg_col + 8'd3;
wire [11:0] fg_vram_addr_nxt = { fg_col_next[6:5], fg_row[4:0], fg_col_next[4:0] };
assign vram_addr = fg_vram_addr_nxt;

// Pipeline 3-stage code: nxt → hold → cur (analoga a BG).
// A sub=7 di ogni tile fanno swap simultaneo:
//   fg_code_nxt  ← vram[fg_col_next] = vram[col + 2]
//   fg_code_hold ← fg_code_nxt (vecchio, = vram[col + 2 - 1 tile])
//   fg_code_cur  ← fg_code_hold (vecchio, = vram[col + 2 - 2 tile] = vram[col])
reg [7:0] fg_code_nxt, fg_code_hold, fg_code_cur;
always @(posedge clk) if (ce_pix) begin
	if (fg_col_sub == 3'd7) begin
		fg_code_cur  <= fg_code_hold;
		fg_code_hold <= fg_code_nxt;
		fg_code_nxt  <= vram_q;
	end
end

// ==== Char ROM fetch FSM per il tile corrente ====
// Char-ROM gira con fg_code_hold (= vram[col + 1] dello stage centrale).
// I 6 byte fetched durante tile X vanno in _nxt; a sub=7 swappati in _cur per
// display di tile X+1.

reg [11:0] crom_i_r;
reg [ 1:0] crom_k_r;
reg [ 7:0] fg_byte_low_nxt  [0:2];
reg [ 7:0] fg_byte_high_nxt [0:2];
reg [ 7:0] fg_byte_low_cur  [0:2];
reg [ 7:0] fg_byte_high_cur [0:2];

// Char-ROM addr: usa fg_code_hold (stage centrale pipeline).
wire [11:0] fg_i_low  = {fg_code_hold, fg_row_sub};
wire [11:0] fg_i_high = fg_i_low | 12'h800;

// Fetch schedule: fg_code_stable disponibile dal sub=0.
//   sub=0,1,2: i_low k=0,1,2
//   sub=4,5,6: i_high k=0,1,2
always @(*) begin
	case (fg_col_sub)
		3'd0: begin crom_i_r = fg_i_low;  crom_k_r = 2'd0; end
		3'd1: begin crom_i_r = fg_i_low;  crom_k_r = 2'd1; end
		3'd2: begin crom_i_r = fg_i_low;  crom_k_r = 2'd2; end
		3'd4: begin crom_i_r = fg_i_high; crom_k_r = 2'd0; end
		3'd5: begin crom_i_r = fg_i_high; crom_k_r = 2'd1; end
		3'd6: begin crom_i_r = fg_i_high; crom_k_r = 2'd2; end
		default: begin crom_i_r = fg_i_low; crom_k_r = 2'd0; end
	endcase
end
assign crom_i = crom_i_r;
assign crom_k = crom_k_r;

// Latch byte: crom_data arriva 2 clk dopo l'emissione di crom_i/k.
// Quindi quando fg_col_sub=0 emetto, crom_data valido a fg_col_sub=2 (ce_pix dopo).
// Ma ce_pix è 1 ogni 4 clk, quindi "+2 clk" = dentro lo stesso ce_pix slot.
// Per semplicità latch al ciclo successivo di ce_pix.
reg [2:0] fg_col_sub_d;
always @(posedge clk) if (ce_pix) fg_col_sub_d <= fg_col_sub;

// Schedule (verificato empiricamente dal trace sim):
// Al ce_pix sub=M, crom_data ha output emission sub=M stesso (pipeline è 0
// ce_pix = 2 clk_sys ben sotto 8 clk_sys di ce_pix).
// Quindi latch al ce_pix sub=N stesso dove emesso sub=N.
// Non serve fg_col_sub_d, uso fg_col_sub direct.
always @(posedge clk) if (ce_pix) begin
	case (fg_col_sub)
		3'd0: fg_byte_low_nxt [0] <= crom_data;
		3'd1: fg_byte_low_nxt [1] <= crom_data;
		3'd2: fg_byte_low_nxt [2] <= crom_data;
		3'd4: fg_byte_high_nxt[0] <= crom_data;
		3'd5: fg_byte_high_nxt[1] <= crom_data;
		3'd6: fg_byte_high_nxt[2] <= crom_data;
		default: ;
	endcase
end

// Swap byte al sub=7: _nxt → _cur. Display tile X+1 (display attuale) usa _cur.
always @(posedge clk) if (ce_pix) begin
	if (fg_col_sub == 3'd7) begin
		fg_byte_low_cur [0] <= fg_byte_low_nxt [0];
		fg_byte_low_cur [1] <= fg_byte_low_nxt [1];
		fg_byte_low_cur [2] <= fg_byte_low_nxt [2];
		fg_byte_high_cur[0] <= fg_byte_high_nxt[0];
		fg_byte_high_cur[1] <= fg_byte_high_nxt[1];
		fg_byte_high_cur[2] <= fg_byte_high_nxt[2];
	end
end

// === Extract 5bpp pixel ===
wire       fg_half      = fg_col_sub[2];
wire [1:0] fg_bit_sel   = 2'd3 - fg_col_sub[1:0];
wire [7:0] fg_byte0     = fg_half ? fg_byte_high_cur[0] : fg_byte_low_cur[0];
wire [7:0] fg_byte1     = fg_half ? fg_byte_high_cur[1] : fg_byte_low_cur[1];
wire [7:0] fg_byte2     = fg_half ? fg_byte_high_cur[2] : fg_byte_low_cur[2];

// MAME drawgfx.cpp readbit: MSB-first.
// charlayout planes = {16, 12, 8, 4, 0} (5 planes, planes[0]=MSB di pen).
//   planes[0]=16+c → byte 2, bit 7-c (pen MSB)
//   planes[1]=12+c → byte 1, bit 3-c
//   planes[2]=8+c  → byte 1, bit 7-c
//   planes[3]=4+c  → byte 0, bit 3-c
//   planes[4]=0+c  → byte 0, bit 7-c (pen LSB)
wire fg_pMSB = fg_byte2[{1'b1, fg_bit_sel}];  // byte2[7-c]
wire fg_p_1  = fg_byte1[{1'b0, fg_bit_sel}];  // byte1[3-c]
wire fg_p_2  = fg_byte1[{1'b1, fg_bit_sel}];  // byte1[7-c]
wire fg_p_3  = fg_byte0[{1'b0, fg_bit_sel}];  // byte0[3-c]
wire fg_pLSB = fg_byte0[{1'b1, fg_bit_sel}];  // byte0[7-c]

wire [4:0] fg_pen = {fg_pMSB, fg_p_1, fg_p_2, fg_p_3, fg_pLSB};
// MAME char 5bpp pen = row_sub*4 + pen_visibile. row_sub è implicito in
// linecolor[y] (scanline diversa per ogni row_sub del char). pen_visibile=pen[1:0].
// Analisi char c4: pen valori in range {0,1,5,9,13,17,21,25} = row_sub*4+{0,1}
// dove bit[1:0] = {0 o 1} = pen_visibile ∈ {0,1,2,3}. Formula finale semplice.
wire [1:0] fg_pen_idx = fg_pen[1:0];
// MAME 1:1: set_transparent_pen(0) è sul pen 5bpp completo (0..31), non solo pen visibile.
// fg_opaque = (fg_pen != 0) — match MAME drawer transparent pen check.
wire       fg_opaque = |fg_pen;   // MAME 1:1: trasparente sse pen 5bpp = 0

// ============================================================
// BG TILEMAP (MAME)
//   scan(col,row) = {col[6:5], row[4:0], col[4:0]}  (stesso del FG)
//   code_addr = 0x1000*bg_image + tile_index
//   pal_addr  = 0xC000 + 0x100*bg_image + code
//   pix_addr: gfxset (3+bg_image) entry base = 0x2000*bg_image + code*8 + r
//             (col<4: half0; col>=4: half1 @ +0x800; planes 2,3 @ +0xC000 offset)
//   BG scroll = scroll_x >> 1
// ============================================================

// MAME: bg_col = bitmap_x + scroll>>1
wire [11:0] bg_col_pix  = {2'd0, screen_x} + {1'd0, scroll_x[11:1]}
                         + {{6{bg_off_x[5]}}, bg_off_x};
wire  [8:0] bg_row_pix  = screen_y;   // MAME: bitmap_y

wire  [7:0] bg_col     = bg_col_pix[10:3];
wire  [4:0] bg_row     = bg_row_pix[7:3];
wire  [2:0] bg_col_sub = bg_col_pix[2:0];
wire  [2:0] bg_row_sub = bg_row_pix[2:0];

// Pipeline 3 stadi, delay 2 tile. Priming 2 tile (16 hcnt) — HBLANK 8 hcnt
// non basta. Soluzione: bg_code_hold/bg_pal_hold/bg_code_cur/bg_pal_cur NON
// resettati a fine scanline, così i valori della scanline precedente fanno
// da priming per la scanline successiva. Unico caso degenere: prima scanline
// dopo reset o dopo vblank row change — ma lo scroll_x uguale per tutte le
// scanline e bg_row cambia solo al limite di tile verticale.
wire  [7:0] bg_col_next = bg_col + 8'd2;
wire [11:0] bg_tile_next = { bg_col_next[6:5], bg_row[4:0], bg_col_next[4:0] };

reg [7:0] bg_code_nxt,  bg_pal_nxt;
reg [7:0] bg_code_hold, bg_pal_hold;
reg [7:0] bg_pix01_lo_nxt, bg_pix23_lo_nxt, bg_pix01_hi_nxt, bg_pix23_hi_nxt;
reg [7:0] bg_code_cur, bg_pal_cur;
reg [7:0] bg_pix01_lo, bg_pix23_lo, bg_pix01_hi, bg_pix23_hi;

// Fetch FSM: ogni 8 ce_pix = 1 tile
//   col_sub=0: bgmap_addr = 0x1000*bg_image + tile_next → latch bg_code_next @ col_sub=1
//   col_sub=1: bgmap_addr = 0xC000 + 0x100*bg_image + bg_code_next → latch bg_pal_next @ col_sub=2
//   col_sub=2..5: idle
//   col_sub=6: latch bg_row_sub_latch
// Pix fetch durante col corrente (half scelto):
//   col 0..3: byte_low (plane 0/1)  e byte_high (plane 2/3) letti in sequenza
//   col 4..7: come sopra ma half1

// BG pipeline: fetch PER TILE N+1 durante il tile N.
// bgmap fetch si sposta a fine tile (sub=4..7) così bg_code_nxt è disponibile
// dal sub=0 del tile successivo per il bgpix fetch.
//
// Schedule bgmap (per tile N+1):
//   sub=4,5: code slot → latch @ edge 5→6 (case 5)
//   sub=6,7: pal  slot → latch @ edge 7→0 (case 7)
always @(*) begin
	bgmap_addr = 16'd0;
	case (bg_col_sub)
		3'd4, 3'd5: bgmap_addr = {bg_image, bg_tile_next};                  // code
		3'd6, 3'd7: bgmap_addr = 16'hC000 + {4'd0, bg_image, bg_code_nxt};  // pal
		default: ;
	endcase
end

always @(posedge clk) if (ce_pix) begin
	case (bg_col_sub)
		3'd5: bg_code_nxt <= bgmap_data;
		3'd7: bg_pal_nxt  <= bgmap_data;
		default: ;
	endcase
end

// BG pixel ROM layout (MAME tilelayout, 4bpp 8x8):
//   base = (3 + bg_image) * 0x1000 + code*8 + row  + (col<4 ? 0 : 0x800)
//   planes 0/1 @ rom[base]
//   planes 2/3 @ rom[base + 0xC000]

// Pixel ROM fetch per il tile CORRENTE (N). Usa bg_code_cur già latched nel swap
// alla fine del tile precedente, quindi stabile per tutti gli 8 sub di tile N.
// Così bgpix fetch può girare in parallelo al bgmap fetch (che prepara tile N+1).
//
// Base offset in bgtiles1 = bg_image * 0x1000 (NON (3+bg_image)*0x1000: il "3"
// del cpp tileinfo.set(3+bg_image) è solo l'indice gfxdecode globale; bgtiles1
// nella region parte a offset 0).
wire [16:0] bg_pix_nxt_half0 = {1'd0, bg_image[3:0], 12'd0}
                              + {6'd0, bg_code_hold, 3'd0}
                              + {14'd0, bg_row_sub};
wire [16:0] bg_pix_nxt_half1 = bg_pix_nxt_half0 + 17'h0800;

// Pixel fetch. La BRAM registered ha 1-clk latency. L'addr emesso al sub=N
// produce bgpix_data = rom[addr N] al ce_pix sub=N+1 edge. Tuttavia tra
// l'edge del sub=N e sub=N+1, se l'addr combinatorio cambia di nuovo (nuovo
// sub), bgpix_data_r si aggiorna al nuovo valore prima del ce_pix sub=N+1.
//
// Fix: tengo addr stabile 2 sub per ogni fetch. Sub=0..7 = 4 fetch × 2 sub.
// Schedule:
//   sub=0,1: half0 p01 → latch @ case 1 (edge 1→2)
//   sub=2,3: half0 p23 → latch @ case 3
//   sub=4,5: half1 p01 → latch @ case 5
//   sub=6,7: half1 p23 → latch @ case 7
//
// bg_code_nxt deve essere disponibile già dal sub=0. Lo spostiamo al fetch map
// del tile PRIMA (tile N-1 fetcha map per tile N). Cioè bg_code_nxt è quello
// del tile che inizio ora.
// Per semplicità test: assumo bg_code_nxt = bg_code_cur del tile che sto per
// renderizzare. Accettiamo shift di 1 tile (dettagli da sistemare dopo).
//
// Il map fetch deve anche essere 2 sub: usiamo sub=6..7 e sub=0..1 del tile
// precedente? Per ora ignoro map pipeline — verifico solo pix.
// Pixel fetch per tile CORRENTE (N). Usa bg_code_cur (stabile per tutti gli
// 8 sub). Gira in parallelo al bgmap fetch (che usa bg_code_nxt per tile N+1).
// 4 fetch × 2 sub = 8 sub esatti.
//
// Schedule:
//   sub=0,1: half0 p01 → latch @ case 1 (edge 1→2)
//   sub=2,3: half0 p23 → latch @ case 3
//   sub=4,5: half1 p01 → latch @ case 5
//   sub=6,7: half1 p23 → latch @ case 7
always @(*) begin
	case (bg_col_sub)
		3'd0, 3'd1: bgpix_addr = bg_pix_nxt_half0;
		3'd2, 3'd3: bgpix_addr = bg_pix_nxt_half0 + 17'hC000;
		3'd4, 3'd5: bgpix_addr = bg_pix_nxt_half1;
		3'd6, 3'd7: bgpix_addr = bg_pix_nxt_half1 + 17'hC000;
		default:    bgpix_addr = 17'd0;
	endcase
end

always @(posedge clk) if (ce_pix) begin
	case (bg_col_sub)
		3'd1: bg_pix01_lo_nxt <= bgpix_data;
		3'd3: bg_pix23_lo_nxt <= bgpix_data;
		3'd5: bg_pix01_hi_nxt <= bgpix_data;
		3'd7: bg_pix23_hi_nxt <= bgpix_data;
		default: ;
	endcase
end

// Swap dedicated: al ce_pix edge successivo al completamento dei _nxt (sub=0
// pre-edge, cioè edge 0→1 del tile successivo). Un ce_pix di ritardo rispetto
// al tile "fetching" — tile N+1 fetched durante tile N, diventa _cur all'inizio
// del tile N+2? no, diventa _cur all'inizio del tile che inizia al sub=1→...
// Detto meglio: quando bg_col_sub pre-edge = 0 → edge 0→1 → inizia il nuovo
// tile al sub=1. Il display di quel tile inizia al sub=0 (prossimo tick però è
// sub=1). Tolleriamo 1 sub shift.
// Pipeline 3 stage swap al case 7 (edge 7→0 di ogni tile).
// IMPORTANTE: al sub=7 ho anche il latch di bg_pix23_hi_nxt. Per evitare la
// race NBA (swap legge il vecchio _nxt mentre il fetch scrive il nuovo) uso
// un bypass combinatorio: allo swap assegno direttamente bgpix_data (che al
// sub=7 contiene il byte half1 p23 fresco) invece di bg_pix23_hi_nxt.
//   stage1: bg_code_hold <= bg_code_nxt   (bgmap→hold)
//   stage2: bg_code_cur  <= bg_code_hold  (hold→cur, stabile per tile attuale)
//           bg_pix*      <= bg_pix*_nxt   (fetch→rendering)
always @(posedge clk) if (ce_pix) begin
	if (bg_col_sub == 3'd7) begin
		bg_code_hold <= bg_code_nxt;
		bg_pal_hold  <= bgmap_data;       // bypass: al sub=7 bgmap_data = pal fresco
		bg_code_cur  <= bg_code_hold;
		bg_pal_cur   <= bg_pal_hold;
		bg_pix01_lo  <= bg_pix01_lo_nxt;
		bg_pix23_lo  <= bg_pix23_lo_nxt;
		bg_pix01_hi  <= bg_pix01_hi_nxt;
		bg_pix23_hi  <= bgpix_data;       // bypass: al sub=7 bgpix_data = byte fresco
	end
end

// Extract BG 4bpp pen — MAME tilelayout planes = {4, 0, 0xC000*8+4, 0xC000*8+0}
// Convenzione MAME (src/emu/drawgfx.cpp): bit offset 0 = bit 7 del byte (MSB).
// Formula: planeP_pixelX = ROM[ (planes[P]+xoffsets[X]) >> 3 ][ 7 - ((...)&7) ]
// Per planes={4,0}, xoffsets={0,1,2,3} nel nibble:
//   plane 0 pixel c = byte[7 - c]   (MSB del byte, hi-nibble)
//   plane 1 pixel c = byte[3 - c]   (MSB del nibble low)
wire       bg_half_cur = bg_col_sub[2];
wire [7:0] bg_byte01   = bg_half_cur ? bg_pix01_hi : bg_pix01_lo;
wire [7:0] bg_byte23   = bg_half_cur ? bg_pix23_hi : bg_pix23_lo;
wire [1:0] bg_bit_sel  = 2'd3 - bg_col_sub[1:0];
// MAME drawgfx.cpp readbit: src[n/8] & (0x80 >> (n%8)) → MSB-first bit order.
// Per planes = {4, 0, 0xC000*8+4, 0xC000*8+0}:
//   planes[0]=4  → bit (0x80>>4)=bit3. MSB del pen.
//   planes[1]=0  → bit (0x80>>0)=bit7. pen bit 2.
//   planes[2]=4  (+0xC000) → byte23 bit 3. pen bit 1.
//   planes[3]=0  (+0xC000) → byte23 bit 7. pen LSB.
// xoffset[c]=c → bitmask shiftato: bit (3-c) e bit (7-c).
wire       bg_b01_hi = bg_byte01[{1'b0, bg_bit_sel}];   // bit3-c (planes[0], MSB pen)
wire       bg_b01_lo = bg_byte01[{1'b1, bg_bit_sel}];   // bit7-c (planes[1])
wire       bg_b23_hi = bg_byte23[{1'b0, bg_bit_sel}];   // bit3-c (planes[2])
wire       bg_b23_lo = bg_byte23[{1'b1, bg_bit_sel}];   // bit7-c (planes[3], LSB pen)
wire [3:0] bg_pen    = {bg_b01_hi, bg_b01_lo, bg_b23_hi, bg_b23_lo};

// ============================================================
// SPRITE RENDERER (line buffer ping-pong, scanner FSM fedele MAME)
//
// Sprite RAM layout (cpp):
//   offs+0: sy_raw       → sy = 239 - sy_raw
//   offs+1: bit7 = gfxset (c12 vs c13); bit[6:0] = sprite_idx
//   offs+2: bit4 = ~flipx_raw (NB: ~... & 0x10); bit[3:0] = color
//   offs+3: sx
// Y match: sy <= yscan < sy + 16
// flipy = flip_screen (sempre in parallelo al flip_screen globale)
// Pixel layout: 4bpp 8×16
//   base = gfxset_base + idx*16 + row (row = yscan - sy, 0..15)
//   col<4: byte @ base; col>=4: byte @ base + 0x800
//   planes 0/1 dal byte letto; planes 2/3 stesso byte + 0x2000
//
// Draw order MAME: dall'ultimo sprite al primo → il primo è "on top" (sovrascrive).
// ============================================================

// Line buffer 320 px con margini 32 sx + 32 dx (= clear esteso).
// write_addr = sx + col + 32 → range 32..294. read_addr = screen_x + 32 → 32..279.
// Slot 0..31 e 280..319 sono "margine fuori area visibile".
localparam integer SPR_LB_WIDTH = 320;
localparam signed [11:0] SPR_LB_LAST       = 12'sd319;
localparam signed [11:0] SPR_LB_ORIGIN_WR  = 12'sd32;
localparam signed [11:0] SPR_LB_ORIGIN_RD  = 12'sd32;
localparam signed [11:0] SPR_DRAW_X_BIAS   = 12'sd0;

reg [3:0] spr_lb_a [0:SPR_LB_WIDTH-1];
reg [3:0] spr_lb_b [0:SPR_LB_WIDTH-1];
reg [3:0] spr_pal_a [0:SPR_LB_WIDTH-1];
reg [3:0] spr_pal_b [0:SPR_LB_WIDTH-1];
reg       spr_buf_sel;

reg [5:0] spr_scan_idx;
reg [4:0] spr_step;
reg [1:0] spr_byte_idx;
reg [13:0] mame_sprrom_addr;
wire [7:0]  mame_sprite_addr_w = {spr_scan_idx, spr_byte_idx};
reg signed [8:0] spr_ey;   // MAME: sy = 239 - sy_raw. Range [-16..239]. Signed 9-bit.
reg [7:0] spr_attr1, spr_attr2, spr_sx;
reg [7:0] spr_pix01, spr_pix23;  // byte plane 0/1 e 2/3
reg [2:0] spr_write_col;
reg [7:0] yscan_next;
reg       spr_scan_busy;
reg       spr_scan_pending;


// Dichiarazioni forward per buffer clear (definito più sotto). ModelSim richiede
// la dichiarazione prima dell'uso; Quartus accettava forward ref.
reg [8:0] clear_cnt;
reg       clear_busy;

// sprite_addr/sprrom_addr — mux MAME-style vs PCB-gate-level vedi blocco
// `ifdef SPRITE_GATE_LEVEL più sotto.

reg [9:0] hcnt_prev;
wire start_scan = (hcnt != hcnt_prev) && (hcnt == 10'd8);
always @(posedge clk) hcnt_prev <= hcnt;

// row sub dentro lo sprite (4 bit), con flipy
// spr_ey signed → estensione di yscan_next a signed 9-bit per sottrazione corretta.
wire signed [8:0] yscan_s = {1'b0, yscan_next};
wire [3:0] spr_yd      = (yscan_s - spr_ey);  // range valido [0..15] quando in match
wire [3:0] spr_row_sub = flip_screen ? (4'd15 - spr_yd) : spr_yd;

// Sprite ROM addressing (16 KB = 14 bit addr):
//   bit[13] = plane_high (0 = p0/1, 1 = p2/3)           → +0x2000
//   bit[12] = gfxset (0 = c12 entry 1, 1 = c13 entry 2)  → +0x1000
//   bit[11] = col_half (0 = c<4, 1 = c>=4)               → +0x800
//   bit[10:4] = sprite idx (7 bit)
//   bit[3:0]  = row (4 bit, 0..15)

// NOTA: la dual-port RAM sprite ha 1-clock latency. Schema SET→WAIT→LATCH
// (2 clk tra emissione addr e dato stabile).
localparam
	SS_IDLE      = 5'd0,
	SS_SET_SY    = 5'd1,  SS_WAIT_SY    = 5'd2,  SS_LATCH_SY    = 5'd3,
	SS_SET_A1    = 5'd4,  SS_WAIT_A1    = 5'd5,  SS_LATCH_A1    = 5'd6,
	SS_SET_A2    = 5'd7,  SS_WAIT_A2    = 5'd8,  SS_LATCH_A2    = 5'd9,
	SS_SET_SX    = 5'd10, SS_WAIT_SX    = 5'd11, SS_LATCH_SX    = 5'd12,
	SS_CHECK     = 5'd13,
	// Metà sinistra (col 0..3):
	SS_SET_L01   = 5'd14, SS_WAIT_L01   = 5'd15, SS_LATCH_L01   = 5'd16,
	SS_SET_L23   = 5'd17, SS_WAIT_L23   = 5'd18, SS_LATCH_L23   = 5'd19,
	SS_WRITE_L   = 5'd20,
	// Metà destra (col 4..7):
	SS_SET_R01   = 5'd21, SS_WAIT_R01   = 5'd22, SS_LATCH_R01   = 5'd23,
	SS_SET_R23   = 5'd24, SS_WAIT_R23   = 5'd25, SS_LATCH_R23   = 5'd26,
	SS_WRITE_R   = 5'd27,
	SS_NEXT      = 5'd28;

// Flags pre-processati (dopo flip_screen)
// 247 = larghezza area attiva
wire signed [9:0] spr_sx_base = flip_screen ? ($signed(10'd247) - $signed({2'b00, spr_sx}))
                                            : $signed({2'b00, spr_sx});
wire signed [9:0] spr_sx_flip  = spr_sx_base;
// OSD knob spr_off_x_player: offset SOLO agli sprite con scan_idx in range player (0..17).
// Permette di testare se il player car ha bisogno di shift X specifico.
wire        is_player_idx = (spr_scan_idx <= 6'd17);
wire signed [11:0] spr_player_off = is_player_idx
                                  ? $signed({{6{spr_off_x_player[5]}}, spr_off_x_player})
                                  : 12'sd0;
wire signed [11:0] spr_write_addr_bias = SPR_LB_ORIGIN_WR
                                        + SPR_DRAW_X_BIAS
                                        + $signed({{6{spr_off_x[5]}}, spr_off_x})
                                        + spr_player_off;
wire       spr_flipx_raw = ~spr_attr2[4];   // cpp: flipx = ~spriteram[offs+2] & 0x10 → bit4=0 means flip
wire       spr_flipx     = flip_screen ? ~spr_flipx_raw : spr_flipx_raw;
wire       spr_flipy     = flip_screen;

always @(posedge clk) if (reset) begin
	spr_scan_busy    <= 1'b0;
	spr_scan_pending <= 1'b0;
	spr_scan_idx     <= 6'd0;
	spr_step         <= SS_IDLE;
	spr_byte_idx     <= 2'd0;
	spr_buf_sel      <= 1'b0;
	yscan_next       <= 8'd0;
	mame_sprrom_addr <= 14'd0;
	spr_write_col    <= 3'd0;
end else begin
	if (start_scan) begin
		spr_buf_sel      <= ~spr_buf_sel;
		spr_scan_idx     <= 6'd0;
		spr_step         <= SS_IDLE;
		spr_byte_idx     <= 2'd0;
		spr_scan_busy    <= 1'b0;
		spr_scan_pending <= 1'b1;
		// MAME letterale: yscan_next = screen_y (= bitmap_y).
		yscan_next <= screen_y[7:0] + {{2{spr_off_y[5]}}, spr_off_y};
	end else if (spr_scan_pending && !clear_busy) begin
		spr_scan_busy    <= 1'b1;
		spr_scan_pending <= 1'b0;
		spr_scan_idx     <= 6'd63;          // MAME: scan da 63 -> 0 (ultimo scritto = on-top = idx 0)
		spr_step         <= SS_SET_SY;
	end else if (spr_scan_busy) begin
		case (spr_step)
			// Dual-port RAM: 1-clk latency → SET → WAIT → LATCH
			SS_SET_SY:    begin spr_byte_idx <= 2'd0; spr_step <= SS_WAIT_SY;  end
			SS_WAIT_SY:   begin                       spr_step <= SS_LATCH_SY; end
			SS_LATCH_SY:  begin : latch_sy_scope
				// MAME 1:1: sy = 239 - sy_raw (no flip), sy = 238 - sy in flip mode.
				// Cpp: sy = 239 - raw; if (flip) sy = 238 - sy → sy = 238 - (239-raw) = raw - 1.
				reg signed [8:0] sy_new;
				sy_new = flip_screen ? ($signed({1'b0, sprite_q}) - 9'sd1)
				                     : ($signed({1'b0, 8'd239}) - $signed({1'b0, sprite_q}));
				spr_ey <= sy_new;
				// Early-exit: match se sy <= yscan < sy+16 (signed).
				if (($signed({1'b0, yscan_next}) < sy_new) ||
				    ($signed({1'b0, yscan_next}) >= (sy_new + 9'sd16)))
					spr_step <= SS_NEXT;
				else
					spr_step <= SS_SET_A1;
			end

			SS_SET_A1:    begin spr_byte_idx <= 2'd1; spr_step <= SS_WAIT_A1;  end
			SS_WAIT_A1:   begin                       spr_step <= SS_LATCH_A1; end
			SS_LATCH_A1:  begin spr_attr1 <= sprite_q; spr_step <= SS_SET_A2; end

			SS_SET_A2:    begin spr_byte_idx <= 2'd2; spr_step <= SS_WAIT_A2;  end
			SS_WAIT_A2:   begin                       spr_step <= SS_LATCH_A2; end
			SS_LATCH_A2:  begin spr_attr2 <= sprite_q; spr_step <= SS_SET_SX; end

			SS_SET_SX:    begin spr_byte_idx <= 2'd3; spr_step <= SS_WAIT_SX;  end
			SS_WAIT_SX:   begin                       spr_step <= SS_LATCH_SX; end
			SS_LATCH_SX:  begin spr_sx    <= sprite_q; spr_step <= SS_CHECK;  end

			SS_CHECK: begin
				if (($signed({1'b0, yscan_next}) >= spr_ey) &&
				    ($signed({1'b0, yscan_next}) < (spr_ey + 9'sd16)))
					spr_step <= SS_SET_L01;
				else
					spr_step <= SS_NEXT;
			end
			// === Metà sinistra (col 0..3): half=0 ===
			SS_SET_L01: begin
				mame_sprrom_addr <= {1'b0, spr_attr1[7], 1'b0, spr_attr1[6:0], spr_row_sub};
				spr_step <= SS_WAIT_L01;
			end
			SS_WAIT_L01:  begin                       spr_step <= SS_LATCH_L01; end
			SS_LATCH_L01: begin
				spr_pix01 <= sprrom_data;
				// planes 2/3 = +0x2000 (bit 13)
				mame_sprrom_addr <= {1'b1, spr_attr1[7], 1'b0, spr_attr1[6:0], spr_row_sub};
				spr_step <= SS_SET_L23;
			end
			SS_SET_L23:   begin spr_step <= SS_WAIT_L23;  end
			SS_WAIT_L23:  begin spr_step <= SS_LATCH_L23; end
			SS_LATCH_L23: begin
				spr_pix23 <= sprrom_data;
				spr_write_col <= 3'd0;
				spr_step <= SS_WRITE_L;
			end
			SS_WRITE_L: begin : spr_write_l_scope
				// Processiamo ROM half=0 (col sorgente 0..3). 4 pixel.
				// Bit in byte: MSB-first senza flipx (bit 3→col0), inverso con flipx.
				// Destinazione visiva:
				//   !flipx: dst_col = 0..3 (pixel sorgente 0..3 vanno a visiva 0..3)
				//    flipx: dst_col = 7..4 (specchio)
				reg [1:0] b;
				reg       p0, p1, p2, p3;
				reg [3:0] pen;
				reg [2:0] dst_col;
				reg signed [11:0] write_idx;
				reg signed [11:0] write_addr;
				b = 2'd3 - spr_write_col[1:0];             // pixel sorgente 0..3, bit MSB-first
				p0 = spr_pix01[{1'b0, b}];
				p1 = spr_pix01[{1'b1, b}];
				p2 = spr_pix23[{1'b0, b}];
				p3 = spr_pix23[{1'b1, b}];
				pen = {p0, p1, p2, p3};  // p0=MSB (plane 0), p3=LSB (plane 3)
				dst_col   = spr_flipx ? (3'd7 - {1'b0, spr_write_col[1:0]})
				                       : {1'b0, spr_write_col[1:0]};
				write_idx = $signed({{2{spr_sx_flip[9]}}, spr_sx_flip}) + $signed({9'd0, dst_col});
				// Modulo 256 sul (sx+col), poi +bias (= +32 di ORIGIN_WR)
				// Sprite a sx=$FF col=1 → (255+1) mod 256 + 32 = 32 (= screen_x=0)
				write_addr = {3'd0, write_idx[7:0]} + spr_write_addr_bias;
				if ((pen != 4'd0) && (write_addr >= 12'sd0) && (write_addr <= SPR_LB_LAST)) begin
					if (spr_buf_sel == 1'b0) begin
						spr_lb_a [write_addr[8:0]] <= pen;
						spr_pal_a[write_addr[8:0]] <= spr_attr2[3:0];
					end else begin
						spr_lb_b [write_addr[8:0]] <= pen;
						spr_pal_b[write_addr[8:0]] <= spr_attr2[3:0];
					end
				end
				if (spr_write_col == 3'd3) spr_step <= SS_SET_R01;
				spr_write_col <= spr_write_col + 3'd1;
			end
			// === Metà destra (col 4..7): half=1 ===
			SS_SET_R01: begin
				mame_sprrom_addr <= {1'b0, spr_attr1[7], 1'b1, spr_attr1[6:0], spr_row_sub};
				spr_step <= SS_WAIT_R01;
			end
			SS_WAIT_R01:  begin                       spr_step <= SS_LATCH_R01; end
			SS_LATCH_R01: begin
				spr_pix01 <= sprrom_data;
				mame_sprrom_addr <= {1'b1, spr_attr1[7], 1'b1, spr_attr1[6:0], spr_row_sub};
				spr_step <= SS_SET_R23;
			end
			SS_SET_R23:   begin spr_step <= SS_WAIT_R23;  end
			SS_WAIT_R23:  begin spr_step <= SS_LATCH_R23; end
			SS_LATCH_R23: begin
				spr_pix23 <= sprrom_data;
				spr_write_col <= 3'd4;
				spr_step <= SS_WRITE_R;
			end
			SS_WRITE_R: begin : spr_write_r_scope
				// Processiamo ROM half=1 (col sorgente 4..7).
				//   !flipx: dst_col = 4..7
				//    flipx: dst_col = 3..0 (specchio)
				reg [1:0] b;
				reg       p0, p1, p2, p3;
				reg [3:0] pen;
				reg [2:0] dst_col;
				reg signed [11:0] write_idx;
				reg signed [11:0] write_addr;
				b = 2'd3 - spr_write_col[1:0];
				p0 = spr_pix01[{1'b0, b}];
				p1 = spr_pix01[{1'b1, b}];
				p2 = spr_pix23[{1'b0, b}];
				p3 = spr_pix23[{1'b1, b}];
				pen = {p0, p1, p2, p3};  // p0=MSB (plane 0), p3=LSB (plane 3)
				dst_col   = spr_flipx ? (3'd3 - {1'b0, spr_write_col[1:0]})
				                       : (3'd4 + {1'b0, spr_write_col[1:0]});
				write_idx = $signed({{2{spr_sx_flip[9]}}, spr_sx_flip}) + $signed({9'd0, dst_col});
				// Modulo 256 sul (sx+col), poi +bias
				write_addr = {3'd0, write_idx[7:0]} + spr_write_addr_bias;
				if ((pen != 4'd0) && (write_addr >= 12'sd0) && (write_addr <= SPR_LB_LAST)) begin
					if (spr_buf_sel == 1'b0) begin
						spr_lb_a [write_addr[8:0]] <= pen;
						spr_pal_a[write_addr[8:0]] <= spr_attr2[3:0];
					end else begin
						spr_lb_b [write_addr[8:0]] <= pen;
						spr_pal_b[write_addr[8:0]] <= spr_attr2[3:0];
					end
				end
				if (spr_write_col == 3'd7) spr_step <= SS_NEXT;
				spr_write_col <= spr_write_col + 3'd1;
			end
			SS_NEXT: begin
				if (spr_scan_idx == 6'd0) begin
					spr_scan_busy <= 1'b0;
					spr_step <= SS_IDLE;
				end else begin
					spr_scan_idx <= spr_scan_idx - 6'd1;
					spr_step <= SS_SET_SY;
				end
			end
			default: spr_step <= SS_IDLE;
		endcase
	end
end

// Buffer clear (reg dichiarati sopra, forward ref)
always @(posedge clk) if (reset) begin
	clear_cnt  <= 9'd0;
	clear_busy <= 1'b0;
end else begin
	if (start_scan) begin
		clear_cnt  <= 9'd0;
		clear_busy <= 1'b1;
	end else if (clear_busy) begin
		if (spr_buf_sel == 1'b0) begin
			spr_lb_a [clear_cnt] <= 4'd0;
			spr_pal_a[clear_cnt] <= 4'd0;
		end else begin
			spr_lb_b [clear_cnt] <= 4'd0;
			spr_pal_b[clear_cnt] <= 4'd0;
		end
		clear_cnt <= clear_cnt + 9'd1;
		if (clear_cnt == 9'd319) clear_busy <= 1'b0;
	end
end

// Read buffer "current" — combinazionale (distributed RAM, 0 latency).
wire signed [11:0] spr_read_addr_s = $signed({2'b00, screen_x}) + SPR_LB_ORIGIN_RD;
wire       spr_read_ok = (spr_read_addr_s >= 12'sd0) && (spr_read_addr_s <= SPR_LB_LAST);
wire [8:0] spr_read_addr = spr_read_ok ? spr_read_addr_s[8:0] : 9'd0;
wire [3:0] spr_pen_raw = spr_buf_sel ? spr_lb_a [spr_read_addr] : spr_lb_b [spr_read_addr];
wire [3:0] spr_pal_raw = spr_buf_sel ? spr_pal_a[spr_read_addr] : spr_pal_b[spr_read_addr];
wire [3:0] spr_pen_legacy = spr_read_ok ? spr_pen_raw : 4'd0;
wire [3:0] spr_pal_legacy = spr_read_ok ? spr_pal_raw : 4'd0;
wire       spr_opaque_legacy = |spr_pen_legacy;

// ============================================================
// Feeder combinatori per sprite_stage (gate-level PCB)
// Ricostruiscono — fuori dagli scope `SS_WRITE_L`/`SS_WRITE_R` del case —
// gli stessi valori di `pen` e `dst_col` calcolati dentro la FSM, così che
// il subsystem gate-level riceva esattamente lo stream di pixel/colonne che
// il renderer attuale scrive nel line buffer.
// ============================================================
wire        feed_is_R    = (spr_step == SS_WRITE_R);
wire        feed_active  = (spr_step == SS_WRITE_L) || feed_is_R;
wire [1:0]  feed_b       = 2'd3 - spr_write_col[1:0];
wire        feed_p0      = spr_pix01[{1'b0, feed_b}];
wire        feed_p1      = spr_pix01[{1'b1, feed_b}];
wire        feed_p2      = spr_pix23[{1'b0, feed_b}];
wire        feed_p3      = spr_pix23[{1'b1, feed_b}];
wire [3:0]  feed_pen     = {feed_p0, feed_p1, feed_p2, feed_p3};
wire [2:0]  feed_dst_col = spr_flipx
                         ? (feed_is_R ? (3'd3 - {1'b0, spr_write_col[1:0]})
                                       : (3'd7 - {1'b0, spr_write_col[1:0]}))
                         : (feed_is_R ? (3'd4 + {1'b0, spr_write_col[1:0]})
                                       : {1'b0, spr_write_col[1:0]});
wire        feed_load_pulse = (spr_step == SS_LATCH_SX);

`ifdef SPRITE_GATE_LEVEL
// ============================================================
// Sprite stage PCB gate-level (pagine 10+11, rtl/citycon/pld/sprite_pcb.v)
// Sostituisce SIA il line buffer (pagina 11) SIA lo scanner+ROM-fetch
// (pagina 10) con il subsystem PCB-fedele. I segnali `sprite_addr` e
// `sprrom_addr` sono pilotati da sprite_pcb. Lo scanner MAME-style
// (citycon_video.sv:571-749) continua a girare in parallelo ma le sue
// uscite vengono ignorate dal mux finale.
// ============================================================
wire [3:0] pcb_spr_pen, pcb_spr_pal;
wire       pcb_spr_opaque;
wire [7:0] pcb_obj_addr;
wire [13:0] pcb_rom_addr;

sprite_pcb u_sprite_pcb (
	.clk          (clk),
	.ce_pix       (ce_pix),
	.reset_n      (~reset),
	.flip_screen  (flip_screen),
	.hcnt         (hcnt),
	.vcnt         (vcnt),
	.start_scan   (start_scan),
	.obj_addr     (pcb_obj_addr),
	.obj_q        (sprite_q),
	.rom_addr     (pcb_rom_addr),
	.rom_q        (sprrom_data),
	.spr_pen_out  (pcb_spr_pen),
	.spr_pal_out  (pcb_spr_pal),
	.spr_opaque   (pcb_spr_opaque)
);

assign sprite_addr = pcb_obj_addr;
assign sprrom_addr = pcb_rom_addr;

wire [3:0] spr_pen_out = pcb_spr_pen;
wire [3:0] spr_pal_out = pcb_spr_pal;
wire       spr_opaque  = pcb_spr_opaque;
`else
assign sprite_addr = mame_sprite_addr_w;
assign sprrom_addr = mame_sprrom_addr;

wire [3:0] spr_pen_out = spr_pen_legacy;
wire [3:0] spr_pal_out = spr_pal_legacy;
wire       spr_opaque  = spr_opaque_legacy;
`endif

// ============================================================
// PALETTE LOOKUP (unified fetch 2-byte word)
//
// Per ogni pixel scegliamo il palette index:
//   sprite opaque: pal_idx = 0   + {spr_pal_out, spr_pen_out}   (color*16 + pen, 4bpp → base 0, 16 banks)
//   FG opaque:     pal_idx = 640 + 4*scanline + fg_pen[1:0]     (virtual palette via linecolor)
//                  NOTA: pen[1:0] è l'uso "ridotto" — fedeltà max richiede la
//                        virtual palette write che qui non implementiamo.
//   BG fallback:   pal_idx = 256 + {bg_pal[3:0], bg_pen}        (base 256, 16 banks)
// ============================================================

// Selezione indice palette (11-bit word, 0..1663 delle 1664 entries totali).
// Palette mapping:
//   sprite: base 0  + spr_pal*16 + spr_pen           (16 banks × 16 pen)
//   FG:     MAME scrive ogni frame palram[640+4y+i] copiando da palram[512+4*linecolor[y]+i].
//           Invece di replicare il writeback in HW, leggo DIRETTAMENTE da
//           palram[512 + 4*linecolor[y] + pen[1:0]] (sorgente MAME). Equivalente.
//   BG:     base 256 + bg_pal*16 + bg_pen             (16 banks × 16 pen)
wire [10:0] pal_idx_sel;
// FG: virtual palette via linecolor. MAME fa palram[640+4*y+i]=palram[512+4*linecolor[y]+i]
// per i=0..3. Uso fg_pen_idx (priority encoder 5bit→3bit) come i.
// FG: palette[512 + 4*linecolor[y_fg] + pen[1:0]]. linecolor indicizzato
// da y_fg (non y_active) perché MAME fa changecolor(640+4*offs+...) dove
// offs = char_color*8 + row_sub = y_fg.
// MAME 1:1: FG legge dalla VIRTUAL palette palram[640+4*y+pen[1:0]].
// La virtual palette viene scritta in HW via FSM in citycon_top durante VBLANK,
// copiando palram[512+4*linecolor[y]+i] → palram[640+4*y+i] (i=0..3).
assign pal_idx_sel = spr_opaque ? (11'd0   + {3'd0, spr_pal_out, spr_pen_out})
                   : fg_opaque  ? (11'd640 + {1'b0, y_fg[7:0], 2'd0} + {9'd0, fg_pen[1:0]})
                   :              (11'd256 + {3'd0, bg_pal_cur[3:0], bg_pen});

// Fetch 2 byte consecutivi (hi/lo) per word.
// NB: la BRAM palette ha 1-clk latency. Quindi pal_q arriva **1 ciclo dopo**
// l'emissione dell'addr. Latchiamo in base alla phase RITARDATA di 1 clk.
reg       pal_byte_phase;
reg       pal_byte_phase_d;   // phase dell'addr a cui pal_q corrisponde
reg [7:0] pal_hi, pal_lo;
always @(posedge clk) if (reset) begin
	pal_byte_phase   <= 1'b0;
	pal_byte_phase_d <= 1'b0;
end else begin
	pal_byte_phase   <= ~pal_byte_phase;
	pal_byte_phase_d <= pal_byte_phase;
end

always @(posedge clk) begin
	if (pal_byte_phase_d == 1'b0) pal_hi <= pal_q;  // byte pari (2*indx) = RRRRGGGG
	else                          pal_lo <= pal_q;  // byte dispari     = BBBBxxxx
end

wire [15:0] pal_word = {pal_hi, pal_lo};
wire [3:0]  col_r = pal_word[15:12];
wire [3:0]  col_g = pal_word[11:8];
wire [3:0]  col_b = pal_word[7:4];

// ============================================================
// VIRTUAL PALETTE WRITEBACK FSM (MAME 1:1 implementation)
// Ogni frame in vblank esegue il loop:
//   for offs=0..255: indx=linecolor[offs];
//     for i=0..3: palette[640+4*offs+i] = palette[512+4*indx+i]
// 1024 entries × 2 byte = 2048 byte trasferiti per frame.
// ============================================================
localparam VP_IDLE     = 4'd0,
           VP_READ_LC  = 4'd1,
           VP_WAIT_LC  = 4'd2,
           VP_LATCH_LC = 4'd3,
           VP_READ_HI  = 4'd4,
           VP_WAIT_HI  = 4'd5,
           VP_LATCH_HI = 4'd6,
           VP_READ_LO  = 4'd7,
           VP_WAIT_LO  = 4'd8,
           VP_LATCH_LO = 4'd9,
           VP_WRITE_HI = 4'd10,
           VP_WRITE_LO = 4'd11,
           VP_NEXT     = 4'd12;

reg [3:0] vp_state;
reg [7:0] vp_y;
reg [1:0] vp_i;
reg [7:0] vp_linecol;
reg [7:0] vp_hi, vp_lo;
reg       vp_busy;

// Wires per addr palette source/dest (indirizzo BYTE, 12-bit)
wire [11:0] vp_pal_src_hi = {1'b0, 9'd512 + {3'd0, vp_linecol[7:0], 2'd0} + {10'd0, vp_i[1:0]}, 1'b0};
// Compatto: src_word_idx = 512 + 4*linecol + i; src_byte = (idx<<1) | byte_phase
wire [10:0] vp_src_word = 11'd512 + {1'b0, vp_linecol, 2'd0} + {9'd0, vp_i};
wire [10:0] vp_dst_word = 11'd640 + {1'b0, vp_y,       2'd0} + {9'd0, vp_i};

always @(posedge clk) if (reset) begin
	vp_state    <= VP_IDLE;
	vp_y        <= 8'd0;
	vp_i        <= 2'd0;
	vp_busy     <= 1'b0;
	vp_linecol  <= 8'd0;
	vp_hi       <= 8'd0;
	vp_lo       <= 8'd0;
end else begin
	case (vp_state)
		VP_IDLE: begin
			vp_busy <= 1'b0;
			if (vblank_rise) begin
				vp_busy <= 1'b1;
				vp_y    <= 8'd0;
				vp_i    <= 2'd0;
				vp_state <= VP_READ_LC;
			end
		end
		VP_READ_LC:  vp_state <= VP_WAIT_LC;
		VP_WAIT_LC:  vp_state <= VP_LATCH_LC;
		VP_LATCH_LC: begin vp_linecol <= linecol_q; vp_state <= VP_READ_HI; end
		VP_READ_HI:  vp_state <= VP_WAIT_HI;
		VP_WAIT_HI:  vp_state <= VP_LATCH_HI;
		VP_LATCH_HI: begin vp_hi <= pal_q; vp_state <= VP_READ_LO; end
		VP_READ_LO:  vp_state <= VP_WAIT_LO;
		VP_WAIT_LO:  vp_state <= VP_LATCH_LO;
		VP_LATCH_LO: begin vp_lo <= pal_q; vp_state <= VP_WRITE_HI; end
		VP_WRITE_HI: vp_state <= VP_WRITE_LO;
		VP_WRITE_LO: vp_state <= VP_NEXT;
		VP_NEXT: begin
			if (vp_i == 2'd3) begin
				vp_i <= 2'd0;
				if (vp_y == 8'd255) begin
					vp_busy  <= 1'b0;
					vp_state <= VP_IDLE;
				end else begin
					vp_y     <= vp_y + 8'd1;
					vp_state <= VP_READ_LC;
				end
			end else begin
				vp_i <= vp_i + 2'd1;
				vp_state <= VP_READ_HI;
			end
		end
		default: vp_state <= VP_IDLE;
	endcase
end

// Mux pal_addr/pal_we/pal_data: durante vp_busy controllato dal FSM,
// altrimenti dal renderer.
always @(*) begin
	pal_addr = {pal_idx_sel, pal_byte_phase};
	pal_we   = 1'b0;
	pal_data = 8'd0;
	if (vp_busy) begin
		case (vp_state)
			VP_READ_HI, VP_WAIT_HI, VP_LATCH_HI:
				pal_addr = {vp_src_word, 1'b0};   // hi byte (pari)
			VP_READ_LO, VP_WAIT_LO, VP_LATCH_LO:
				pal_addr = {vp_src_word, 1'b1};   // lo byte (dispari)
			VP_WRITE_HI: begin
				pal_addr = {vp_dst_word, 1'b0};
				pal_we   = 1'b1;
				pal_data = vp_hi;
			end
			VP_WRITE_LO: begin
				pal_addr = {vp_dst_word, 1'b1};
				pal_we   = 1'b1;
				pal_data = vp_lo;
			end
			default: ;
		endcase
	end
end

// Mux linecol_addr: durante vp_busy emette vp_y, altrimenti y_fg
always @(*) begin
	if (vp_busy) linecol_addr = vp_y;
	else         linecol_addr = y_fg[7:0];
end

// ============================================================
// Output mixing (MAME order: BG base → FG trans 0 → sprite trans 0)
// ============================================================
always @(posedge clk) if (ce_pix) begin
	vga_hs <= hsync;
	vga_vs <= vsync;
	vga_hb <= hblank;
	vga_vb <= vblank;
	if (hblank | vblank) begin
		vga_r <= 8'd0;
		vga_g <= 8'd0;
		vga_b <= 8'd0;
	end else begin
		vga_r <= {col_r, col_r};
		vga_g <= {col_g, col_g};
		vga_b <= {col_b, col_b};
	end
end

// Unused suppressors
/* verilator lint_off UNUSED */
wire _unused = &{1'b0};
/* verilator lint_on UNUSED */

endmodule
