// ============================================================
// 82S123 — Bipolar PROM 32 word × 8 bit (Signetics/TI/AMD)
// 16-pin DIP, 5 address (A0..A4), 8 output tri-state
// Sul PCB City Connection: N5 (address decoder CPU) e R4 (funzione ignota).
//
// Implementazione FPGA: BRAM/distributed inferred da reg array sync read,
// con preload da file hex (caricato a build via initial). In runtime la
// PROM è read-only.
//
// Differenza con PCB:
// - Real chip: ~50ns combinatorio asincrono (output = mem[addr] istantaneo)
// - FPGA: 1-clk registered output (per inferenza BRAM Quartus/Altera)
//   → consumer deve compensare 1 ck di latency
//
// Per uso "100% async-like": commentare il sync block e usare assign diretto
// (verrà inferito come distributed RAM/LUT se size piccolo).
// ============================================================

module prom_82s123 #(
    parameter SIMFILE = "",       // file hex per simulazione/synthesis
    parameter ASYNC   = 0          // 0 = registered (1ck), 1 = combinatoria pura
)(
    input  wire        clk,
    input  wire  [4:0] addr,
    input  wire        cs_n,       // chip select active-low
    output wire  [7:0] q
);

reg [7:0] mem [0:31];
reg [7:0] q_reg;

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
        assign q = cs_n ? 8'hFF : mem[addr];   // pull-up tri-state when /CS high
    end else begin : g_sync
        assign q = cs_n ? 8'hFF : q_reg;
    end
endgenerate

endmodule
