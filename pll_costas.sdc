create_clock -name clk_0 -period 20 [get_ports clk_0]
derive_pll_clocks
derive_clock_uncertainty

# Push-button and LEDs: asynchronous to the design, not timed
set_false_path -from [get_ports rst_n]
set_false_path -to   [get_ports led_*]

# Reset synchronizers: first flop samples asynchronous inputs (rst_pulse from
# clk_0, PLL locked) by design
set_false_path -to [get_registers {*synchronizer:*|chain[0][*]}]
