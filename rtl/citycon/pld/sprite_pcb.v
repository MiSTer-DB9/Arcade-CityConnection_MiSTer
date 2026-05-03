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
// sprite_pcb v5 — Sprite stage PCB-fedele City Connection
//
// CORREZIONE ARCHITETTURALE chiave: counter B7+B10 è SINGLE
// dual-purpose. Genera l'address SIA per write (HBLANK) SIA per read
// (visible) sul SOLO bus dei 6148 6148 single-port.
// Tutti gli XOR (A9 NSM, XHFF/SL) si applicano sullo stesso address per
// entrambe le fasi → write/read si ricompongono coerenti.
//
// FASE WRITE (HBLANK):
//   - FSM scanner sequenzia lettura OBJ RAM, ROM fetch, draw 4+4 pixel
//   - LOAD pulse XHFF/SL ricarica counter con sx+32 a inizio metà L/R
//   - COUNT durante 4 ck DRAW_L e 4 ck DRAW_R
//   - PAL H7 OW1/OW2 attivi → write nel line buffer
//
// FASE READ (visible):
//   - FSM in IDLE
//   - Counter free-running su ce_pix da 0 a 255 (sincronizzato a hcnt)
//   - Address read = stesso xor_addr (Q ⊕ {NSM, 0, 0, XHFF})
//   - PAL H7 OW1/OW2 inattivi → letture
//
// PING-PONG SCANLINE:
//   V1 (vcnt[0]) alterna i banchi → write banco corrente, read banco old.
// ============================================================

module sprite_pcb (
    input  wire        clk,
    input  wire        ce_pix,
    input  wire        reset_n,
    input  wire        flip_screen,

    input  wire  [9:0] hcnt,
    input  wire  [8:0] vcnt,
    input  wire        start_scan,

    output reg   [7:0] obj_addr,
    input  wire  [7:0] obj_q,

    output wire [13:0] rom_addr,
    input  wire  [7:0] rom_q,

    output wire  [3:0] spr_pen_out,   // OBJ0..OBJ3
    output wire  [3:0] spr_pal_out,   // OBJ4..OBJ7
    output wire        spr_opaque
);

// ============================================================
// V counter primati VF4..VF7
// ============================================================
wire [3:0] vf_primati = vcnt[7:4] ^ {4{flip_screen}};
wire       v1_signal  = vcnt[0];           // V1 ping-pong scanline

// ============================================================
// yscan_next
// ============================================================
// yscan_next = scanline che il line buffer dovrà servire al RENDER successivo.
// Con ping-pong V1: scanline N (V1=0) scrivo banco A i pixel della scanline N
// stessa, leggo banco B (= scanline N-1 popolata in V1=1). Per allineare,
// scrivo i pixel della scanline N che leggerò dal banco B alla scanline N+1.
// Cioè durante scanline N popolo banco A per render della scanline N+1.
//
// yscan_next = vcnt (scrivo sprite a y match con scanline N → letto a N+1
// dopo il toggle banco V1)
reg [7:0] yscan_next;
always @(posedge clk) begin
    if (~reset_n)        yscan_next <= 8'd0;
    else if (start_scan) yscan_next <= vcnt[7:0];
end

// ============================================================
// FSM scanner pagina 11
// ============================================================
localparam SCN_IDLE       = 5'd0,
           SCN_SET_SY     = 5'd1,  SCN_W_SY     = 5'd2,  SCN_L_SY    = 5'd3,
           SCN_SET_A1     = 5'd4,  SCN_W_A1     = 5'd5,  SCN_L_A1    = 5'd6,
           SCN_SET_A2     = 5'd7,  SCN_W_A2     = 5'd8,  SCN_L_A2    = 5'd9,
           SCN_SET_SX     = 5'd10, SCN_W_SX     = 5'd11, SCN_L_SX    = 5'd12,
           SCN_LOAD_L     = 5'd13,
           SCN_FETCH_L01  = 5'd14, SCN_W_L01    = 5'd15, SCN_L_L01   = 5'd16,
           SCN_FETCH_L23  = 5'd17, SCN_W_L23    = 5'd18, SCN_L_L23   = 5'd19,
           SCN_DRAW_L     = 5'd20,
           SCN_LOAD_R     = 5'd21,
           SCN_FETCH_R01  = 5'd22, SCN_W_R01    = 5'd23, SCN_L_R01   = 5'd24,
           SCN_FETCH_R23  = 5'd25, SCN_W_R23    = 5'd26, SCN_L_R23   = 5'd27,
           SCN_DRAW_R     = 5'd28,
           SCN_NEXT       = 5'd29;

reg [4:0] scn_state;
reg [5:0] slot_idx;
reg [1:0] byte_idx;
reg [2:0] draw_col;

reg [7:0] reg_sy_raw;
reg [7:0] reg_attr1;
reg [7:0] reg_attr2;
reg [7:0] reg_ob;

// HREV sul PCB = attr2[4] raw (NON invertito come nel MAME-style flipx).
// MAME: flipx = ~attr2[4]; PCB: HREV = attr2[4]. Convenzioni opposte.
// Il NAND A3 produce NSM = NAND(match, HREV), quindi:
//   attr2[4]=1 (sprite "naturale" MAME) → HREV=1 → NSM=0 in match → A0=Q0 (lineare)
//   attr2[4]=0 (sprite flipx MAME) → HREV=0 → NSM=1 in match → A0=~Q0 (flip)
wire        hrev_eff = flip_screen ? ~reg_attr2[4] : reg_attr2[4];
wire [3:0]  col_bnk  = reg_attr2[3:0];

wire signed [8:0] sy_eff = flip_screen ? ($signed({1'b0, reg_sy_raw}) - 9'sd1)
                                       : ($signed({1'b0, 8'd239})    - $signed({1'b0, reg_sy_raw}));
wire        y_match    = ($signed({1'b0, yscan_next}) >= sy_eff) &&
                         ($signed({1'b0, yscan_next}) <  (sy_eff + 9'sd16));
wire [3:0]  row_sub_raw = $signed({1'b0, yscan_next}) - sy_eff;
wire [3:0]  row_sub    = flip_screen ? (4'd15 - row_sub_raw) : row_sub_raw;

reg [7:0] reg_pix01_L, reg_pix23_L;
reg [7:0] reg_pix01_R, reg_pix23_R;

reg scn_clear_busy;
reg [7:0] clear_cnt;

always @(posedge clk) begin
    if (~reset_n) begin
        scn_state      <= SCN_IDLE;
        slot_idx       <= 6'd0;
        byte_idx       <= 2'd0;
        draw_col       <= 3'd0;
        reg_sy_raw     <= 8'd0;
        reg_attr1      <= 8'd0;
        reg_attr2      <= 8'd0;
        reg_ob         <= 8'd0;
        reg_pix01_L    <= 8'd0;
        reg_pix23_L    <= 8'd0;
        reg_pix01_R    <= 8'd0;
        reg_pix23_R    <= 8'd0;
        scn_clear_busy <= 1'b0;
        clear_cnt      <= 8'd0;
    end else begin
        if (start_scan) begin
            scn_clear_busy <= 1'b1;
            clear_cnt      <= 8'd0;
        end else if (scn_clear_busy) begin
            clear_cnt <= clear_cnt + 8'd1;
            if (clear_cnt == 8'hFF) scn_clear_busy <= 1'b0;
        end

        if (start_scan) begin
            scn_state <= SCN_IDLE;
            slot_idx  <= 6'd63;
            byte_idx  <= 2'd0;
        end else if (~scn_clear_busy) begin
            case (scn_state)
                SCN_IDLE:    scn_state <= SCN_SET_SY;

                SCN_SET_SY:  begin byte_idx <= 2'd0; scn_state <= SCN_W_SY; end
                SCN_W_SY:    scn_state <= SCN_L_SY;
                SCN_L_SY: begin reg_sy_raw <= obj_q; scn_state <= SCN_SET_A1; end

                SCN_SET_A1:  begin byte_idx <= 2'd1; scn_state <= SCN_W_A1; end
                SCN_W_A1:    scn_state <= SCN_L_A1;
                SCN_L_A1: begin reg_attr1 <= obj_q; scn_state <= SCN_SET_A2; end

                SCN_SET_A2:  begin byte_idx <= 2'd2; scn_state <= SCN_W_A2; end
                SCN_W_A2:    scn_state <= SCN_L_A2;
                SCN_L_A2: begin reg_attr2 <= obj_q; scn_state <= SCN_SET_SX; end

                SCN_SET_SX:  begin byte_idx <= 2'd3; scn_state <= SCN_W_SX; end
                SCN_W_SX:    scn_state <= SCN_L_SX;
                SCN_L_SX: begin reg_ob <= obj_q;
                    scn_state <= y_match ? SCN_LOAD_L : SCN_NEXT;
                end

                SCN_LOAD_L:      scn_state <= SCN_FETCH_L01;
                SCN_FETCH_L01:   scn_state <= SCN_W_L01;
                SCN_W_L01:       scn_state <= SCN_L_L01;
                SCN_L_L01: begin reg_pix01_L <= rom_q; scn_state <= SCN_FETCH_L23; end
                SCN_FETCH_L23:   scn_state <= SCN_W_L23;
                SCN_W_L23:       scn_state <= SCN_L_L23;
                SCN_L_L23: begin
                    reg_pix23_L <= rom_q;
                    draw_col    <= 3'd0;
                    scn_state   <= SCN_DRAW_L;
                end
                SCN_DRAW_L: begin
                    if (draw_col == 3'd3) scn_state <= SCN_LOAD_R;
                    draw_col <= draw_col + 3'd1;
                end

                SCN_LOAD_R:      scn_state <= SCN_FETCH_R01;
                SCN_FETCH_R01:   scn_state <= SCN_W_R01;
                SCN_W_R01:       scn_state <= SCN_L_R01;
                SCN_L_R01: begin reg_pix01_R <= rom_q; scn_state <= SCN_FETCH_R23; end
                SCN_FETCH_R23:   scn_state <= SCN_W_R23;
                SCN_W_R23:       scn_state <= SCN_L_R23;
                SCN_L_R23: begin
                    reg_pix23_R <= rom_q;
                    draw_col    <= 3'd0;
                    scn_state   <= SCN_DRAW_R;
                end
                SCN_DRAW_R: begin
                    if (draw_col == 3'd3) scn_state <= SCN_NEXT;
                    draw_col <= draw_col + 3'd1;
                end

                SCN_NEXT: begin
                    if (slot_idx == 6'd0) scn_state <= SCN_IDLE;
                    else begin
                        slot_idx  <= slot_idx - 6'd1;
                        scn_state <= SCN_SET_SY;
                    end
                end

                default: scn_state <= SCN_IDLE;
            endcase
        end
    end
end

always @(*) obj_addr = {slot_idx, byte_idx};

// ============================================================
// Sprite ROM address bus (B13 stub)
// ============================================================
wire rom_plane_high = (scn_state == SCN_FETCH_L23) || (scn_state == SCN_W_L23) ||
                      (scn_state == SCN_FETCH_R23) || (scn_state == SCN_W_R23);
wire rom_half       = (scn_state == SCN_FETCH_R01) || (scn_state == SCN_W_R01) ||
                      (scn_state == SCN_FETCH_R23) || (scn_state == SCN_W_R23);

assign rom_addr = {rom_plane_high, reg_attr1[7], rom_half, reg_attr1[6:0], row_sub};

// ============================================================
// Segnali di controllo
// ============================================================
wire draw_active     = (scn_state == SCN_DRAW_L) || (scn_state == SCN_DRAW_R);
wire is_R_phase      = (scn_state == SCN_DRAW_R);
wire load_pulse      = (scn_state == SCN_LOAD_L) || (scn_state == SCN_LOAD_R);
wire scan_active     = (scn_state != SCN_IDLE);   // = scan in corso (HBLANK)

// HBLANK detect: scan_clear_busy + scan_active = "fase write"
wire in_hblank_phase = scn_clear_busy | scan_active;

// XHFF/SL = LOAD pulse SOLO a inizio sprite (LOAD_L).
// LOAD_R non ricarica: il counter continua dal valore raggiunto dopo
// DRAW_L (= sx+4) producendo i pixel R a sx+4..sx+7 sequenziali.
// SEMPLIFICAZIONE FPGA: il PCB usa pulse periodico ogni 8 ck con LS166
// shift register, ma FSM-MAME-style serializza in 2 metà 4-pixel ognuna.
wire xhff_sl = (scn_state == SCN_LOAD_L);

// NSM = NAND(V1, 8A3_signal) — pin 5 = V1, pin 4 = timing slot 8A3 (TBD).
// CONFERMATO 2026-04-29: NSM NON contiene HREV. Il flip H avviene via LS166
// bit-reverse + B11 sel (pen extraction LSB-first, vedi sotto).
// Senza conferma del segnale 8A3, cablo NSM=0 per non toggle bit 0 durante
// draw write. Sintomo se sbagliato: scramble pari/dispari nello sprite.
wire scan_match_active = draw_active & y_match;
wire nsm = 1'b0;     // TODO: cablare a NAND(V1, 8A3) quando confermato

// ============================================================
// LS166 ×4 (modellato come MSB-first byte ROM extraction)
// ============================================================
// L↔R swap quando HREV=0 (mirror): D11/E11 LS166 caricano byte L vs R in
// fasi temporalmente sfasate; B11 sceglie quale usa il line buffer.
// Effetto: per mirror, i primi 4 pixel del rendering vengono dal byte R.
wire        is_R_phase_eff = hrev_eff ? is_R_phase : ~is_R_phase;
wire [7:0]  pix01_cur  = is_R_phase_eff ? reg_pix01_R : reg_pix01_L;
wire [7:0]  pix23_cur  = is_R_phase_eff ? reg_pix23_R : reg_pix23_L;

// Pen extraction MSB-first sempre (= il flip avviene via address NSM).
// LS166 produce output serial MSB-first del parallel input → pix_b = 3 - col
// sempre. Il flip H avviene via L↔R swap di pix01/pix23 (vedi is_R_phase_eff).
wire [1:0]  pix_b      = 2'd3 - draw_col[1:0];
wire        s0 = pix01_cur[{1'b0, pix_b}];
wire        s1 = pix01_cur[{1'b1, pix_b}];
wire        s2 = pix23_cur[{1'b0, pix_b}];
wire        s3 = pix23_cur[{1'b1, pix_b}];
wire [3:0]  pen_S = {s0, s1, s2, s3};

// PCB (crop pagina 12): pin P0..P3 di B7 cablati direttamente a OB0..OB3,
// pin P0..P3 di B10 a OB4..OB7. Niente E9 LS283 in mezzo (E9 era mio
// errore di lettura — il vero E9 LS283 ×2 è in pagina 11 ed è l'adder
// V offset di un altro path).

// ============================================================
// B7 + B10 LS161 — counter SINGLE dual-purpose:
//   FASE WRITE (HBLANK):
//     LOAD pulse = xhff_sl → ricarica con sx+32 al cambio metà
//     COUNT = draw_active → 4+4 ck increment durante DRAW_L/R
//   FASE READ (visible):
//     LOAD inattivo
//     COUNT = ce_pix → conta libero da 0 a 255
//     A inizio scanline (start_scan) il counter è stato resettato implicito
//     dall'ultima fase HBLANK (counter è dove era a fine HBLANK; non serve
//     reset esplicito perché sx counter ha pre-loaded l'offset corrente)
//
// In realtà sul PCB il counter parte naturalmente dal punto in cui era
// alla fine del frame precedente; durante visible il read inizia da 0
// perché il line buffer è clear-prima e poi gli sprite scrivono in
// posizioni ≥32. Per coerenza, modello il counter come: count su ce_pix
// SEMPRE (incluso visible), con LOAD durante xhff_sl pulse. Reset su
// start_scan riporta a 0 per inizio visible della scanline corrente.
// ============================================================
wire counter_count_en = draw_active;                 // count solo durante draw (4 ck DRAW_L + 4 ck DRAW_R)
wire counter_load_n   = ~xhff_sl;

wire counter_clr_n = reset_n;

wire [3:0] q_lo, q_hi;
wire       rco_lo;

ttl_74ls161 u_b7 (
    .clk    (clk),
    .clr_n  (counter_clr_n),
    .load_n (counter_load_n),
    .enp    (counter_count_en),
    .ent    (counter_count_en),
    .p      (reg_ob[3:0]),               // OB0..OB3 (E8/E7 latch) diretti
    .q      (q_lo),
    .rco    (rco_lo)
);

ttl_74ls161 u_b10 (
    .clk    (clk),
    .clr_n  (counter_clr_n),
    .load_n (counter_load_n),
    .enp    (counter_count_en),
    .ent    (counter_count_en & rco_lo),
    .p      (reg_ob[7:4]),               // OB4..OB7
    .q      (q_hi),
    .rco    ()
);

// ============================================================
// A9 LS86 — XOR address (write E read shared)
//   A0 = Q0 ⊕ NSM    (NSM contiene HREV per il flip)
//   A1 = Q1 ⊕ 0
//   A2 = Q2 ⊕ 0
//   A3 = Q3 ⊕ XHFF/SL
// ============================================================
wire [3:0] xor_lo;

// A9 LS86 cablaggio confermato dal pin_mapping (pagina 12):
//   A0 = Q0 ⊕ NSM    (gate 1)
//   A1 = Q1 ⊕ 0      (gate 2, pin GND)
//   A2 = Q2 ⊕ 0      (gate 3, pin GND)
//   A3 = Q3 ⊕ XHFF/SL (gate 4)
ttl_74ls86 u_a9 (
    .a (q_lo),
    .b ({xhff_sl, 1'b0, 1'b0, nsm}),
    .y (xor_lo)
);

// A10 LS86 — bit alti passthrough (TBD)
wire [3:0] xor_hi;

ttl_74ls86 u_a10 (
    .a (q_hi),
    .b (4'd0),
    .y (xor_hi)
);

wire [7:0] addr_bus = {xor_hi, xor_lo};

// ============================================================
// PAL H7 — istanziato con cablaggio CONFERMATO pagina 12
// ============================================================
wire pal_h7_o12, pal_h7_o14, pal_h7_o15, pal_h7_o16, pal_h7_o17, pal_h7_o19;

// i13 = LT1 retroazionato — sul PCB è bidir del PAL stesso. Per evitare
// loop combinatorio, lo modelliamo come reg latched ck-delayed.
reg pal_h7_i13_r;
always @(posedge clk) pal_h7_i13_r <= pal_h7_o16;

pal_h7 u_pal_h7 (
    .i1  (vf_primati[0]),
    .i2  (vf_primati[1]),
    .i3  (vf_primati[2]),
    .i4  (vf_primati[3]),
    .i5  (pen_S[0]),
    .i6  (pen_S[1]),
    .i7  (pen_S[2]),
    .i8  (pen_S[3]),
    .i9  (v1_signal),
    .i11 (~(ce_pix & draw_active)),
    .i13 (pal_h7_i13_r),
    .i14 (1'b0), .i15 (1'b0), .i16 (1'b0), .i17 (1'b0), .i18 (1'b0),
    .o12 (pal_h7_o12),
    .o14 (pal_h7_o14),
    .o15 (pal_h7_o15),
    .o16 (pal_h7_o16),
    .o17 (pal_h7_o17),
    .o19 (pal_h7_o19)
);

wire col0p = pal_h7_o14;
wire col1p = 1'b0;

/* verilator lint_off UNUSED */
wire _h7_unused = &{pal_h7_o15, pal_h7_o16, pal_h7_o17};
/* verilator lint_on UNUSED */

// ============================================================
// LINE BUFFER 6148 — banchi A/B controllati da V1 (ping-pong scanline)
//
// Sul PCB i 6148 sono single-port async; write+read condividono lo
// stesso bus address. Su FPGA duplichiamo come 2 banchi LUTRAM:
//   V1=0 → fase scrittura su banco A; lettura da banco B (= scanline -1)
//   V1=1 → fase scrittura su banco B; lettura da banco A
// addr_bus è lo stesso per write e read (counter dual-purpose).
// ============================================================
reg [3:0] lb_a_pen [0:255];
reg [3:0] lb_a_col [0:255];
reg [3:0] lb_b_pen [0:255];
reg [3:0] lb_b_col [0:255];

// Write enable: solo durante draw_active (HBLANK fase write) e |pen_S
// (= no transparent write per sprite priority OR), dipende da V1
wire we_A = ~v1_signal & draw_active & |pen_S;
wire we_B =  v1_signal & draw_active & |pen_S;

always @(posedge clk) begin
    if (we_A) begin
        lb_a_pen[addr_bus] <= pen_S;
        lb_a_col[addr_bus] <= col_bnk;
    end
    if (we_B) begin
        lb_b_pen[addr_bus] <= pen_S;
        lb_b_col[addr_bus] <= col_bnk;
    end
end

// Clear scanline (banco di scrittura corrente)
always @(posedge clk) begin
    if (scn_clear_busy) begin
        if (~v1_signal) begin
            lb_a_pen[clear_cnt] <= 4'd0;
            lb_a_col[clear_cnt] <= 4'd0;
        end else begin
            lb_b_pen[clear_cnt] <= 4'd0;
            lb_b_col[clear_cnt] <= 4'd0;
        end
    end
end

// ============================================================
// READ — durante visible il line buffer è letto da hcnt-based addr.
// Sul PCB (TBD definitivo del read path) il counter B7+B10 è dual-purpose
// e legge da Q durante visible. Su FPGA con il modello FSM-MAME-style del
// scanner, il counter scrive solo durante draw_active e fermerebbe a fine
// HBLANK, quindi serve un read addr basato su hcnt come nel legacy.
// read_addr = screen_x = hcnt - 24 (mod 256)
// Niente +32: lo write_addr non ha offset (E9 LS283 rimosso, B7+B10 LOAD =
// OB diretto). Quindi read e write usano stesso slot.
wire [9:0] read_addr_full = hcnt - 10'd24;
wire [7:0] read_addr      = read_addr_full[7:0];

reg [3:0] a6_pen, a6_col;
reg [3:0] d6_pen, d6_col;

always @(posedge clk) begin
    a6_pen <= lb_a_pen[read_addr];
    a6_col <= lb_a_col[read_addr];
    d6_pen <= lb_b_pen[read_addr];
    d6_col <= lb_b_col[read_addr];
end

// ============================================================
// E6 + B6 LS157 — mux finale ping-pong scanline
// PCB (pin_mapping confermato pag.12 riga 1714-1715):
//   E6 sel = ER1 (PAL H7 pin 12)  → alterna banco pen ping/pong
//   B6 sel = ER2 (PAL H7 pin 19)  → alterna banco col ping/pong
// ============================================================
wire [3:0] mux_pen, mux_col;

// Sel = ~V1 (lettura dal banco opposto a quello in scrittura)
// Sul PCB il mux usa ER1/ER2 di PAL H7, ma le equazioni JEDEC non
// producono il pattern naive con il cablaggio attuale → uso ~V1 diretto.
ttl_74ls157 u_e6 (
    .g_n (1'b0),
    .sel (~v1_signal),
    .a   (a6_pen),
    .b   (d6_pen),
    .y   (mux_pen)
);

ttl_74ls157 u_b6 (
    .g_n (1'b0),
    .sel (~v1_signal),
    .a   (a6_col),
    .b   (d6_col),
    .y   (mux_col)
);

// ============================================================
// A7 LS283 — color combiner
// ============================================================
wire [3:0] color_b_input = {2'b00, col1p, col0p};
wire [3:0] color_sum;

ttl_74ls283 u_a7 (
    .a    (mux_col),
    .b    (color_b_input),
    .cin  (1'b0),
    .s    (color_sum),
    .cout ()
);

assign spr_pen_out = mux_pen;
assign spr_pal_out = color_sum;
assign spr_opaque  = |mux_pen;

/* verilator lint_off UNUSED */
wire _unused = &{1'b0, vcnt[3:1], hrev_eff};
/* verilator lint_on UNUSED */

endmodule
