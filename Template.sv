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

    Based on the MiSTer "Template" wrapper by Sorgelig — kept here as the
    project entry point that wires the citycon_top game core to the MiSTer
    framework (HPS/IO, video scaler, audio, OSD).

*/

// City Connection (Jaleco 1985) — MiSTer core
//============================================================================

// Sprite stage gate-level (PCB Jaleco): commentare per usare il renderer
// "MAME-style" originale del core. Quando definito, citycon_video.sv mux-a
// le uscite dal modulo sprite_pcb (rtl/citycon/pld/sprite_pcb.v) al posto
// del line buffer scritto in citycon_video.sv.
//`define SPRITE_GATE_LEVEL

module emu
(
	input         CLK_50M,
	input         RESET,
	inout  [48:0] HPS_BUS,
	output        CLK_VIDEO,
	output        CE_PIXEL,
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER,
	output        VGA_DISABLE,
	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,
`ifdef MISTER_FB_PALETTE
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,
	output  [1:0] BUTTONS,

	input         CLK_AUDIO,
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,
	output  [1:0] AUDIO_MIX,

	inout   [3:0] ADC_BUS,

	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Unused ports /////////
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
// Pause: toggle on rising edge of joy[12] (standard MiSTer pause bit)
reg pause_toggle;
reg joy_pause_prev;
always @(posedge clk_sys) begin
	if (reset) begin
		pause_toggle <= 1'b0;
		joy_pause_prev <= 1'b0;
	end else begin
		joy_pause_prev <= joy0[12] | joy1[12];
		if ((joy0[12] | joy1[12]) && !joy_pause_prev)
			pause_toggle <= ~pause_toggle;
	end
end
wire pause = pause_toggle;  // solo pad (joy[12])
assign HDMI_FREEZE = 1'b0;  // pausa NON freeza HDMI (= continua a mostrare frame live)
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;          // signed
assign AUDIO_L = audio_out;  // mute "naturale" via audio CPU haltata in pause
assign AUDIO_R = audio_out;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

// OSD offset X per calibrazione HW. 6-bit (0..63) interpretato two's complement:
//   0..31  → 0..+31
//   32..63 → -32..-1
wire signed [5:0] fg_off_x   = status[45:40] + 6'sd1;
wire signed [5:0] bg_off_x   = status[51:46] + 6'sd1;
wire signed [5:0] spr_off_x  = status[57:52] - 6'sd1;
wire signed [5:0] scia_off_x = status[63:58];
wire signed [5:0] spr_off_y  = status[69:64];
wire signed [5:0] spr_off_x_player = status[75:70];
wire signed [5:0] scia_scroll_off  = status[81:76];   // intercept lettura $0B durante dispatcher scia $D14B
// width_lshift: distribuzione degli 8 px extra (gioco a 248 px) tra sinistra e destra.
// 0..8 = quanti px vanno a sinistra (resto a destra). Default 4 = centrato (4 sx, 4 dx).
wire [3:0] width_lshift = status[85:82];
// Audio volume boost: 0=100% (default 1.5x MAME), 1=125%, 2=150%, 3=175%, 4=200%
wire [2:0] volume_step  = status[88:86];


`include "build_id.v"
localparam CONF_STR = {
	"CityConnection;;",
	"-;",
	"P1,Video;",
	"P1O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[7:5],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
	"P1-;",
	// Tweak schermo (OSD nascoste — logica interna invariata):
	// "P1O[45:40],FG X offset,0,+1,...,-1;",
	// "P1O[51:46],BG X offset,0,+1,...,-1;",
	// "P1O[57:52],Sprite X offset,0,+1,...,-1;",
	// "P1O[63:58],Scia X offset,0,+1,...,-1;",
	// "P1O[69:64],Sprite Y offset,0,+1,...,-1;",
	// "P1O[75:70],Player X offset,0,+1,...,-1;",
	// "P1O[81:76],Scia scroll patch,0,+1,...,-1;",
	// "P1O[85:82],8px shift left,0,1,2,3,4,5,6,7,8;",
	"O[18],Clean Pause,Off,On;",
	"-;",
	"P2,Audio;",
	"P2O[88:86],Volume,100%,125%,150%,175%,200%;",
	"-;",
	"DIP;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"-;",
	"J1,Fire,Jump,Start 1P,Start 2P,Coin;",
	"jn,A,B,Start,Select,R;",
	"V,v",`BUILD_DATE
};

wire forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire [15:0] joy0, joy1;
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire        ioctl_wait;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),
	.ps2_key(ps2_key),
	.joystick_0(joy0),
	.joystick_1(joy1),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);

// DIP switches — loaded from MRA via ioctl (index 254)
reg  [7:0] dsw1 = 8'hFF;
reg  [7:0] dsw2 = 8'hFF;
always @(posedge clk_sys)
	if (ioctl_wr && (ioctl_index == 16'd254)) begin
		if (ioctl_addr[0] == 1'b0) dsw1 <= ioctl_dout;
		if (ioctl_addr[0] == 1'b1) dsw2 <= ioctl_dout;
	end

// ============================================================
// Joystick → City Connection input mapping
// MAME P1 port (active-low): b7=START2, b6=START1, b5=FIRE2, b4=FIRE1,
//   b3=LEFT, b2=RIGHT, b1=DOWN, b0=UP
// MiSTer joy: [0]=R [1]=L [2]=D [3]=U [4]=A(Fire) [5]=B(Jump)
//             [10]=Start [11]=Coin
// ============================================================
wire [7:0] p1_input = ~{joy1[10], joy0[10], joy0[5], joy0[4],
                         joy0[1], joy0[0], joy0[2], joy0[3]};
wire [7:0] p2_input = ~{joy1[10], joy0[10], joy1[5], joy1[4],
                         joy1[1], joy1[0], joy1[2], joy1[3]};

// COIN handling: DSW1 bit 7 è IPT_COIN1 — joy direct
wire coin1 = joy0[11] | joy1[11];
wire [7:0] dsw1_live = {~coin1, dsw1[6:0]};

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

// Reset della CPU/gioco: include download (game in reset finché ROM arriva).
wire reset = RESET | status[0] | buttons[1] | ~pll_locked | ioctl_download;

// Reset del video: SOLO ~pll_locked. Il video deve generare sync sempre, anche
// durante download, altrimenti il framework Sorgelig non mostra il memtest.
wire video_reset = ~pll_locked;

///////////////////////   SDRAM (stub, porta singola)   //////////

// Stub SDRAM tied-off — l'uso reale sarà definito nel game module.
// TODO: istanziare il controller Sorgelig quando servirà per ROM banks.
assign SDRAM_CLK = 1'b0;
assign SDRAM_CKE = 1'b0;
assign SDRAM_A   = 13'd0;
assign SDRAM_BA  = 2'd0;
assign SDRAM_DQ  = 16'hZZZZ;
assign SDRAM_DQML = 1'b1;
assign SDRAM_DQMH = 1'b1;
assign SDRAM_nCS  = 1'b1;
assign SDRAM_nCAS = 1'b1;
assign SDRAM_nRAS = 1'b1;
assign SDRAM_nWE  = 1'b1;

///////////////////////   MAIN ROM BRAM (48KB)  ///////////////////
(* ramstyle = "no_rw_check" *) reg [7:0] mainrom [0:48*1024-1];
wire        mrom_we = ioctl_download && ioctl_wr && ioctl_index == 16'd0
                      && ioctl_addr < 27'h0C000;
wire [15:0] mrom_addr;
reg   [7:0] mrom_data;
always @(posedge clk_sys) begin
	mrom_data <= mainrom[mrom_addr[15:0]];
	if (mrom_we) mainrom[ioctl_addr[15:0]] <= ioctl_dout;
end

///////////////////////   AUDIO CPU ROM BRAM (32KB)  /////////////
// c1: ioctl 0x0C000-0x13FFF (32KB). Audio CPU vede ROM a $8000-$FFFF.
// arom_addr range 0..0x7FFF, indirizzato dal 6809 audio con (cpu_addr & 0x7FFF).
(* ramstyle = "no_rw_check" *) reg [7:0] audrom [0:32*1024-1];
wire        arom_we = ioctl_download && ioctl_wr && ioctl_index == 16'd0
                      && ioctl_addr >= 27'h0C000 && ioctl_addr < 27'h14000;
wire [14:0] arom_wraddr = ioctl_addr[14:0] - 15'h4000;  // 0x0C000-0x0C000=0, ma [14:0]=$4000 → wrap → -$4000
wire [14:0] arom_addr;
reg   [7:0] arom_data;
always @(posedge clk_sys) begin
	arom_data <= audrom[arom_addr];
	if (arom_we) audrom[arom_wraddr] <= ioctl_dout;
end

///////////////////////   CHAR ROM BRAM (4KB source)  /////////////
// Region "chars" c4: MRA offset 0x14000-0x14FFF (usiamo solo primi 4KB,
// come fa init_citycon MAME).
// Expansion 2bpp→5bpp on-the-fly: renderer ci passa (i, k) dove i=src index
// 0..0xFFF e k=byte triplet 0..2. Noi leggiamo src[i] e componiamo il byte
// espanso come MAME fa in init_citycon.
(* ramstyle = "no_rw_check" *) reg [7:0] charrom [0:4*1024-1];
wire crom_we = ioctl_download && ioctl_wr && ioctl_index == 16'd0
               && ioctl_addr >= 27'h14000 && ioctl_addr < 27'h15000;
always @(posedge clk_sys)
	if (crom_we) charrom[ioctl_addr[11:0]] <= ioctl_dout;

// Interfaccia verso il renderer: (crom_i 12-bit, crom_k 2-bit) → crom_data
wire [11:0] crom_i;
wire [ 1:0] crom_k;

reg  [ 7:0] crom_src_r;
reg  [ 2:0] crom_i_r;
reg  [ 1:0] crom_k_r;

always @(posedge clk_sys) begin
	crom_src_r <= charrom[crom_i];
	crom_i_r   <= crom_i[2:0];
	crom_k_r   <= crom_k;
end

wire [7:0] crom_mask = crom_src_r | (crom_src_r << 4) | (crom_src_r >> 4);
reg  [ 7:0] crom_data;

always @(posedge clk_sys) begin
	case (crom_k_r)
		2'd0: crom_data <= crom_src_r;
		2'd1: crom_data <= (crom_i_r[0] ? (crom_mask & 8'hF0) : 8'd0)
		                 | (crom_i_r[1] ? (crom_mask & 8'h0F) : 8'd0);
		2'd2: crom_data <= (crom_i_r[2] ? (crom_mask & 8'hF0) : 8'd0);
		default: crom_data <= 8'd0;
	endcase
end

///////////////////////   BG TILE MAPS BRAM (56KB)  ///////////////
// MRA offset 0x32000-0x3FFFF (region "bgtiles2" c2+c3+c5)
// c2 32KB @ 0x0000-0x7FFF (tile codes for bg_image 0..7)
// c3 16KB @ 0x8000-0xBFFF (tile codes for bg_image 8..11)
// c5  8KB @ 0xC000-0xDFFF (palette codes for bg_image 0..7)
(* ramstyle = "no_rw_check" *) reg [7:0] bgmap_rom [0:56*1024-1];
wire [15:0] bgmap_wraddr = ioctl_addr[15:0] - 16'h2000;
wire        bgmap_we = ioctl_download && ioctl_wr && ioctl_index == 16'd0
                       && ioctl_addr >= 27'h32000 && ioctl_addr < 27'h40000;
wire [15:0] bgmap_addr;
reg   [7:0] bgmap_data;
// Fuso in un solo always: Quartus infer simple dual-port BRAM
always @(posedge clk_sys) begin
	bgmap_data <= bgmap_rom[bgmap_addr];
	if (bgmap_we) bgmap_rom[bgmap_wraddr] <= ioctl_dout;
end

///////////////////////   BG TILE PIXELS BRAM (96KB)  /////////////
// MRA offset 0x1A000-0x31FFF (region "bgtiles1" c9+c8+c6+c7)
// Layout: c9 32KB @ 0x00000, c8 16KB @ 0x08000, c6 32KB @ 0x0C000, c7 16KB @ 0x14000
(* ramstyle = "no_rw_check" *) reg [7:0] bgpix_rom [0:96*1024-1];
wire [17:0] bgpix_wraddr = ioctl_addr[17:0] - 18'h1A000;
wire        bgpix_we = ioctl_download && ioctl_wr && ioctl_index == 16'd0
                       && ioctl_addr >= 27'h1A000 && ioctl_addr < 27'h32000;
wire [16:0] bgpix_addr;
reg   [7:0] bgpix_data;
always @(posedge clk_sys) begin
	bgpix_data <= bgpix_rom[bgpix_addr];
	if (bgpix_we) bgpix_rom[bgpix_wraddr[16:0]] <= ioctl_dout;
end

///////////////////////   SPRITE ROM BRAM (16KB)  /////////////////
(* ramstyle = "no_rw_check" *) reg [7:0] spr_rom [0:16*1024-1];
wire [13:0] sprrom_wraddr = ioctl_addr[13:0] - 14'h2000;
wire        sprrom_we = ioctl_download && ioctl_wr && ioctl_index == 16'd0
                        && ioctl_addr >= 27'h16000 && ioctl_addr < 27'h1A000;
wire [13:0] sprrom_addr;
reg   [7:0] sprrom_data;
always @(posedge clk_sys) begin
	sprrom_data <= spr_rom[sprrom_addr];
	if (sprrom_we) spr_rom[sprrom_wraddr] <= ioctl_dout;
end

///////////////////////   GAME   ///////////////////////////////////
wire        ce_pix;
wire        vblank_irq;
wire  [7:0] game_r, game_g, game_b;
wire        game_hs, game_vs, game_hb, game_vb;
wire  [7:0] soundlatch1, soundlatch2;
wire [15:0] audio_out;
wire  [9:0] render_x;
wire  [8:0] render_y;

citycon_audio audio
(
	.clk          (clk_sys),
	.reset        (reset),
	.pause        (pause),
	.vblank_irq   (vblank_irq),
	.soundlatch1  (soundlatch1),
	.soundlatch2  (soundlatch2),
	.volume_step  (volume_step),
	.arom_addr    (arom_addr),
	.arom_data    (arom_data),
	.audio_out    (audio_out)
);

citycon_top game
(
	.clk            (clk_sys),
	.reset          (reset),
	.video_reset    (video_reset),
	.pause          (pause),
	.ce_pix         (ce_pix),
	.vblank_irq     (vblank_irq),

	.fg_off_x       (fg_off_x),
	.bg_off_x       (bg_off_x),
	.spr_off_x      (spr_off_x),
	.spr_off_y      (spr_off_y),
	.spr_off_x_player (spr_off_x_player),
	.scia_scroll_off  (scia_scroll_off),
	.scia_off_x     (scia_off_x),
	.width_lshift   (width_lshift),

	.p1_input       (p1_input),
	.p2_input       (p2_input),
	.dsw1           (dsw1_live),
	.dsw2           (dsw2),

	.mrom_addr      (mrom_addr),
	.mrom_data      (mrom_data),

	.crom_i         (crom_i),
	.crom_k         (crom_k),
	.crom_data      (crom_data),

	.bgmap_addr     (bgmap_addr),
	.bgmap_data     (bgmap_data),

	.bgpix_addr     (bgpix_addr),
	.bgpix_data     (bgpix_data),

	.sprrom_addr    (sprrom_addr),
	.sprrom_data    (sprrom_data),

	.soundlatch1_out (soundlatch1),
	.soundlatch2_out (soundlatch2),

	.vga_r          (game_r),
	.vga_g          (game_g),
	.vga_b          (game_b),
	.vga_hs         (game_hs),
	.vga_vs         (game_vs),
	.vga_hb         (game_hb),
	.vga_vb         (game_vb),

	.render_x       (render_x),
	.render_y       (render_y),

	.ioctl_download (ioctl_download),
	.ioctl_wr       (ioctl_wr),
	.ioctl_addr     (ioctl_addr),
	.ioctl_dout     (ioctl_dout),
	.ioctl_index    (ioctl_index)
);

///////////////////////   VIDEO   //////////////////////////////////
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_HS    = game_hs;
assign VGA_VS    = game_vs;
// VGA_DE è pilotato da video_freak (non qui); VGA_DE_IN alla riga sotto gli passa il DE-raw.
// Pause overlay: dim video + logo + supporters durante pausa.
// OSD "Clean Pause" (status[18]): ON=video raw senza addon, OFF=overlay attivo.
pause_overlay u_pause_ovl (
	.clk       (clk_sys),
	.pause     (pause),
	.clean     (status[18]),
	.render_x  (render_x),
	.render_y  (render_y),
	.rgb_r_in  (game_r),
	.rgb_g_in  (game_g),
	.rgb_b_in  (game_b),
	.rgb_r_out (VGA_R),
	.rgb_g_out (VGA_G),
	.rgb_b_out (VGA_B)
);

wire [11:0] arx = (!ar) ? 12'd4 : (ar - 1'd1);
wire [11:0] ary = (!ar) ? 12'd3 : 12'd0;

video_freak video_freak
(
	.CLK_VIDEO(clk_sys),
	.CE_PIXEL(ce_pix),
	.VGA_VS(game_vs),
	.HDMI_WIDTH(HDMI_WIDTH),
	.HDMI_HEIGHT(HDMI_HEIGHT),
	.VGA_DE(VGA_DE),
	.VIDEO_ARX(VIDEO_ARX),
	.VIDEO_ARY(VIDEO_ARY),
	.VGA_DE_IN(~(game_hb | game_vb)),
	.ARX(arx),
	.ARY(ary),
	.CROP_SIZE(12'd0),
	.CROP_OFF(5'd0),
	.SCALE(status[7:5])
);

assign LED_USER = ioctl_download;

endmodule
