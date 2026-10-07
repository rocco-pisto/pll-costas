library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @brief Numerically controlled oscillator: frequency in, sin/cos out.
--!
--! Integrates freq_i into a phase with the phase accumulator, then feeds the
--! fractional phase (phase_low, UQ0.16) as a Q0.16 BAM angle to the sin/cos
--! generator. The integer part of the phase is unused.
--!
--! @generic CLK_MULT Ratio between clk and the board clock F_CLK (see phase).
--!
--! @port clk     Clock input, F_CLK * CLK_MULT.
--! @port rst_n   Synchronous active-low reset.
--! @port freq_i  Output frequency [Hz] (SLV, UQ32.0).
--! @port sin_o   Sine output, valid when valid_o='1' (SLV, Q1.15 signed).
--! @port cos_o   Cosine output, valid when valid_o='1' (SLV, Q1.15 signed).
--! @port valid_o High when sin_o/cos_o are valid (continuously after reset).
--!
--! @note The sin/cos generator is enabled every cycle, so a new sample is
--!       produced each clock. Latency from a phase accumulation to sin_o/cos_o
--!       is 7 clock cycles (1 register + 6 sincos pipeline), from a freq_i
--!       change 8 clock cycles.
entity nco is
    generic (
        CLK_MULT : positive := 1 --!< clk frequency / F_CLK.
    );
    port (
        clk     : in  std_logic;                     --!< Clock.
        rst_n   : in  std_logic;                     --!< Synchronous active-low reset.
        freq_i  : in  std_logic_vector(31 downto 0); --!< Frequency [Hz], UQ32.0.
        sin_o   : out std_logic_vector(15 downto 0); --!< Sine output, Q1.15.
        cos_o   : out std_logic_vector(15 downto 0); --!< Cosine output, Q1.15.
        valid_o : out std_logic                      --!< Outputs valid.
    );
end entity nco;

architecture rtl of nco is

    component phase
        generic (
            CLK_MULT : positive := 1
        );
        port (
            clk          : in  std_logic;
            rst_n        : in  std_logic;
            freq_i       : in  std_logic_vector(31 downto 0);
            phase_high_o : out std_logic_vector(15 downto 0);
            phase_low_o  : out std_logic_vector(15 downto 0)
        );
    end component;
    component sincos
        port (
            clk     : in  std_logic;
            rst_n   : in  std_logic;
            en_i    : in  std_logic;
            angle_i : in  std_logic_vector(15 downto 0);
            sin_o   : out std_logic_vector(15 downto 0);
            cos_o   : out std_logic_vector(15 downto 0);
            done_o  : out std_logic
        );
    end component;

    signal phase_low : std_logic_vector(15 downto 0); --!< Fractional phase [cycles], UQ0.16 = Q0.16 BAM.

begin

    component_phase : phase
        generic map (
            CLK_MULT => CLK_MULT
        )
        port map (
            clk          => clk,
            rst_n        => rst_n,
            freq_i       => freq_i,
            phase_high_o => open,
            phase_low_o  => phase_low
        );

    component_sincos : sincos
        port map (
            clk     => clk,
            rst_n   => rst_n,
            en_i    => '1',
            angle_i => phase_low,
            sin_o   => sin_o,
            cos_o   => cos_o,
            done_o  => valid_o
        );

end architecture rtl;
