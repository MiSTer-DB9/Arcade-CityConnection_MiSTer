// ============================================================
// 82S129 — Bipolar PROM 256 word × 4 bit (Signetics/TI/AMD)
// 16-pin DIP, 8 address (A0..A7), 4 output tri-state
// Sul PCB City Connection: L6 (funzione ignota).
//
// Implementazione FPGA: simile a 82S123 ma 256×4.
// ============================================================

module prom_82s129 #(
    parameter SIMFILE = "",
    parameter ASYNC   = 0
)(
    input  wire        clk,
    input  wire  [7:0] addr,
    input  wire        cs_n,
    output wire  [3:0] q
);

reg [3:0] mem [0:255];
reg [3:0] q_reg;

initial begin
    if (SIMFILE != "") begin
        $readmemh(SIMFILE, mem);
    end
end

always @(posedge clk) begin
    q_reg <= mem[addr];
end

generate
    if (ASYNC) begin : g_async
        assign q = cs_n ? 4'hF : mem[addr];
    end else begin : g_sync
        assign q = cs_n ? 4'hF : q_reg;
    end
endgenerate

endmodule
