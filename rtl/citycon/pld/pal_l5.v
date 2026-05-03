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
// PAL L5 — funzione non ancora identificata (City Connection)
// Decompilazione JEDEC via jedutil → reference/pld_decoded/pal_l5_eqn.txt
//
// Architettura: PAL16L8A combinatorio puro.
// 8 output (TUTTI), tutti active-low. Pattern molto regolare:
// le equazioni sono tutte 1-term AND di letterali su i1..i8, suggerendo
// che è un DECODER puro (es. address decode secondario o I/O decoder).
//
// Equazioni originali (active-low output):
//   /o12 = i1 & /i2 & i3 & /i4 & /i5 & /i6 & /i7 & /i8
//   /o13 = i1 & /i2 & i3 & /i4 & /i5 & /i8
//   /o14 = /i1 & /i2 & i3 & /i4 & /i5 & /i6 & /i7 & /i8
//   /o15 = /i1 & /i2 & i3 & /i4 & /i5 & /i8
//   /o16 = i2 & /i3 & /i4 & /i5 & /i6 & /i7 & /i8
//   /o17 = i2 & /i3 & /i4 & /i5 & i7 & /i8
//   /o18 = i2 & /i3 & /i4 & /i5 & /i8
//   /o19 = i1 & i2 & i3 & /i4 & /i5 & /i8
//
// OSSERVAZIONI:
// - Tutte le equazioni richiedono i4=0, i5=0, i8=0 → questi 3 sono pin di
//   ENABLE (active-low) globali per tutto il chip.
// - i1, i2, i3 selezionano quale output attivare → 8 combinazioni = 1 per
//   ognuno degli 8 output (decoder 3→8, simile a 74LS138).
// - i6, i7 introducono restrizioni aggiuntive su alcuni output.
// - Conclusione probabile: **LS138-like decoder con 3 enable + 3 select**.
//   Tipico utilizzo: secondary I/O decode (es. $3000-$3007 sub-decode), o
//   palette-RAM bank select.
// ============================================================

module pal_l5 (
    input  wire i1, i2, i3, i4, i5, i6, i7, i8, i9, i11,
    input  wire i13, i14, i15, i16, i17, i18,

    output wire o12,
    output wire o13,
    output wire o14,
    output wire o15,
    output wire o16,
    output wire o17,
    output wire o18,
    output wire o19
);

wire o12_n = i1 & ~i2 & i3 & ~i4 & ~i5 & ~i6 & ~i7 & ~i8;
assign o12 = ~o12_n;

wire o13_n = i1 & ~i2 & i3 & ~i4 & ~i5 & ~i8;
assign o13 = ~o13_n;

wire o14_n = ~i1 & ~i2 & i3 & ~i4 & ~i5 & ~i6 & ~i7 & ~i8;
assign o14 = ~o14_n;

wire o15_n = ~i1 & ~i2 & i3 & ~i4 & ~i5 & ~i8;
assign o15 = ~o15_n;

wire o16_n = i2 & ~i3 & ~i4 & ~i5 & ~i6 & ~i7 & ~i8;
assign o16 = ~o16_n;

wire o17_n = i2 & ~i3 & ~i4 & ~i5 & i7 & ~i8;
assign o17 = ~o17_n;

wire o18_n = i2 & ~i3 & ~i4 & ~i5 & ~i8;
assign o18 = ~o18_n;

wire o19_n = i1 & i2 & i3 & ~i4 & ~i5 & ~i8;
assign o19 = ~o19_n;

/* verilator lint_off UNUSED */
wire _unused_pal_l5 = &{1'b0, i9, i11, i13, i14, i15, i16, i17, i18};
/* verilator lint_on UNUSED */

endmodule
