// ============================================================
// 74LS161 — Synchronous 4-bit binary counter with parallel load
// 16-pin DIP. Edge-triggered su clk rising.
//
// Pinout: P (P0..P3 parallel inputs), Q (Q0..Q3 outputs), CLK, /CLR (sync),
// /LOAD, ENT (enable T), ENP (enable P), RCO (ripple carry out).
//
// Funzionamento:
// - Su edge di CLK:
//   - Se /CLR=0 → Q=0 (sync clear, priorità massima)
//   - Else if /LOAD=0 → Q=P (sync load)
//   - Else if ENT & ENP → Q=Q+1 (count)
//   - Else → Q invariato (hold)
// - RCO = Q3 & Q2 & Q1 & Q0 & ENT (= 1 quando Q==15 e ENT=1)
//
// Uso tipico cascadati: ENT del primo ← 1, ENP del primo ← 1.
// ENT/ENP del secondo ← RCO del primo.
// ============================================================

module ttl_74ls161 (
    input  wire       clk,
    input  wire       clr_n,    // sync clear active-low
    input  wire       load_n,   // sync load active-low
    input  wire       enp,      // enable P
    input  wire       ent,      // enable T
    input  wire [3:0] p,        // parallel data
    output reg  [3:0] q,
    output wire       rco       // ripple carry out
);

always @(posedge clk) begin
    if (~clr_n)         q <= 4'd0;
    else if (~load_n)   q <= p;
    else if (enp & ent) q <= q + 4'd1;
end

assign rco = (q == 4'd15) & ent;

endmodule
