library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @brief Board-level constants (clock frequencies).
--!
--! @note Plain numeric_std only: Quartus Prime Standard does not synthesize
--!       ieee.fixed_pkg.
package board is
    constant F_CLK    : unsigned(31 downto 0) := to_unsigned(50 * (10**6), 32);  --!< Board clock frequency (clk_0) [Hz].
    constant PLL_MULT : positive := 4;    --!< pll_200 output / input frequency ratio (200 MHz / 50 MHz).
    constant T_CLK_L  : integer  := -40;  --!< LSB weight of the clock period used by phase.vhd is 2**T_CLK_L s.
end package;
