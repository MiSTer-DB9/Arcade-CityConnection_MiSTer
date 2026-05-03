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
// PAL U7 (CCP-2) — sync/timing generator (City Connection)
// Decompilazione JEDEC via jedutil → reference/pld_decoded/pal_u7_eqn.txt
//
// Architettura: PAL16L8A combinatorio puro.
// 4 output utilizzati: o12, o15, o16, o19 (gli altri 4 pin di output non
// sono programmati nel JEDEC dump → restano hi-Z o non utilizzati).
//
// Equazioni originali (active-low output):
//   /o12 = i8 & /i9 & /i11 & /i14 +
//          /i7 & /i8 & i9 & /i11 & /i14
//   /o15 = /i18 +
//          i2 & /i3 & /i6 +
//          i1 & /i3 & /i6
//   /o16 = /i1 & /i2 +
//          i6 +
//          i3
//   /o19 = /i6 +
//          i1 & i2 & i3 & i4 & i5 +
//          i17
//
// NOTA: i pin i1..i9 sono cablati a counter H/V primati (vedi schema PCB
// pagina 7 — H1', H2', H4', H8', H16', H32', V1', V2', V4', ...). I pin
// bidirezionali i13..i18 sono fed back o da altri segnali timing.
// Mapping definitivo richiede analisi schema dettagliata.
// ============================================================

module pal_u7 (
    input  wire i1, i2, i3, i4, i5, i6, i7, i8, i9, i11,
    input  wire i13, i14, i15, i16, i17, i18,

    output wire o12,
    output wire o15,
    output wire o16,
    output wire o19
);

wire o12_n = (i8 & ~i9 & ~i11 & ~i14)
           | (~i7 & ~i8 & i9 & ~i11 & ~i14);
assign o12 = ~o12_n;

wire o15_n = (~i18)
           | (i2 & ~i3 & ~i6)
           | (i1 & ~i3 & ~i6);
assign o15 = ~o15_n;

wire o16_n = (~i1 & ~i2)
           | i6
           | i3;
assign o16 = ~o16_n;

wire o19_n = (~i6)
           | (i1 & i2 & i3 & i4 & i5)
           | i17;
assign o19 = ~o19_n;

/* verilator lint_off UNUSED */
wire _unused_pal_u7 = &{1'b0, i13, i15, i16};
/* verilator lint_on UNUSED */

endmodule
