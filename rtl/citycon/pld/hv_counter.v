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
// hv_counter — Counter H/V 9-bit + flip XOR (City Connection PCB)
// Replica gate-level della pagina 7 dello schema:
//   - Counter H (3× LS161 cascadati per 9-bit completo, ma solo 2 effettivi
//     visto che HTOTAL=320 < 512)
//   - Counter V (3× LS161 cascadati, sempre 9-bit)
//   - LS86 XOR per flip orizzontale (E6 colonna superiore)
//   - LS86 XOR per flip verticale (E6 colonna inferiore)
//   - LS283 R10 per offset additivo dopo XOR (gestisce displacement
//     di flip per allineare l'origine bitmap)
//
// Numeri PCB confermati MAME/decompilazione:
//   HTOTAL=320, HBEND=8, HBSTART=248
//   VTOTAL=262, VBEND=16, VBSTART=240
//
// CLK input = pixel clock (5 MHz nominale, qui clk_sys 48 MHz con ce_pix).
// Per replicare PCB: il counter deve incrementare ad ogni edge ce_pix.
// ============================================================

module hv_counter (
    input  wire       clk,            // clk_sys (48 MHz)
    input  wire       ce_pix,         // pixel clock enable (= clk/8 = 5 MHz)
    input  wire       reset_n,
    input  wire       flip_h,         // NXMFF — flip orizzontale
    input  wire       flip_v,         // NYMFF — flip verticale

    // Counter raw (pre-flip) — pin H1..H256 e V1..V256 dello schema
    output wire [8:0] hcnt,           // H[8:0]
    output wire [8:0] vcnt,           // V[8:0]

    // Counter primati (post-XOR-flip) — pin H1'..H256' e V1'..V256'
    output wire [8:0] hcnt_p,         // H'[8:0]
    output wire [8:0] vcnt_p          // V'[8:0]
);

// ============================================================
// Counter H: 3× LS161 cascadati
// LS161 carry chain: ENT chained, ENP=1
// Wrap: HTOTAL=320 → quando hcnt==319 fa CLR sync al ck successivo
// (sul PCB il wrap è fatto dal PAL U7 via CLR_n; qui lo simuliamo
//  combinatoriamente per ora — TODO: spostare in pal_u7)
// ============================================================

wire [3:0] h_q0, h_q1, h_q2;
wire       h_rco0, h_rco1;
wire       h_clr_n_internal;

assign h_clr_n_internal = ~(hcnt == 9'd319) & reset_n;

ttl_74ls161 u_h0 (
    .clk     (clk),
    .clr_n   (h_clr_n_internal),
    .load_n  (1'b1),
    .enp     (ce_pix),
    .ent     (ce_pix),
    .p       (4'd0),
    .q       (h_q0),
    .rco     (h_rco0)
);

ttl_74ls161 u_h1 (
    .clk     (clk),
    .clr_n   (h_clr_n_internal),
    .load_n  (1'b1),
    .enp     (ce_pix),
    .ent     (h_rco0),
    .p       (4'd0),
    .q       (h_q1),
    .rco     (h_rco1)
);

ttl_74ls161 u_h2 (
    .clk     (clk),
    .clr_n   (h_clr_n_internal),
    .load_n  (1'b1),
    .enp     (ce_pix),
    .ent     (h_rco1),
    .p       (4'd0),
    .q       (h_q2),
    .rco     ()
);

assign hcnt = {h_q2[0], h_q1, h_q0};

// ============================================================
// Counter V: 3× LS161 cascadati, incrementa al wrap di H
// ============================================================

wire [3:0] v_q0, v_q1, v_q2;
wire       v_rco0, v_rco1;
wire       v_clr_n_internal;
wire       v_inc;

assign v_clr_n_internal = ~(vcnt == 9'd261) & reset_n;
assign v_inc = ce_pix & (hcnt == 9'd319);   // V incrementa quando H wrappa

ttl_74ls161 u_v0 (
    .clk     (clk),
    .clr_n   (v_clr_n_internal),
    .load_n  (1'b1),
    .enp     (v_inc),
    .ent     (v_inc),
    .p       (4'd0),
    .q       (v_q0),
    .rco     (v_rco0)
);

ttl_74ls161 u_v1 (
    .clk     (clk),
    .clr_n   (v_clr_n_internal),
    .load_n  (1'b1),
    .enp     (v_inc),
    .ent     (v_rco0),
    .p       (4'd0),
    .q       (v_q1),
    .rco     (v_rco1)
);

ttl_74ls161 u_v2 (
    .clk     (clk),
    .clr_n   (v_clr_n_internal),
    .load_n  (1'b1),
    .enp     (v_inc),
    .ent     (v_rco1),
    .p       (4'd0),
    .q       (v_q2),
    .rco     ()
);

assign vcnt = {v_q2[0], v_q1, v_q0};

// ============================================================
// Flip XOR (LS86 E6)
// H' = H XOR {flip_h replicato 9 volte}
// V' = V XOR {flip_v replicato 9 volte}
//
// NB: sul PCB c'è anche un LS283 (R10) che somma un offset al risultato
// XOR, gestendo il displacement di flip. Per ora: solo XOR, l'offset
// può essere aggiunto in un secondo step se necessario per allineare.
// ============================================================

assign hcnt_p = hcnt ^ {9{flip_h}};
assign vcnt_p = vcnt ^ {9{flip_v}};

endmodule
