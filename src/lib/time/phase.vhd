library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.board.all;

--! @brief Phase accumulator (in cycles) for a given frequency.
--!
--! Every clock cycle accumulates freq_i * T_CLK, i.e. the phase advance in
--! cycles (turns) over one clock period, with T_CLK = 1 / (F_CLK * CLK_MULT).
--! The accumulator is UQ16.(-T_CLK_L) (raw unsigned, LSB weight 2**T_CLK_L
--! cycles) and wraps modulo 2**16 cycles. The outputs are its 16 integer bits
--! and the 16 MSBs of its fractional part (truncated).
--!
--! @generic CLK_MULT Ratio between clk and the board clock F_CLK (e.g.
--!                   PLL_MULT when clocked from pll_200).
--!
--! @port clk          Clock input, F_CLK * CLK_MULT.
--! @port rst_n        Synchronous active-low reset (clears the accumulator).
--! @port freq_i       Frequency [Hz] (SLV, UQ32.0).
--! @port phase_high_o Integer part of the phase [cycles] (SLV, UQ16.0).
--! @port phase_low_o  Fractional part of the phase [cycles] (SLV, UQ0.16),
--!                    wraps once per cycle of freq_i.
--!
--! @note freq_i is registered into d_phi: a change of freq_i affects the
--!       accumulator with one clock cycle of latency.
--! @note T_CLK is rounded to 2**T_CLK_L, so the phase drifts by
--!       freq_i * (T_CLK - 1/(F_CLK*CLK_MULT)) cycles per clock.
entity phase is
    generic (
        CLK_MULT : positive := 1 --!< clk frequency / F_CLK.
    );
    port (
        clk          : in  std_logic;                     --!< Clock.
        rst_n        : in  std_logic;                     --!< Synchronous active-low reset.
        freq_i       : in  std_logic_vector(31 downto 0); --!< Frequency [Hz], UQ32.0.
        phase_high_o : out std_logic_vector(15 downto 0); --!< Phase integer part [cycles], UQ16.0.
        phase_low_o  : out std_logic_vector(15 downto 0)  --!< Phase fractional part [cycles], UQ0.16.
    );
end entity;

architecture rtl of phase is

    constant W_FRAC : integer := -T_CLK_L; --!< Accumulator fractional bits.

    --! Clock period [s], rounded to 2**T_CLK_L (UQ-24.40, max ~59.6 ns).
    --! Raw unsigned: T_CLK [s] = T_CLK * 2**T_CLK_L.
    constant T_CLK : unsigned(16 downto 0) :=
        to_unsigned(natural(round(2.0**W_FRAC / (real(to_integer(F_CLK)) * real(CLK_MULT)))), 17);

    signal phi   : unsigned(15+W_FRAC downto 0); --!< Phase accumulator [cycles], UQ16.W_FRAC.
    signal d_phi : unsigned(15+W_FRAC downto 0); --!< Phase increment per clock [cycles], UQ16.W_FRAC.

begin

    process (clk)
    begin
        if rising_edge(clk) then
            -- UQ32.0 * UQ-24.40 = UQ8.40 (exact), zero-extended to UQ16.40
            d_phi <= resize(unsigned(freq_i) * T_CLK, d_phi'length);
            if rst_n = '0' then
                phi <= (others => '0');
            else
                -- Wraps on overflow: the phase is periodic modulo 2**16 cycles.
                phi <= phi + d_phi;
            end if;
        end if;
    end process;

    phase_high_o <= std_logic_vector(phi(15+W_FRAC downto W_FRAC));
    phase_low_o  <= std_logic_vector(phi(W_FRAC-1 downto W_FRAC-16));

end architecture;
