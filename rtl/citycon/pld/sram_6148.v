// ============================================================
// 6148 — Static RAM 1024 word × 4 bit (asincrona)
// 18-pin DIP, 10 address (A0..A9), 4 data I/O bidirezionali, /CE, /WE
// Sul PCB City Connection: 3 chip cascadati come "OBJ output RAM" (sprite
// line buffer 256 px × 12 bit, tipicamente: 4 bit pen + 4 bit color +
// 4 bit attr/priority).
//
// Caratteristica chiave del 6148:
// - **Asincrona**: read è puramente combinatorio (no clock, no latency)
// - **Single-port**: 1 sola interfaccia indirizzo/dato per ciclo
//
// Implementazione FPGA: per replicare il comportamento ASYNC il read
// richiede distributed RAM (LUT-based, no clock) → ramstyle MLAB su Altera.
// Per BRAM (M9K) registered, c'è 1 ck di latency che non c'è sull'HW.
// ============================================================

module sram_6148 #(
    parameter SIZE = 1024     // tipicamente 1024×4
)(
    input  wire        clk,        // serve solo per write
    input  wire  [9:0] addr,
    input  wire        we_n,       // write enable active-low
    input  wire        ce_n,       // chip enable active-low
    input  wire  [3:0] din,
    output wire  [3:0] dout
);

(* ramstyle = "MLAB,no_rw_check" *) reg [3:0] mem [0:SIZE-1];

// Write sincrono al edge di clk (modellando setup/hold)
always @(posedge clk) begin
    if (~ce_n & ~we_n) mem[addr] <= din;
end

// Read combinatorio (asincrono come HW reale)
assign dout = ce_n ? 4'hF : mem[addr];

endmodule
