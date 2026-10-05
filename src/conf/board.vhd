library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

--! @brief Board-level constants (clock frequency and period).
--!
--! @note Plain numeric_std/math_real only: Quartus Prime Standard does not
--!       synthesize ieee.fixed_pkg.
package board is
    constant F_CLK   : unsigned(31 downto 0) := to_unsigned(50 * (10**6), 32);  --!< System clock frequency [Hz].
    constant T_CLK_L : integer := -40;  --!< LSB weight of T_CLK is 2**T_CLK_L s.
    --! System clock period [s], rounded to 2**T_CLK_L (UQ-24.40, max ~59.6 ns).
    --! Stored as raw unsigned: T_CLK [s] = T_CLK * 2**T_CLK_L.
    constant T_CLK   : unsigned(16 downto 0) :=
        to_unsigned(natural(round(2.0**(-T_CLK_L) / real(to_integer(F_CLK)))), 17);
end package;
