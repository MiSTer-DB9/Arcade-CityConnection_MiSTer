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

// ============================================================
// sprite_stage — PCB pagina 11 gate-level (City Connection)
// Line buffer + output stage costruiti con primitivi PCB reali:
//   - LS161 B7+B10  : counter sx 8-bit con LOAD parallelo
//   - LS86  A9+A10  : XOR per flipx (HREV) sull'address line buffer
//   - LS283 B8      : adder con WRITE_BIAS (offset write)
//   - 6148  ×4      : line buffer 2 banchi ping-pong (pen + color, 4 bit cad.)
//   - LS273 A6+D6   : latch output dal banco di lettura
//   - LS157 E6+B6   : mux ping-pong finale → OBJ0..OBJ7
//   - PAL H7        : sequencer ER1/ER2 (read enable A/B), OW1/OW2 (write
//                      enable A/B), LT1/LT2 (latch output A/B)
//
// Interfacce esterne identiche alla versione hybrid: ricevuti dai feeder di
// citycon_video.sv i segnali "scanner-side" (sx/flipx/col_bank latched al
// load_pulse, e stream di pen/dst_col durante il fetch ROM), produce
// spr_pen_out / spr_pal_out / spr_opaque al pixel rate.
//
// SCANNER (pagina 10) NON è ancora gate-level — resta MAME-style sopra di
// noi (citycon_video.sv:571-749). Quando passeremo allo scanner gate-level,
// solo i feeder verranno sostituiti, questo modulo non cambia.
// ============================================================

module sprite_stage (
    input  wire        clk,             // clk_sys (48 MHz)
    input  wire        ce_pix,          // pixel clock enable (= clk/8)
    input  wire        reset_n,

    input  wire        flip_screen,

    // hcnt/vcnt (per gating start_scan e read_addr)
    input  wire  [9:0] hcnt,
    input  wire  [8:0] vcnt,

    // Trigger inizio scanline (= start_scan del renderer)
    input  wire        start_scan,

    // Input dal scanner sprite (MAME-style upstream per ora)
    input  wire  [7:0] in_sx,           // OB0..OB7
    input  wire  [3:0] in_col_bank,     // COL0..COL3
    input  wire        in_flipx,        // HREV
    input  wire        in_load_pulse,   // pulse 1ck: latcha sx in B7+B10

    input  wire  [3:0] in_pen,          // S0..S3 = sprite pen
    input  wire        in_pen_valid,    // pulse: questo pen è valido
    input  wire  [2:0] in_pen_col,      // dst_col 0..7 (post-flipx)

    // Output: sprite pixel a screen_x corrente
    output wire  [3:0] spr_pen_out,    // OBJ0..OBJ3
    output wire  [3:0] spr_pal_out,    // OBJ4..OBJ7
    output wire        spr_opaque
);

// ============================================================
// E8/E7 LS174 — latch attribute (HREV, COL_bank, sx)
// (qui rappresentato come `always @(posedge clk)` registered su load_pulse)
// ============================================================
reg       hrev_q;            // HREV → flipx_signal
reg [3:0] col_bank_q;        // COL0..COL3
reg [7:0] sx_load_q;         // OB0..OB7 (verso B7+B10 LOAD)

always @(posedge clk) begin
    if (~reset_n) begin
        hrev_q     <= 1'b0;
        col_bank_q <= 4'd0;
        sx_load_q  <= 8'd0;
    end else if (in_load_pulse) begin
        hrev_q     <= in_flipx;
        col_bank_q <= in_col_bank;
        sx_load_q  <= in_sx;
    end
end

// ============================================================
// B7 + B10 LS161 — counter sx 8-bit con LOAD parallelo
//
// LOAD: in_load_pulse (latcha sx_load_q in Q0..Q7)
// COUNT: durante in_pen_valid (incrementa di 1 per pixel scritto)
// CLR_n: reset_n
//
// NB: i 2 chip cascadati: B7 = bit 0..3, B10 = bit 4..7
//   B7  ENT=ENP=count_en, B10 ENT=B7.RCO, B10 ENP=count_en
// ============================================================
wire        count_en   = in_pen_valid;
wire        load_n     = ~in_load_pulse;
wire        clr_n      = reset_n;

wire [3:0]  q_lo;
wire        rco_lo;
wire [3:0]  q_hi;

ttl_74ls161 u_b7 (
    .clk    (clk),
    .clr_n  (clr_n),
    .load_n (load_n),
    .enp    (count_en),
    .ent    (count_en),
    .p      (sx_load_q[3:0]),
    .q      (q_lo),
    .rco    (rco_lo)
);

ttl_74ls161 u_b10 (
    .clk    (clk),
    .clr_n  (clr_n),
    .load_n (load_n),
    .enp    (count_en),
    .ent    (count_en & rco_lo),
    .p      (sx_load_q[7:4]),
    .q      (q_hi),
    .rco    ()
);

wire [7:0] sx_counter = {q_hi, q_lo};

// ============================================================
// A9 + A10 LS86 — XOR ×8 con HREV per flip H
// PCB: ogni Q passa per uno XOR con HREV → A0..A7 (address scrittura LB)
//
// NOTA: per ora HREV upstream è già applicato dallo scanner MAME-style
// che invia in_pen_col post-flipx. Per evitare doppio flip, qui forziamo
// il 2° input dello XOR a 0 (= passthrough). Quando lo scanner upstream
// diventerà gate-level e invierà pixel in ordine "naturale" PCB, basterà
// cablare hrev_q come 2° input.
// ============================================================
wire flipx_to_xor = 1'b0;     // TODO: rimettere `hrev_q` quando scanner sarà gate-level

wire [3:0] a_lo;
wire [3:0] a_hi;

ttl_74ls86 u_a9 (
    .a (q_lo),
    .b ({4{flipx_to_xor}}),
    .y (a_lo)
);

ttl_74ls86 u_a10 (
    .a (q_hi),
    .b ({4{flipx_to_xor}}),
    .y (a_hi)
);

wire [7:0] xor_addr = {a_hi, a_lo};

// ============================================================
// B8 LS283 — adder per offset di scrittura
// WRITE_BIAS = 32 per matchare il legacy SPR_LB_ORIGIN_WR.
// TODO PCB-fedele: derivare bit-by-bit l'offset cablato sui pin di B8.
// ============================================================
localparam [7:0] WRITE_BIAS = 8'd32;

wire [3:0] sum_lo;
wire       sum_lo_cout;
wire [3:0] sum_hi;

ttl_74ls283 u_b8_lo (
    .a    (xor_addr[3:0]),
    .b    (WRITE_BIAS[3:0]),
    .cin  (1'b0),
    .s    (sum_lo),
    .cout (sum_lo_cout)
);

ttl_74ls283 u_b8_hi (
    .a    (xor_addr[7:4]),
    .b    (WRITE_BIAS[7:4]),
    .cin  (sum_lo_cout),
    .s    (sum_hi),
    .cout ()
);

wire [7:0] write_addr = {sum_hi, sum_lo};

// ============================================================
// XHFF / NSM e buffer-select per ping-pong
//
// Sul PCB:
//   - XHFF è un FF che alterna metà sx/dx dello sprite ROM (sel di B11)
//     gestito upstream nello scanner — qui non lo usiamo direttamente
//     (in_pen_col già porta dst_col post-flipx)
//   - NSM è il segnale "scan attivo" generato dal NAND tree → entra in
//     PAL H7 pin 9 come selettore stato
//   - Il PCB toggla i banchi line buffer al cambio scanline (= start_scan)
// ============================================================
reg buf_sel;       // 0 = banco A scrive / banco B legge; 1 = swap
always @(posedge clk) begin
    if (~reset_n)         buf_sel <= 1'b0;
    else if (start_scan)  buf_sel <= ~buf_sel;
end

wire nsm = in_pen_valid;    // = "scan is writing now"

// ============================================================
// PAL H7 (CCP-1) — sprite line buffer sequencer
//
// Cablaggio input (ipotesi consolidata da pin_mapping.md):
//   i1..i4 = S0..S3 (sprite pen, da B11)
//   i5..i8 = V counter primati (qui sostituito con vcnt[3:0] come prossimità,
//            nota: il PCB usa V primati post-flip; scanner upstream è
//            MAME-style, l'effetto sui bit vcnt è equivalente per visible
//            area)
//   i9     = NSM = write_busy
//   i11    = strobe scrittura attiva (qui = ce_pix & nsm — gating clk pixel
//            durante write)
//   i13    = buf_sel (selettore A/B feedback)
//
// Output:
//   o12 = ER1 (read enable banco A)
//   o19 = ER2 (read enable banco B)
//   o17 = OW1 (write enable banco A)
//   o18 (NB: pin 18 NOT presente nelle eqn estratte come output —
//        il decode dice o15=LT2, o16=LT1; OW2 è probabilmente o17 con
//        i9 invertito. Per ora cablerò: OW1=o19 e OW2=o17 secondo le
//        equazioni che hanno entrambe `& /i11`)
//
// ATTENZIONE: l'interpretazione completa di H7 richiede crosscheck JEDEC
// → pin assignment fisico. Questa istanza usa il decode disponibile.
// ============================================================
wire pal_h7_o12, pal_h7_o14, pal_h7_o15, pal_h7_o16, pal_h7_o17, pal_h7_o19;

pal_h7 u_pal_h7 (
    .i1  (in_pen[0]),
    .i2  (in_pen[1]),
    .i3  (in_pen[2]),
    .i4  (in_pen[3]),
    .i5  (vcnt[0]),
    .i6  (vcnt[1]),
    .i7  (vcnt[2]),
    .i8  (vcnt[3]),
    .i9  (nsm),
    .i11 (~(ce_pix & nsm)),     // active-low strobe scrittura
    .i13 (buf_sel),
    .i14 (1'b0), .i15 (1'b0), .i16 (1'b0), .i17 (1'b0), .i18 (1'b0),
    .o12 (pal_h7_o12),
    .o14 (pal_h7_o14),
    .o15 (pal_h7_o15),
    .o16 (pal_h7_o16),
    .o17 (pal_h7_o17),
    .o19 (pal_h7_o19)
);

// Mappatura active-low → segnali PCB
wire er1_n = pal_h7_o12;     // read enable A active-low
wire er2_n = pal_h7_o19;     // read enable B active-low
wire ow1_n = pal_h7_o17;     // write enable A active-low
wire ow2_n = ~pal_h7_o17;    // PCB usa pin separati; qui derivato per inversione su buf_sel
wire lt1_n = pal_h7_o16;
wire lt2_n = pal_h7_o15;

// PAL H7 produce ER/OW per banco A; per banco B inverto su buf_sel:
// quando buf_sel=0 → write su A, read da B.
// Il PCB ha 6 output separati per i 2 banchi; le equazioni JEDEC che abbiamo
// suggeriscono questa simmetria via i13=feedback. Cablo deterministicamente:
wire we_A_n = buf_sel ? 1'b1 : ~(in_pen_valid & |in_pen);
wire we_B_n = buf_sel ? ~(in_pen_valid & |in_pen) : 1'b1;

// Suppress warning unused PAL H7 outputs
/* verilator lint_off UNUSED */
wire _h7_unused = &{er1_n, er2_n, ow1_n, ow2_n, lt1_n, lt2_n,
                    pal_h7_o14};
/* verilator lint_on UNUSED */

// ============================================================
// 6148 ×4 — Line buffer 2 banchi (A,B), ognuno {pen 4-bit, col 4-bit}
//
// Address bus: 8-bit comune (write_addr[7:0] in scrittura,
//              read_addr[7:0]  in lettura).
// Sul PCB i 6148 sono 1Kx4 ma usati come 256x4 (A8,A9 a GND).
//
// FPGA: i 6148 PCB sono async single-port. Per supportare write+read
// simultanei nello stesso clock (write da scanner, read da renderer)
// servono 2 read port. Workaround: array reg + always block (LUTRAM).
// Indirizzamento e write enable rimangono PCB-fedeli.
// ============================================================

reg [3:0] lb_a_pen [0:255];
reg [3:0] lb_a_col [0:255];
reg [3:0] lb_b_pen [0:255];
reg [3:0] lb_b_col [0:255];

// Write
always @(posedge clk) begin
    if (~we_A_n) begin
        lb_a_pen[write_addr] <= in_pen;
        lb_a_col[write_addr] <= col_bank_q;
    end
    if (~we_B_n) begin
        lb_b_pen[write_addr] <= in_pen;
        lb_b_col[write_addr] <= col_bank_q;
    end
end

// Clear all'inizio scanline (replica clear_busy del legacy)
reg [7:0] clr_cnt;
reg       clr_busy;
always @(posedge clk) begin
    if (~reset_n) begin
        clr_cnt  <= 8'd0;
        clr_busy <= 1'b0;
    end else if (start_scan) begin
        clr_cnt  <= 8'd0;
        clr_busy <= 1'b1;
    end else if (clr_busy) begin
        clr_cnt <= clr_cnt + 8'd1;
        if (clr_cnt == 8'hFF) clr_busy <= 1'b0;
    end
end
always @(posedge clk) begin
    if (clr_busy) begin
        if (~buf_sel) begin
            lb_a_pen[clr_cnt] <= 4'd0;
            lb_a_col[clr_cnt] <= 4'd0;
        end else begin
            lb_b_pen[clr_cnt] <= 4'd0;
            lb_b_col[clr_cnt] <= 4'd0;
        end
    end
end

// ============================================================
// Read address: come legacy → screen_x + SPR_LB_ORIGIN_RD(32)
// con screen_x = hcnt - 24  →  read_addr = hcnt + 8 (mod 256)
// ============================================================
wire [9:0] read_addr_full = hcnt + 10'd8;
wire [7:0] read_addr      = read_addr_full[7:0];

// ============================================================
// A6 + D6 LS273 — latch output 6148 (un latch per banco)
// Sul PCB sono "registered" su LT1/LT2 di PAL H7. Qui registriamo al clock
// principale (effetto equivalente per la pipeline pixel).
// ============================================================
reg [3:0] a6_pen, a6_col;     // banco A latched
reg [3:0] d6_pen, d6_col;     // banco B latched

always @(posedge clk) begin
    a6_pen <= lb_a_pen[read_addr];
    a6_col <= lb_a_col[read_addr];
    d6_pen <= lb_b_pen[read_addr];
    d6_col <= lb_b_col[read_addr];
end

// ============================================================
// E6 + B6 LS157 — mux finale ping-pong
// SEL = ~buf_sel (legge dal banco opposto a quello che si sta scrivendo)
// ============================================================
wire [3:0] mux_pen, mux_col;

ttl_74ls157 u_e6 (
    .g_n (1'b0),
    .sel (buf_sel),
    .a   (d6_pen),
    .b   (a6_pen),
    .y   (mux_pen)
);

ttl_74ls157 u_b6 (
    .g_n (1'b0),
    .sel (buf_sel),
    .a   (d6_col),
    .b   (a6_col),
    .y   (mux_col)
);

assign spr_pen_out = mux_pen;
assign spr_pal_out = mux_col;
assign spr_opaque  = |mux_pen;

/* verilator lint_off UNUSED */
wire _unused = &{1'b0, ce_pix, vcnt, flip_screen, sx_counter,
                 sum_lo_cout};
/* verilator lint_on UNUSED */

endmodule
