library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @brief Power-up reset pulse generator.
--!
--! Asserts rst_o from configuration (register initial value) and releases it
--! after N_CYCLES clock cycles. Needs no external reset: the initial values
--! are loaded from the bitstream. Intended to drive the asynchronous reset
--! (areset) of the PLL from the clock that feeds the PLL itself.
--!
--! @generic N_CYCLES Pulse length [clock cycles].
--!
--! @port clk   Clock input (the PLL reference clock).
--! @port rst_o Active-high reset pulse, high for N_CYCLES clock cycles after
--!             configuration.
--!
--! @note N_CYCLES must cover the minimum areset pulse width of the PLL.
entity reset_pulse is
    generic (
        N_CYCLES : positive := 16 --!< Pulse length [clock cycles].
    );
    port (
        clk   : in  std_logic; --!< Clock.
        rst_o : out std_logic  --!< Active-high reset pulse.
    );
end entity reset_pulse;

architecture rtl of reset_pulse is

    signal cnt : natural range 0 to N_CYCLES := 0;   --!< Elapsed cycles (initialised at configuration).
    signal rst : std_logic                   := '1'; --!< Reset register, asserted at configuration.

begin

    process (clk)
    begin
        if rising_edge(clk) then
            if cnt = N_CYCLES - 1 then
                rst <= '0';
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    rst_o <= rst;

end architecture rtl;
