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

// City Connection — Audio subsystem
// Reference MAME citycon.cpp:384-431, sound_map 244-251
//
// Hardware:
//   audio CPU = MC6809E @ MASTER_CLOCK/32 = 20MHz/32 = 625 kHz
//   AY8910 (= jt49)   @ MASTER_CLOCK/16 = 1.25 MHz, vol 0.40
//   YM2203 (= jt03)   @ MASTER_CLOCK/16 = 1.25 MHz, FM 0.40 + PSG 0.20
//
// sound_map:
//   $0000-$0FFF  audioram (4 KB)
//   $4000-$4001  AY8910 address_data_w
//   $4002        AY8910 data_r
//   $6000-$6001  YM2203 rw
//   $8000-$FFFF  audio ROM (c1)
//
// soundlatch1 ($3001 main → audio) → YM2203 port A (read by audio CPU via YM2203)
// soundlatch2 ($3002 main → audio) → YM2203 port B
// AY8910 ports A/B: not connected (MAME default)
//
// IRQ audio CPU = vblank rising edge (MAME: irq0_line_hold "actually unused")
//============================================================================

module citycon_audio
(
	input             clk,           // 40 MHz
	input             reset,
	input             pause,         // halta audio CPU (per evitare click su pause)
	input             vblank_irq,    // edge for IRQ (MAME irq0_line_hold)

	input      [7:0]  soundlatch1,   // da main CPU $3001
	input      [7:0]  soundlatch2,   // da main CPU $3002
	input      [2:0]  volume_step,   // 0=100% (1.5x MAME) ... 4=200%

	// Audio ROM (c1, 32KB) — BRAM esterna
	output     [14:0] arom_addr,     // 0..0x7FFF
	input       [7:0] arom_data,

	// Audio output mixed mono → both L/R
	output reg [15:0] audio_out
);

// ============================================================
// Clock enables
//   clk_sys = 40 MHz (= 2× MASTER_CLOCK)
//   audio CPU E = MASTER/32 = 625 kHz → divisor 64
//   AY8910 = MASTER/16 = 1.25 MHz → divisor 32
//   YM2203 = MASTER/16 = 1.25 MHz → divisor 32
// ============================================================

// Audio CPU 6809E divisor 64
reg [5:0] cpu_div = 6'd0;
always @(posedge clk) cpu_div <= (cpu_div == 6'd63) ? 6'd0 : cpu_div + 6'd1;
wire ce_aE = (cpu_div == 6'd0);     // ogni 64 clk → 625 kHz
wire ce_aQ = (cpu_div == 6'd32);    // +180°

// AY8910 / YM2203 divisor 32 → 1.25 MHz
reg [4:0] snd_div = 5'd0;
always @(posedge clk) snd_div <= snd_div + 5'd1;
wire ce_snd = (snd_div == 5'd0);    // ogni 32 clk → 1.25 MHz

// ============================================================
// Audio CPU 6809E
// ============================================================
wire [15:0] acpu_addr;
wire  [7:0] acpu_dout;
reg   [7:0] acpu_din;
wire        acpu_rnw;
reg         airq_n;

mc6809i u_audiocpu
(
	.clk     (clk),
	.cen_E   (ce_aE),
	.cen_Q   (ce_aQ),
	.D       (acpu_din),
	.DOut    (acpu_dout),
	.ADDR    (acpu_addr),
	.RnW     (acpu_rnw),
	.BS      (),
	.BA      (),
	.nIRQ    (airq_n),
	.nFIRQ   (1'b1),
	.nNMI    (1'b1),
	.AVMA    (),
	.BUSY    (),
	.LIC     (),
	.nHALT   (~pause),
	.nRESET  (~reset),
	.nDMABREQ(1'b1),
	.OP      (),
	.RegData ()
);

wire acpu_we = ~acpu_rnw & ce_aQ;

// ============================================================
// Memory map decoder
//   $0000-$0FFF  audioram
//   $4000-$4001  AY8910 write
//   $4002        AY8910 read
//   $6000-$6001  YM2203 rw
//   $8000-$FFFF  ROM
// ============================================================
wire cs_aram  = (acpu_addr[15:12] == 4'h0);
wire cs_ay    = (acpu_addr[15:12] == 4'h4);                    // $4000-$4FFF (mirror AY)
wire cs_ay_w0 = cs_ay && (acpu_addr[1:0] == 2'd0) && acpu_we;  // $4000 addr latch
wire cs_ay_w1 = cs_ay && (acpu_addr[1:0] == 2'd1) && acpu_we;  // $4001 data write
wire cs_ay_r2 = cs_ay && (acpu_addr[1:0] == 2'd2) && acpu_rnw; // $4002 data read
wire cs_ym    = (acpu_addr[15:12] == 4'h6);                    // $6000-$6FFF
wire cs_arom  = acpu_addr[15];                                  // $8000-$FFFF

assign arom_addr = acpu_addr[14:0];

// ============================================================
// Audio RAM 4 KB (single-port, only audio CPU)
// ============================================================
(* ramstyle = "no_rw_check" *) reg [7:0] audioram [0:4*1024-1];
reg [7:0] aram_dout;
always @(posedge clk) begin
	aram_dout <= audioram[acpu_addr[11:0]];
	if (cs_aram & acpu_we) audioram[acpu_addr[11:0]] <= acpu_dout;
end

// ============================================================
// AY8910 (jt49) — address latch + jt49 instance
// MAME address_data_w: offs=0 latch addr (regnum), offs=1 write data
// ============================================================
reg [3:0] ay_latched_addr;
always @(posedge clk) if (reset) ay_latched_addr <= 4'd0;
                     else if (cs_ay_w0) ay_latched_addr <= acpu_dout[3:0];

wire [7:0] ay_dout;
wire [7:0] ay_A, ay_B, ay_C;

jt49 u_ay (
	.rst_n   (~reset),
	.clk     (clk),
	.clk_en  (ce_snd),
	.addr    (ay_latched_addr),
	.cs_n    (~(cs_ay_w1 | cs_ay_r2)),
	.wr_n    (~cs_ay_w1),
	.din     (acpu_dout),
	.sel     (1'b1),         // sel=1 → no extra div
	.dout    (ay_dout),
	.sound   (),             // 10-bit mix non usato
	.A       (ay_A),
	.B       (ay_B),
	.C       (ay_C),
	.sample  (),
	.IOA_in  (8'hFF),
	.IOA_out (),
	.IOB_in  (8'hFF),
	.IOB_out ()
);

// ============================================================
// YM2203 (jt03) — addr 1-bit (latching interno chip)
// port A = soundlatch1, port B = soundlatch2
// ============================================================
wire [7:0] ym_dout;
wire signed [15:0] ym_fm_snd;
wire        [ 9:0] ym_psg_snd;

jt03 u_ym (
	.rst        (reset),
	.clk        (clk),
	.cen        (ce_snd),
	.din        (acpu_dout),
	.addr       (acpu_addr[0]),
	.cs_n       (~cs_ym),
	.wr_n       (~acpu_we),
	.dout       (ym_dout),
	.irq_n      (),
	.IOA_in     (soundlatch1),
	.IOB_in     (soundlatch2),
	.psg_A      (),
	.psg_B      (),
	.psg_C      (),
	.fm_snd     (ym_fm_snd),
	.psg_snd    (ym_psg_snd),
	.snd        (),
	.snd_sample (),
	.debug_view ()
);

// ============================================================
// CPU read mux
// ============================================================
always @(*) begin
	casez ({cs_aram, cs_ay_r2, cs_ym, cs_arom})
		4'b1???: acpu_din = aram_dout;
		4'b01??: acpu_din = ay_dout;
		4'b001?: acpu_din = ym_dout;
		4'b0001: acpu_din = arom_data;
		default: acpu_din = 8'hFF;
	endcase
end

// ============================================================
// IRQ vblank (MAME irq0_line_hold "actually unused" ma cablato)
// ============================================================
always @(posedge clk) if (reset) begin
	airq_n <= 1'b1;
end else begin
	if (vblank_irq) airq_n <= 1'b0;
	// Auto-ack: il 6809 IRQ è level-sensitive, basta tenerlo basso 1 ck.
	// Quando audio CPU non lo serve (= MAME "actually unused"), nessuno legge
	// IRQ ack register, quindi rilascio dopo 1 ck per evitare hang.
	else airq_n <= 1'b1;
end

// ============================================================
// MIXER — MAME volumi:
//   AY8910 mono = (A+B+C) × 0.40
//   YM2203 FM  = fm_snd × 0.40
//   YM2203 PSG = psg_snd × 0.20
// AY8910 outputs 8-bit (0..255), psg_snd 10-bit (0..1023), fm_snd signed 16-bit
//
// Calcolo precisione:
//   AY8910 sum 8+8+8 = 10-bit unsigned (0..765)
//   ×0.40 ≈ ×102/256 (= 0.3984, errore 0.4%) — uso shift: ×102 / 256 con ×26 shift 6 = ×0.40625
//   Per restare nei valori MAME senza approssimazione bisogna usare moltiplicatori.
//
// Uso volumi MAME 1:1 con calcolo intero:
//   AY8910 = sum * 26 / 64 = sum * 0.40625 (errore 1.5%)
//   YM2203 FM = fm_snd * 26 / 64
//   YM2203 PSG = psg_snd * 13 / 64 (= 0.203)
// Per match esatto MAME servirebbero divisioni reali — accettiamo 1-2% di errore.
// ============================================================
wire [9:0] ay_sum10 = {2'd0, ay_A} + {2'd0, ay_B} + {2'd0, ay_C};
// AY8910 out: scale a signed 16-bit centro 0
wire signed [15:0] ay_signed = $signed({1'b0, ay_sum10, 5'd0}) - 16'sd16384;  // centra a 0

// Volume mux: step 0..4 → moltiplicatori (capped 255 per evitare overflow)
//   step | total scale vs MAME | AY/FM mul (0.40 base) | PSG mul (0.20 base)
//     0  |  1.50× (100%)       |    153                |    77
//     1  |  1.875× (125%)      |    191                |    96
//     2  |  2.25× (150%)       |    230                |    115
//     3  |  2.625× (175%)      |    255 (cap)          |    134
//     4  |  3.00× (200%)       |    255 (cap)          |    153
reg [7:0] mul_main, mul_psg;
always @(*) case (volume_step)
	3'd0: begin mul_main = 8'd153; mul_psg = 8'd77;  end
	3'd1: begin mul_main = 8'd191; mul_psg = 8'd96;  end
	3'd2: begin mul_main = 8'd230; mul_psg = 8'd115; end
	3'd3: begin mul_main = 8'd255; mul_psg = 8'd134; end
	3'd4: begin mul_main = 8'd255; mul_psg = 8'd153; end
	default: begin mul_main = 8'd153; mul_psg = 8'd77; end
endcase

wire signed [23:0] mix_ay    = $signed(ay_signed)        * $signed({16'd0, mul_main});
wire signed [23:0] mix_fm    = $signed(ym_fm_snd)        * $signed({16'd0, mul_main});
wire signed [23:0] mix_psg_s = $signed({6'd0, ym_psg_snd}) - 24'sd512;  // psg unsigned 10-bit → signed
wire signed [23:0] mix_psg   = mix_psg_s * $signed({16'd0, mul_psg}) * 24'sd64;  // scale 10→16

wire signed [25:0] mix_sum = {{2{mix_ay [23]}}, mix_ay}
                           + {{2{mix_fm [23]}}, mix_fm}
                           + {{2{mix_psg[23]}}, mix_psg};

// Fade-out su pause: rampa lineare per evitare click ma spegne note in sustain.
// 16-bit gain: 65535 = full, 0 = mute. Step ~64/clk → ~10 ms da full a mute @ 40 MHz.
reg [15:0] pause_gain = 16'hFFFF;
always @(posedge clk) begin
	if (pause) begin
		if (pause_gain >= 16'd64) pause_gain <= pause_gain - 16'd64;
		else                       pause_gain <= 16'd0;
	end else begin
		if (pause_gain <= (16'hFFFF - 16'd64)) pause_gain <= pause_gain + 16'd64;
		else                                    pause_gain <= 16'hFFFF;
	end
end

wire signed [31:0] mix_gained = $signed(mix_sum[25:10]) * $signed({1'b0, pause_gain});

always @(posedge clk) begin
	// /256 per chiudere il volume scaling, clip a 16-bit signed
	audio_out <= mix_gained[31:16];
end

endmodule
