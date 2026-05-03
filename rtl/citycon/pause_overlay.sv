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

// pause_overlay.sv — overlay pausa per City Connection (247×224).
//
// Coord raster HW: render_x = hcnt 32..278, render_y = vcnt 16..239
//
// Layout (in coord HW):
//   - Logo 48×48 (no scaling) top-right (X=224..271, Y=24..71)
//   - LINKS sotto logo (X=180..275, Y=80..215) — 12 char × 17 row
//   - SUPPORTERS header top-left (X=40..119, Y=24) — 10 char × 1 row
//   - PATRONS scroll sotto header (X=40..167, Y=40..231) — 16 char × 24 row visibili

module pause_overlay (
	input  wire        clk,
	input  wire        pause,
	input  wire        clean,    // OSD: bypass overlay (no dim, no logo, no addon)

	input  wire [9:0]  render_x,
	input  wire [8:0]  render_y,

	input  wire [7:0]  rgb_r_in,
	input  wire [7:0]  rgb_g_in,
	input  wire [7:0]  rgb_b_in,

	output wire [7:0]  rgb_r_out,
	output wire [7:0]  rgb_g_out,
	output wire [7:0]  rgb_b_out
);

// Effective overlay: pause attiva ma clean disattivato.
wire overlay_on = pause & ~clean;

// VBlank pulse: rilevato all'ingresso vblank (render_y attraversa 224).
// City Connection: V_ACTIVE=224, V_TOTAL=262 → render_y va 0..261.
reg [8:0] render_y_d;
always @(posedge clk) render_y_d <= render_y;
wire vblank_pulse = (render_y == 9'd224) && (render_y_d == 9'd223);

// =====================================================================
// Logo placement: 48×48 sorgente, NO scaling (entra a destra).
// Top-right: X=192..239, Y=8..55 (margine 7 px da bordo dx, 8 px da top)
// =====================================================================
// Logo SCALE 2x → 96×96 sullo schermo, centrato.
// Centro: X=(32+278)/2=155, Y=(16+239)/2=127. Top-left: (107, 79).
localparam [9:0] LOGO_X    = 10'd107;
localparam [8:0] LOGO_Y    = 9'd79;
localparam [9:0] LOGO_XEND = LOGO_X + 10'd96;     // 96 px = 48 source × 2
localparam [8:0] LOGO_YEND = LOGO_Y + 9'd96;

// Read-ahead: per il pixel corrente serve l'address sul ck precedente.
wire [9:0] x_ahead = render_x + 10'd1;
wire [9:0] dx_screen = x_ahead - LOGO_X;          // 0..95
wire [9:0] dy_screen = {1'b0, render_y} - {1'b0, LOGO_Y};

wire in_logo_ahead = overlay_on &&
	(x_ahead   >= LOGO_X) && (x_ahead   < LOGO_XEND) &&
	(render_y  >= LOGO_Y) && (render_y  < LOGO_YEND);

// SCALE 2x: dx/2, dy/2 (= shift right 1)
// addr = dy*48 + dx. dy 0..47, dx 0..47, max=47*48+47=2303
wire [5:0] dx = dx_screen[6:1];     // / 2
wire [5:0] dy = dy_screen[6:1];     // / 2
wire [11:0] logo_addr = {1'b0, dy, 5'd0} + {2'b0, dy, 4'd0} + {6'd0, dx};

// =====================================================================
// Logo BRAM 2304x2 init da logo/logo.mem
// =====================================================================
reg [1:0] logo_rom [0:2303] /* synthesis ramstyle = "M10K" */;
initial $readmemb("logo/logo.mem", logo_rom);
reg [1:0] logo_pix;
reg       in_logo_now;
always @(posedge clk) begin
	logo_pix    <= logo_rom[logo_addr];
	in_logo_now <= in_logo_ahead;
end

// Palette logo: pal0=nero (trasparente), pal1=magenta, pal2=cyan, pal3=bianco
reg [7:0] lr, lg, lb;
always @(*) case (logo_pix)
	2'd0: {lr, lg, lb} = 24'h000000;
	2'd1: {lr, lg, lb} = 24'hFF00FF;
	2'd2: {lr, lg, lb} = 24'h00E6E4;
	2'd3: {lr, lg, lb} = 24'hFFFFFF;
endcase

wire logo_opaque = 1'b1;

// =====================================================================
// Header "SUPPORTERS" — top-left.
// 10 char × 8 = 80 px. ORIGIN_X = 8, Y = 8.
// =====================================================================
wire       header_on;
wire [1:0] header_tier;
pause_text #(
	.W_CHARS      (10),
	.H_CHARS      (1),
	.MSG_ROWS     (1),
	.ORIGIN_X     (10'd115),   // centrato: (32+278)/2 - 80/2 = 115
	.ORIGIN_Y     (9'd24),     // top + 8 margin
	.SCROLL_EN    (0),
	.FONT_FILE    ("logo/font_darius.hex"),
	.MSG_FILE     ("logo/header.mem")
) u_header (
	.clk          (clk),
	.active       (overlay_on),
	.vblank_pulse (vblank_pulse),
	.render_x     (render_x),
	.render_y     (render_y),
	.pixel_on     (header_on),
	.pixel_tier   (header_tier)
);

// =====================================================================
// Patron scroll — quadrante sinistra full.
// 16 char × 8 = 128 px. ORIGIN_X = 8, Y = 24..215 (= 24 row visibili).
// MSG_ROWS=40 (loop scroll).
// =====================================================================
wire       patron_on;
wire [1:0] patron_tier;
pause_text #(
	.W_CHARS       (30),
	.H_CHARS       (24),
	.MSG_ROWS      (66),
	.ORIGIN_X      (10'd35),   // centrato 247 px area: 32 + (247-240)/2 = 35
	.ORIGIN_Y      (9'd40),    // sotto SUPPORTERS
	.SCROLL_EN     (1),
	.SCROLL_PERIOD (3),
	.FONT_FILE     ("logo/font_darius.hex"),
	.MSG_FILE      ("logo/patrons.mem")
) u_patron (
	.clk          (clk),
	.active       (overlay_on),
	.vblank_pulse (vblank_pulse),
	.render_x     (render_x),
	.render_y     (render_y),
	.pixel_on     (patron_on),
	.pixel_tier   (patron_tier)
);

// =====================================================================
// Links — temporaneamente disabilitati
// =====================================================================
wire       links_on   = 1'b0;
wire [1:0] links_tier = 2'd0;

// Palette tier per i patron (4 livelli):
//   tier 0 = bianco  (default, nessun tier)
//   tier 1 = bronzo/cyan ($3 — base supporters)
//   tier 2 = argento/magenta ($7 — silver supporters)
//   tier 3 = oro     (futuro gold supporters)
function [23:0] tier_color;
	input [1:0] tier;
	begin
		case (tier)
			2'd0: tier_color = 24'hFFFFFF;
			2'd1: tier_color = 24'h00E6E4;
			2'd2: tier_color = 24'hFF00FF;
			2'd3: tier_color = 24'hFFD700;
		endcase
	end
endfunction

// Colori testi:
//   header   = giallo/oro (FFD700)
//   patron   = colore tier
//   links    = colore tier (label cyan, URL bianco)
wire [23:0] header_rgb = 24'hFFD700;
wire [23:0] patron_rgb = tier_color(patron_tier);
wire [23:0] links_rgb  = tier_color(links_tier);

// Priorità mux: logo > header > patron > links > dim > raw
wire text_on = header_on | patron_on | links_on;
wire [23:0] text_rgb = header_on ? header_rgb :
                       links_on  ? links_rgb  :
                                   patron_rgb;

// =====================================================================
// Output mux combinatoriale puro
// =====================================================================
wire [7:0] dim_r = {1'b0, rgb_r_in[7:1]};
wire [7:0] dim_g = {1'b0, rgb_g_in[7:1]};
wire [7:0] dim_b = {1'b0, rgb_b_in[7:1]};

assign rgb_r_out = !overlay_on              ? rgb_r_in :
                   text_on                  ? text_rgb[23:16] :
                   in_logo_now & logo_opaque ? lr        :
                                              dim_r;
assign rgb_g_out = !overlay_on              ? rgb_g_in :
                   text_on                  ? text_rgb[15:8]  :
                   in_logo_now & logo_opaque ? lg        :
                                              dim_g;
assign rgb_b_out = !overlay_on              ? rgb_b_in :
                   text_on                  ? text_rgb[7:0]   :
                   in_logo_now & logo_opaque ? lb        :
                                              dim_b;

endmodule
