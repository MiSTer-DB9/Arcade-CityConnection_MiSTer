// ============================================================
// 74LS86 — Quad XOR gate
// 14-pin DIP. Combinatorio puro.
// ============================================================

module ttl_74ls86 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [3:0] y
);

assign y = a ^ b;

endmodule
