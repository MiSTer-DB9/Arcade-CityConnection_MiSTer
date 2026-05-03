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
// PAL H7 (CCP-1) — sprite line buffer sequencer (City Connection)
// Decompilazione JEDEC via jedutil → reference/pld_decoded/pal_h7_eqn.txt
//
// Architettura: PAL16L8A combinatorio puro (nessun registro interno).
// 10 input dedicati (pin 1-9, 11), 8 output (pin 12-19), tutti active-low.
// Output 12 e 19 sono puri output; 13-18 sono bidirezionali.
//
// NB: i nomi dei pin PCB (e delle equazioni in i1..i18 / o12..o19) sono
// quelli del JEDEC dump. Il cablaggio PCB → segnali deve essere fatto a
// monte (citycon_top.sv quando istanzia questo modulo).
//
// Equazioni originali (active-low output):
//   /o12 = /i9 +
//          i9 & i13
//   /o14 = /i9 & i13 +
//          i9
//   /o15 = /i9 & /i13
//   /o16 = i9 & /i13
//   /o17 = /i9 & /i11 +
//          i1 & i2 & i3 & i4 & i8 & i9 & /i11 +
//          i1 & i2 & i3 & i4 & i7 & i9 & /i11 +
//          i1 & i2 & i3 & i4 & i6 & i9 & /i11 +
//          i1 & i2 & i3 & i4 & i5 & i9 & /i11
//   /o19 = i1 & i2 & i3 & i4 & i8 & /i9 & /i11 +
//          i1 & i2 & i3 & i4 & i7 & /i9 & /i11 +
//          i1 & i2 & i3 & i4 & i6 & /i9 & /i11 +
//          i1 & i2 & i3 & i4 & i5 & /i9 & /i11 +
//          i9 & /i11
//
// NOTA: i13 e i18 sono pin BIDIREZIONALI usati come INPUT in queste
// equazioni. Sul PCB sono fed back da altri output del PAL stesso o da
// segnali esterni — verificare cablaggio prima di stabilire significato
// fisico.
// ============================================================

module pal_h7 (
    input  wire i1, i2, i3, i4, i5, i6, i7, i8, i9, i11,
    input  wire i13, i14, i15, i16, i17, i18,   // pin bidirezionali usati come input

    output wire o12,
    output wire o14,
    output wire o15,
    output wire o16,
    output wire o17,
    output wire o19
);

// Equazioni active-low (notazione: il PAL pin è HIGH quando l'equazione "/o = ..." è FALSE).
// Verilog: assign o = ~(equation_negata).

wire o12_n = (~i9)
           | (i9 & i13);
assign o12 = ~o12_n;

wire o14_n = (~i9 & i13)
           | i9;
assign o14 = ~o14_n;

wire o15_n = (~i9 & ~i13);
assign o15 = ~o15_n;

wire o16_n = (i9 & ~i13);
assign o16 = ~o16_n;

wire o17_n = (~i9 & ~i11)
           | (i1 & i2 & i3 & i4 & i8 & i9 & ~i11)
           | (i1 & i2 & i3 & i4 & i7 & i9 & ~i11)
           | (i1 & i2 & i3 & i4 & i6 & i9 & ~i11)
           | (i1 & i2 & i3 & i4 & i5 & i9 & ~i11);
assign o17 = ~o17_n;

wire o19_n = (i1 & i2 & i3 & i4 & i8 & ~i9 & ~i11)
           | (i1 & i2 & i3 & i4 & i7 & ~i9 & ~i11)
           | (i1 & i2 & i3 & i4 & i6 & ~i9 & ~i11)
           | (i1 & i2 & i3 & i4 & i5 & ~i9 & ~i11)
           | (i9 & ~i11);
assign o19 = ~o19_n;

// Suppressori unused (i14, i15, i16, i17, i18 non compaiono nelle equazioni
// di OUTPUT estratte — possono essere comunque cablati come INPUT ma non
// influenzano questi 6 output).
/* verilator lint_off UNUSED */
wire _unused_pal_h7 = &{1'b0, i14, i15, i16, i17, i18};
/* verilator lint_on UNUSED */

endmodule
