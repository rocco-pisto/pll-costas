library ieee;
use ieee.std_logic_1164.all;

--! @brief Clock-domain-crossing synchronizer for std_logic / std_logic_vector.
--!
--! Passes an asynchronous input through N_STAGES flip-flops (per bit) clocked
--! by the destination clock. A single signal is a vector of width 1
--! (N_W => 1, connect d_i(0) / q_o(0)).
--!
--! To synchronize a reset, connect the (inverted) reset to d_i and use the
--! result as the reset of the destination domain. The reset input of this
--! block itself is optional (default inactive); it can be driven by a reset
--! already synchronized by another instance.
--!
--! @generic N_W      Width of the synchronized signal [bits].
--! @generic N_STAGES Number of synchronizer flip-flops (>= 2).
--! @generic RST_VAL  Value of every flop at power-up and during reset.
--!
--! @port clk   Clock input (destination domain).
--! @port rst_n Synchronous active-low reset (already synchronized to clk).
--! @port d_i   Asynchronous input (SLV, N_W bits).
--! @port q_o   Synchronized output (SLV, N_W bits), N_STAGES cycles latency.
--!
--! @note Bits are synchronized independently: a multi-bit value can be
--!       sampled with bits from different source cycles. Use it only for
--!       single-bit signals or for vectors whose bits are independent
--!       (e.g. Gray-coded or static values).
--! @note The flops power up at RST_VAL (initial value loaded at configuration).
entity synchronizer is
    generic (
        N_W      : positive  := 1;  --!< Signal width [bits].
        N_STAGES : positive  := 2;  --!< Synchronizer depth [flip-flops].
        RST_VAL  : std_logic := '0' --!< Power-up / reset value.
    );
    port (
        clk   : in  std_logic;                          --!< Clock.
        rst_n : in  std_logic := '1';                   --!< Synchronous active-low reset.
        d_i   : in  std_logic_vector(N_W-1 downto 0);   --!< Asynchronous input.
        q_o   : out std_logic_vector(N_W-1 downto 0)    --!< Synchronized output.
    );
end entity synchronizer;

architecture rtl of synchronizer is

    type chain_t is array (0 to N_STAGES-1) of std_logic_vector(N_W-1 downto 0);

    signal chain : chain_t := (others => (others => RST_VAL)); --!< Synchronizer chain.

    attribute altera_attribute : string;
    attribute altera_attribute of rtl : architecture is
        "-name SYNCHRONIZER_IDENTIFICATION ""FORCED IF ASYNCHRONOUS""";

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                chain <= (others => (others => RST_VAL));
            else
                chain(0) <= d_i;
                for i in 1 to N_STAGES-1 loop
                    chain(i) <= chain(i-1);
                end loop;
            end if;
        end if;
    end process;

    q_o <= chain(N_STAGES-1);

end architecture rtl;
