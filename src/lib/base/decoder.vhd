library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @brief Generic binary to one-hot decoder.
--!
--! Interprets num_i as unsigned and drives high only bit num_i of dec_o;
--! all other bits are low. Purely combinational.
--!
--! @generic N_B   Number of input bits (output has 2**N_B bits).
--!
--! @port num_i    Input number (SLV, UQN_B.0).
--! @port dec_o    One-hot output, dec_o(to_integer(num_i)) = '1'.
entity decoder is
    generic (
        N_B : positive := 4 --!< Number of input bits.
    );
    port (
        num_i : in  std_logic_vector(N_B-1 downto 0);     --!< Input number, unsigned.
        dec_o : out std_logic_vector(2**N_B-1 downto 0)   --!< One-hot output.
    );
end entity decoder;

architecture rtl of decoder is
begin

    DECODE:
    process (num_i)
    begin
        dec_o <= (others => '0');
        dec_o(to_integer(unsigned(num_i))) <= '1';
    end process;

end architecture rtl;
