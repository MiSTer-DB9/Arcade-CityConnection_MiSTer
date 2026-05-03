derive_pll_clocks
derive_clock_uncertainty

# ============================================================
# City Connection multicycle paths
#
# clk_sys = 40 MHz (dalla PLL — MAME MASTER/2).
# Main CPU 6809 (mc6809i) opera a ce_E/ce_Q a 1.25 MHz — 1 impulso ogni 32 clk.
# Quindi tutte le path interne della CPU hanno 32 clk per chiudere (non 1).
# Setup multicycle = 32 → 32× periodo di clk_sys (= 32 × 25 ns = 800 ns).
# Hold multicycle  = 31 (always N-1 per CE-gated design).
# ============================================================
set_multicycle_path -setup -from [get_registers {*mc6809i*}] -to [get_registers {*mc6809i*}] 32
set_multicycle_path -hold  -from [get_registers {*mc6809i*}] -to [get_registers {*mc6809i*}] 31

# ============================================================
# Palette fetch loop: pal_byte_phase toggle ogni clk. Non CE-gated.
# Chiusura a 40 MHz (periodo 25 ns) — abbondante.
# ============================================================
