library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.board.all;

--! @brief Phase accumulator (in cycles) for a given frequency.
--!
--! Every clock cycle accumulates freq_i * T_CLK, i.e. the phase advance in
--! cycles (turns) over one clock period. The accumulator is UQ32.(-T_CLK_L)
--! (raw unsigned, LSB weight 2**T_CLK_L cycles) and wraps modulo 2**32 cycles.
--!
--! @port clk          Clock input.
--! @port rst_n        Synchronous active-low reset (clears the accumulator).
--! @port freq_i       Frequency [Hz] (SLV, UQ32.0).
--! @port phase_high_o Integer part of the phase [cycles] (SLV, UQ32.0).
--! @port phase_low_o  Fractional part of the phase [cycles] (SLV, UQ0.32),
--!                    wraps once per cycle of freq_i.
--!
--! @note freq_i is registered into d_phi: a change of freq_i affects the
--!       accumulator with one clock cycle of latency.
--! @note T_CLK is rounded to 2**T_CLK_L, so the phase drifts by
--!       freq_i * (T_CLK - 1/F_CLK) cycles per clock.
entity phase is
    port (
        clk          : in  std_logic;                     --!< Clock.
        rst_n        : in  std_logic;                     --!< Synchronous active-low reset.
        freq_i       : in  std_logic_vector(31 downto 0); --!< Frequency [Hz], UQ32.0.
        phase_high_o : out std_logic_vector(31 downto 0); --!< Phase integer part [cycles], UQ32.0.
        phase_low_o  : out std_logic_vector(31 downto 0)  --!< Phase fractional part [cycles], UQ0.32.
    );
end entity;

architecture rtl of phase is

    constant W_FRAC : integer := -T_CLK_L; --!< Accumulator fractional bits.

    signal phi   : unsigned(31+W_FRAC downto 0); --!< Phase accumulator [cycles], UQ32.W_FRAC.
    signal d_phi : unsigned(31+W_FRAC downto 0); --!< Phase increment per clock [cycles], UQ32.W_FRAC.

begin

    process (clk)
    begin
        if rising_edge(clk) then
            -- UQ32.0 * UQ-24.40 = UQ8.40 (exact), zero-extended to UQ32.40
            d_phi <= resize(unsigned(freq_i) * T_CLK, d_phi'length);
            if rst_n = '0' then
                phi <= (others => '0');
            else
                -- Wraps on overflow: the phase is periodic modulo 2**32 cycles.
                phi <= phi + d_phi;
            end if;
        end if;
    end process;

    phase_high_o <= std_logic_vector(phi(31+W_FRAC downto W_FRAC));
    phase_low_o  <= std_logic_vector(phi(W_FRAC-1 downto W_FRAC-32));

end architecture;
