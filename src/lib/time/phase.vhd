library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.board.all;
use work.ufixed_pkg.all;

--! @brief Phase accumulator (in cycles) for a given frequency.
--!
--! Every clock cycle accumulates freq_i * T_CLK, i.e. the phase advance in
--! cycles (turns) over one clock period, with T_CLK = 1 / (F_CLK * CLK_MULT).
--! T_CLK is ufixed(T_CLK_L downto T_CLK_R) with W_T_CLK bits below the MSB.
--! The accumulator is ufixed(15 downto T_CLK_R) and wraps modulo 2**16
--! cycles. The outputs are its 16 integer bits and the 16 MSBs of the
--! fractional part (truncated).
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
--! @note T_CLK is rounded to 2**T_CLK_R, so the phase drifts by
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

    constant W_T_CLK : natural := 16;                  --!< T_CLK precision [bits below the MSB].
    constant T_CLK_R : integer := T_CLK_L - W_T_CLK;   --!< T_CLK LSB index: 2**-40 s (~0.9 ps).

    --! Clock period [s], rounded to 2**T_CLK_R.
    constant T_CLK : ufixed(T_CLK_L downto T_CLK_R) :=
        to_ufixed(1.0 / (real(to_integer(F_CLK)) * real(CLK_MULT)), T_CLK_L, T_CLK_R);

    signal freq  : ufixed(31 downto 0);       --!< freq_i [Hz].
    signal d_phi : ufixed(15 downto T_CLK_R); --!< Phase increment per clock [cycles].
    signal phi   : ufixed(15 downto T_CLK_R); --!< Phase accumulator [cycles].

begin

    freq <= to_ufixed(freq_i, freq);

    process (clk)
    begin
        if rising_edge(clk) then
            -- (31 downto 0) * (-24 downto -40) = (8 downto -40), exact:
            -- resize only zero-extends it
            d_phi <= resize(freq * T_CLK, d_phi);
            if rst_n = '0' then
                phi <= (others => '0');
            else
                -- No growth: wraps, the phase is periodic modulo 2**16 cycles
                phi <= phi + d_phi;
            end if;
        end if;
    end process;

    phase_high_o <= to_slv(phi(15 downto 0));
    phase_low_o  <= to_slv(phi(-1 downto -16));

end architecture;
