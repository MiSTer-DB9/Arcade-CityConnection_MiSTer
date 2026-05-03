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

// City Connection (Jaleco 1985) — game top module
// Contiene: main CPU 6809, memory map, dual-port RAMs (CPU ↔ video renderer),
//           input muxing, DIP, IRQ ack, instance del renderer video.
// Il renderer legge le VRAM/palette/linecolor/sprite via porte B dual-port.
//============================================================================

module citycon_top
(
	input             clk,          // 48 MHz
	input             reset,        // game/CPU reset (include download)
	input             video_reset,  // solo ~pll_locked (video sempre attivo)
	input             pause,        // halt CPU when high

	input  signed [5:0] fg_off_x,
	input  signed [5:0] bg_off_x,
	input  signed [5:0] spr_off_x,
	input  signed [5:0] scia_off_x,
	input  signed [5:0] spr_off_y,
	input  signed [5:0] spr_off_x_player,
	input  signed [5:0] scia_scroll_off,
	input         [3:0] width_lshift,

	output            ce_pix,
	output            vblank_irq,

	input      [7:0]  p1_input,
	input      [7:0]  p2_input,
	input      [7:0]  dsw1,
	input      [7:0]  dsw2,

	// Main CPU ROM (BRAM esterna in Template.sv, 48KB: c10 + c11)
	output     [15:0] mrom_addr,   // offset in BRAM (max 0xBFFF usato)
	input       [7:0] mrom_data,

	// Char ROM — espansione on-the-fly (i=src idx 0..0xFFF, k=triplet 0..2)
	output     [11:0] crom_i,
	output      [1:0] crom_k,
	input       [7:0] crom_data,

	// BG tile maps — 56KB (c2+c3+c5, tile codes + palette codes per bg_image)
	output     [15:0] bgmap_addr,
	input       [7:0] bgmap_data,

	// BG tile pixels — 96KB (c9+c8+c6+c7, 4bpp)
	output     [16:0] bgpix_addr,
	input       [7:0] bgpix_data,

	// Sprite ROM — 16KB (c12+c13, 4bpp)
	output     [13:0] sprrom_addr,
	input       [7:0] sprrom_data,

	// Audio comm verso sottosistema audio
	output      [7:0] soundlatch1_out,
	output      [7:0] soundlatch2_out,

	// Video output
	output      [7:0] vga_r,
	output      [7:0] vga_g,
	output      [7:0] vga_b,
	output            vga_hs,
	output            vga_vs,
	output            vga_hb,
	output            vga_vb,

	// Raster counters per overlay
	output      [9:0] render_x,
	output      [8:0] render_y,

	// ROM download
	input             ioctl_download,
	input             ioctl_wr,
	input      [26:0] ioctl_addr,
	input       [7:0] ioctl_dout,
	input      [15:0] ioctl_index
);

// ============================================================
// Clock enables (clk_sys = 40 MHz — MAME MASTER_CLOCK / 2)
//   ce_pix = clk/8  = 5 MHz      (MAME PIXEL_CLOCK esatto)
//   ce_E   = clk/32 = 1.25 MHz   (MAME CPU_CLOCK esatto)
//   ce_Q   = ce_E sfasato di 180° (= +16 clk)
//   Frame: 320×262 / 5 MHz = 59.63 Hz ✓
// ============================================================
// clk_div deve girare SEMPRE (anche durante game reset/download) per generare
// ce_pix stabile al video renderer. NON azzerare con reset.
// ce_pix = clk/8 = 5 MHz (match MAME PIXEL_CLOCK).
reg [4:0] clk_div = 5'd0;  // init Altera power-up
always @(posedge clk) clk_div <= clk_div + 5'd1;
assign ce_pix = (clk_div[2:0] == 3'd0);   // ogni 8 clk → 5 MHz

// CPU MC6809 E clock = 2 MHz (match MAME CPU_CLOCK/4 = 8/4). Divisore 20 su 40MHz.
reg [4:0] cpu_div = 5'd0;
always @(posedge clk) cpu_div <= (cpu_div == 5'd19) ? 5'd0 : cpu_div + 5'd1;
wire   ce_E   = (cpu_div == 5'd0);        // ogni 20 clk → 2 MHz (MAME)
wire   ce_Q   = (cpu_div == 5'd10);       // +180°

// ============================================================
// Main CPU 6809
// ============================================================
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;
wire        cpu_rnw;
wire        cpu_bs, cpu_ba;
reg         irq_n;

mc6809i u_maincpu
(
	.clk     (clk),
	.cen_E   (ce_E),
	.cen_Q   (ce_Q),
	.D       (cpu_din),
	.DOut    (cpu_dout),
	.ADDR    (cpu_addr),
	.RnW     (cpu_rnw),
	.BS      (cpu_bs),
	.BA      (cpu_ba),
	.nIRQ    (irq_n),
	.nFIRQ   (1'b1),
	.nNMI    (1'b1),
	.AVMA    (),
	.BUSY    (),
	.LIC     (),
	.nHALT   (~pause),
	.nRESET  (~reset),
	.nDMABREQ(1'b1),
	.OP      (),
	.RegData (cpu_regdata)
);

wire [111:0] cpu_regdata;
wire [15:0]  cpu_pc = cpu_regdata[111:96];

// ============================================================
// Memory map (da citycon.cpp main_map):
//   $0000-$0FFF  WRAM (4KB)
//   $1000-$1FFF  FG VRAM (4KB)
//   $2000-$27FF  linecolor RAM (256B + mirror 0x700)
//   $2800-$2FFF  sprite RAM (256B + mirror 0x700)
//   $3000        IN / background_w
//   $3001        DSW1 r / soundlatch1 w
//   $3002        DSW2 r / soundlatch2 w
//   $3004-$3005  scroll (hi/lo)
//   $3007        IRQ ack (r)
//   $3800-$3FFF  palette RAM (2KB addr space, 1280B effettivi 0-0x4FF)
//   $4000-$FFFF  ROM
// ============================================================
wire cs_wram    = (cpu_addr[15:12] == 4'h0);
wire cs_vram    = (cpu_addr[15:12] == 4'h1);
wire cs_linecol = (cpu_addr[15:11] == 5'b00100);
wire cs_sprite  = (cpu_addr[15:11] == 5'b00101);
wire cs_reg3000 = (cpu_addr[15:12] == 4'h3) && (cpu_addr[11:8] == 4'h0);
wire cs_pal     = (cpu_addr[15:11] == 5'b00111);
wire cs_rom     = cpu_addr[15] | cpu_addr[14];

// In convenzione Greg Miller / jtframe_sys6809: writes si materializzano su cen_Q
// (ADDR/DOut validi da cen_E, bus write gated da cen_Q).
wire cpu_we = ~cpu_rnw & ce_Q;

// ============================================================
// Renderer → RAM read ports (populated by citycon_video instance)
// ============================================================
wire [11:0] vid_vram_addr;
wire  [7:0] vid_vram_q;
wire  [7:0] vid_linecol_addr;
wire  [7:0] vid_linecol_q;
wire  [7:0] vid_sprite_addr;
wire  [7:0] vid_sprite_q;
wire [11:0] vid_pal_addr;
wire  [7:0] vid_pal_q;
wire        vid_pal_we;
wire  [7:0] vid_pal_data;
wire        vblank_rise;

// ============================================================
// Work RAM (4KB) — dual port (porta B non usata esternamente; placeholder)
// ============================================================
wire [7:0] wram_do;
jtframe_dual_ram_cen #(.DW(8), .AW(12)) u_wram (
	.clk0 (clk), .cen0 (1'b1),
	.data0(cpu_dout), .addr0(cpu_addr[11:0]),
	.we0  (cs_wram & cpu_we), .q0 (wram_do),
	.clk1 (clk), .cen1 (1'b1),
	.data1(8'd0), .addr1(12'd0), .we1(1'b0), .q1()
);

// ============================================================
// FG VRAM (4KB) — dual port: porta A = CPU, porta B = renderer
// ============================================================
wire [7:0] vram_do;
jtframe_dual_ram_cen #(.DW(8), .AW(12)) u_vram (
	.clk0 (clk), .cen0 (1'b1),
	.data0(cpu_dout), .addr0(cpu_addr[11:0]),
	.we0  (cs_vram & cpu_we), .q0 (vram_do),
	.clk1 (clk), .cen1 (1'b1),
	.data1(8'd0), .addr1(vid_vram_addr), .we1(1'b0), .q1(vid_vram_q)
);

// ============================================================
// Linecolor RAM (256B)
// ============================================================
wire [7:0] linecolor_do;
jtframe_dual_ram_cen #(.DW(8), .AW(8)) u_linecolor (
	.clk0 (clk), .cen0 (1'b1),
	.data0(cpu_dout), .addr0(cpu_addr[7:0]),
	.we0  (cs_linecol & cpu_we), .q0 (linecolor_do),
	.clk1 (clk), .cen1 (1'b1),
	.data1(8'd0), .addr1(vid_linecol_addr), .we1(1'b0), .q1(vid_linecol_q)
);

// ============================================================
// Sprite RAM (256B)
//
// The CPU writes a live copy, while the renderer reads a frame snapshot.
// This prevents per-sprite tearing when the CPU updates the four sprite bytes
// in separate passes while the video scanner is walking the table.
// ============================================================
wire [7:0] sprite_do;
// sprite_live_q (= reg) e sprite_live_q_raw (= wire da BRAM) dichiarati piu' sotto
// dopo l'istanza u_spriteram per evitare forward-ref con la combinatoria di shift.

reg        spr_copy_busy;
reg        spr_copy_valid;
reg  [7:0] spr_copy_rd_addr;
reg  [7:0] spr_copy_wr_addr;
reg        spr_copy_we;
reg  [7:0] spr_copy_waddr;
reg  [7:0] spr_copy_wdata;

// TEST: rendering legge direttamente dalla sprite RAM live (no snapshot).
// Bypass del double-buffer per verificare se la race "snapshot durante scrittura
// CPU IRQ vblank" è la causa del shift sprite -4X.
jtframe_dual_ram_cen #(.DW(8), .AW(8)) u_spriteram (
	.clk0 (clk), .cen0 (1'b1),
	.data0(cpu_dout), .addr0(cpu_addr[7:0]),
	.we0  (cs_sprite & cpu_we), .q0 (sprite_do),
	.clk1 (clk), .cen1 (1'b1),
	.data1(8'd0), .addr1(vid_sprite_addr), .we1(1'b0), .q1(sprite_live_q_raw)
);

// SHIFT LOGICO SPRITE: solo sy -1 (= +1Y visivo). sx letterale (no +4).
// Il +4 X era per compensare cliprect MAME 240 px; con area 256 px PCB
// non serve più.
wire [7:0] sprite_live_q_raw;
wire [1:0] vid_byte_idx = vid_sprite_addr[1:0];
reg  [7:0] sprite_live_q;
always @(*) begin
	case (vid_byte_idx)
		2'd0:    sprite_live_q = sprite_live_q_raw - 8'd1;   // sy_raw - 1 (= +1Y visivo)
		default: sprite_live_q = sprite_live_q_raw;
	endcase
end

assign vid_sprite_q = sprite_live_q;
wire [7:0] sprite_render_q = sprite_live_q;  // alias retro-compat

always @(posedge clk) if (reset) begin
	spr_copy_busy    <= 1'b0;
	spr_copy_valid   <= 1'b0;
	spr_copy_rd_addr <= 8'd0;
	spr_copy_wr_addr <= 8'd0;
	spr_copy_we      <= 1'b0;
	spr_copy_waddr   <= 8'd0;
	spr_copy_wdata   <= 8'd0;
end else begin
	spr_copy_we <= 1'b0;

	if (vblank_rise && !spr_copy_busy) begin
		spr_copy_busy    <= 1'b1;
		spr_copy_valid   <= 1'b0;
		spr_copy_rd_addr <= 8'd0;
		spr_copy_wr_addr <= 8'd0;
	end else if (spr_copy_busy) begin
		if (spr_copy_valid) begin
			spr_copy_we    <= 1'b1;
			spr_copy_waddr <= spr_copy_wr_addr;
			spr_copy_wdata <= sprite_live_q;

			if (spr_copy_wr_addr == 8'hFF) begin
				spr_copy_busy  <= 1'b0;
				spr_copy_valid <= 1'b0;
			end else begin
				spr_copy_wr_addr <= spr_copy_wr_addr + 8'd1;
			end
		end else begin
			spr_copy_valid <= 1'b1;
		end

		if (spr_copy_rd_addr != 8'hFF)
			spr_copy_rd_addr <= spr_copy_rd_addr + 8'd1;
	end
end

// ============================================================
// Palette RAM (4 KB = 2048 word entries × 2 byte)
// CPU vede solo $3800-$3FFF (2KB = offset 0-0x7FF, idx word 0-0x3FF usato fino
// 0x27F in base alla map $3800-$3CFF). Le entries idx 640..1663 (byte 0x500-
// 0xCFF) sono "virtual palette" scritte in HW dalla logica di update scanline.
// Per ora la virtual palette non è popolata: il renderer leggerà 0 da quelle
// entries (pixel neri sul FG finché non la implementiamo).
// ============================================================
wire [7:0] pal_do;
jtframe_dual_ram_cen #(.DW(8), .AW(12)) u_palram (
	.clk0 (clk), .cen0 (1'b1),
	.data0(cpu_dout), .addr0({1'b0, cpu_addr[10:0]}),
	.we0  (cs_pal & cpu_we), .q0 (pal_do),
	.clk1 (clk), .cen1 (1'b1),
	.data1(vid_pal_data), .addr1(vid_pal_addr), .we1(vid_pal_we), .q1(vid_pal_q)
);

// ============================================================
// $3000 area registers
// ============================================================
reg  [7:0] scroll_lo, scroll_hi;
reg        flip_screen;
reg  [3:0] bg_image;
reg  [7:0] soundlatch1, soundlatch2;

always @(posedge clk) if (reset) begin
	flip_screen <= 1'b0;
	bg_image    <= 4'd0;
	scroll_lo   <= 8'd0;
	scroll_hi   <= 8'd0;
	soundlatch1 <= 8'd0;
	soundlatch2 <= 8'd0;
	irq_n       <= 1'b1;
end else begin
	// Write registers: gated su ce_Q (convenzione 6809)
	if (cs_reg3000 && !cpu_rnw && ce_Q) begin
		case (cpu_addr[2:0])
			3'h0: begin
				bg_image    <= cpu_dout[7:4];
				flip_screen <= cpu_dout[0];
			end
			3'h1: soundlatch1 <= cpu_dout;
			3'h2: soundlatch2 <= cpu_dout;
			3'h4: scroll_hi   <= cpu_dout;
			3'h5: scroll_lo   <= cpu_dout;
			default: ;
		endcase
	end
	// Read-triggered IRQ ack @ $3007: anche le read "completano" su ce_Q.
	if (cs_reg3000 && cpu_rnw && ce_Q && (cpu_addr[2:0] == 3'h7))
		irq_n <= 1'b1;
	if (vblank_rise)
		irq_n <= 1'b0;
end

// ============================================================
// Input + DSW read mux
// ============================================================
reg [7:0] reg3000_do;
always @(*) begin
	case (cpu_addr[2:0])
		3'h0:    reg3000_do = flip_screen ? p2_input : p1_input;
		3'h1:    reg3000_do = dsw1;
		3'h2:    reg3000_do = dsw2;
		3'h7:    reg3000_do = 8'd0;  // IRQ ack
		default: reg3000_do = 8'hFF;
	endcase
end


// CPU read mux
// ============================================================
always @(*) begin
	casez ({cs_wram, cs_vram, cs_linecol, cs_sprite, cs_pal, cs_reg3000, cs_rom})
		7'b1??????: cpu_din = wram_do;
		7'b01?????: cpu_din = vram_do;
		7'b001????: cpu_din = linecolor_do;
		7'b0001???: cpu_din = sprite_do;
		7'b00001??: cpu_din = pal_do;
		7'b000001?: cpu_din = reg3000_do;
		7'b0000001: cpu_din = mrom_data;
		default:    cpu_din = 8'hFF;
	endcase
end

// ============================================================
// ROM address (CPU $4000-$FFFF → offset 0-0xBFFF in mainrom BRAM)
// ============================================================
// ROM mapping (48KB BRAM):
//   c10 @ CPU $4000-$7FFF (16KB) → mrom 0x0000-0x3FFF
//   c11 @ CPU $8000-$FFFF (32KB) → mrom 0x4000-0xBFFF
// Formula: mrom_addr = cpu_addr - 0x4000 (valida per cs_rom)
assign mrom_addr = cpu_addr - 16'h4000;

// ============================================================
// Video renderer
// ============================================================
wire [15:0] scroll_x = {scroll_hi, scroll_lo};

citycon_video u_video (
	.clk          (clk),
	.reset        (video_reset),   // solo ~pll_locked → video attivo sempre
	.ce_pix       (ce_pix),

	.flip_screen  (flip_screen),
	.scroll_x     (scroll_x),
	.bg_image     (bg_image),

	.fg_off_x     (fg_off_x),
	.bg_off_x     (bg_off_x),
	.spr_off_x    (spr_off_x),
	.scia_off_x   (scia_off_x),
	.spr_off_y    (spr_off_y),
	.spr_off_x_player (spr_off_x_player),
	.width_lshift (width_lshift),

	// VRAM / linecolor / sprite / palette read ports
	.vram_addr    (vid_vram_addr),
	.vram_q       (vid_vram_q),
	.linecol_addr (vid_linecol_addr),
	.linecol_q    (vid_linecol_q),
	.sprite_addr  (vid_sprite_addr),
	.sprite_q     (vid_sprite_q),
	.pal_addr     (vid_pal_addr),
	.pal_q        (vid_pal_q),
	.pal_we       (vid_pal_we),
	.pal_data     (vid_pal_data),

	// Char ROM (expansion on-the-fly)
	.crom_i       (crom_i),
	.crom_k       (crom_k),
	.crom_data    (crom_data),

	// BG maps (tile codes + palette codes)
	.bgmap_addr   (bgmap_addr),
	.bgmap_data   (bgmap_data),

	// BG tile pixels
	.bgpix_addr   (bgpix_addr),
	.bgpix_data   (bgpix_data),

	// Sprite ROM
	.sprrom_addr  (sprrom_addr),
	.sprrom_data  (sprrom_data),

	// Video output
	.vga_r        (vga_r),
	.vga_g        (vga_g),
	.vga_b        (vga_b),
	.vga_hs       (vga_hs),
	.vga_vs       (vga_vs),
	.vga_hb       (vga_hb),
	.vga_vb       (vga_vb),
	.vblank_rise  (vblank_rise),

	.render_x_out (render_x),
	.render_y_out (render_y)
);

assign vblank_irq = vblank_rise;

// Unused suppressors
/* verilator lint_off UNUSED */
assign soundlatch1_out = soundlatch1;
assign soundlatch2_out = soundlatch2;

wire _unused_ok = &{cpu_bs, cpu_ba,
                     ioctl_download, ioctl_wr, ioctl_addr, ioctl_dout, ioctl_index};
/* verilator lint_on UNUSED */

endmodule
