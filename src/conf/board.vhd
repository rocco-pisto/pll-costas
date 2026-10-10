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
    --! MSB index of a clock period [s] as ufixed(T_CLK_L downto ...): 2**-24 s
    --! holds periods up to ~119 ns, i.e. clocks from ~8.4 MHz. The LSB
    --! (precision) is chosen by each unit.
    constant T_CLK_L  : integer  := -24;
end package;
