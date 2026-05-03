// ============================================================
// 74LS157 — Quad 2-to-1 multiplexer con select e enable
// 16-pin DIP. Combinatorio puro.
//
// Funzionamento:
//   /G=1 → Y = 0 (output disabilitato)
//   /G=0:
//     SEL=0 → Y = A
//     SEL=1 → Y = B
// ============================================================

module ttl_74ls157 (
    input  wire       g_n,    // enable active-low
    input  wire       sel,    // select (0→A, 1→B)
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [3:0] y
);

assign y = g_n ? 4'd0 : (sel ? b : a);

endmodule
