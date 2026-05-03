// ============================================================
// 74LS283 — 4-bit binary full adder con carry-in/out
// 16-pin DIP. Combinatorio puro.
//
// Funzionamento: Σ = A + B + Cin (5-bit result)
//   S[3:0] = Σ[3:0]
//   Cout   = Σ[4]
// ============================================================

module ttl_74ls283 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,
    output wire [3:0] s,
    output wire       cout
);

wire [4:0] sum = {1'b0, a} + {1'b0, b} + {4'b0, cin};
assign s    = sum[3:0];
assign cout = sum[4];

endmodule
