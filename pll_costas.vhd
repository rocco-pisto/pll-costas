-- Copyright (C) 2025  Altera Corporation. All rights reserved.
-- Your use of Altera Corporation's design tools, logic functions 
-- and other software and tools, and any partner logic 
-- functions, and any output files from any of the foregoing 
-- (including device programming or simulation files), and any 
-- associated documentation or information are expressly subject 
-- to the terms and conditions of the Altera Program License 
-- Subscription Agreement, the Altera Quartus Prime License Agreement,
-- the Altera IP License Agreement, or other applicable license
-- agreement, including, without limitation, that your use is for
-- the sole purpose of programming logic devices manufactured by
-- Altera and sold by Altera or its authorized distributors.  Please
-- refer to the Altera Software License Subscription Agreements 
-- on the Quartus Prime software download page.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library altera;
use altera.altera_syn_attributes.all;

--! @brief Top level: fixed 1 Hz NCO with its sin output decoded onto the LEDs.
--!
--! @port clk_0  Clock input.
--! @port rst_n  Synchronous active-low reset.
--! @port led_*  One-hot display of the NCO sin output's 3 MSBs in offset
--!               binary: led_0 at sin = -1, led_7 at sin = +1.
entity pll_costas is
	port
	(
-- {ALTERA_IO_BEGIN} DO NOT REMOVE THIS LINE!

		clk_0 : in std_logic;
		rst_n : in std_logic;
		led_0 : out std_logic;
		led_1 : out std_logic;
		led_2 : out std_logic;
		led_3 : out std_logic;
		led_4 : out std_logic;
		led_5 : out std_logic;
		led_6 : out std_logic;
		led_7 : out std_logic
-- {ALTERA_IO_END} DO NOT REMOVE THIS LINE!

	);

-- {ALTERA_ATTRIBUTE_BEGIN} DO NOT REMOVE THIS LINE!
-- {ALTERA_ATTRIBUTE_END} DO NOT REMOVE THIS LINE!
end pll_costas;

architecture ppl_type of pll_costas is

-- {ALTERA_COMPONENTS_BEGIN} DO NOT REMOVE THIS LINE!
	component nco
		port (
			clk     : in  std_logic;
			rst_n   : in  std_logic;
			freq_i  : in  std_logic_vector(31 downto 0);
			sin_o   : out std_logic_vector(15 downto 0);
			cos_o   : out std_logic_vector(15 downto 0);
			valid_o : out std_logic
		);
	end component;

	component decoder
		generic (
			N_B : positive := 4
		);
		port (
			num_i : in  std_logic_vector(N_B-1 downto 0);
			dec_o : out std_logic_vector(2**N_B-1 downto 0)
		);
	end component;
-- {ALTERA_COMPONENTS_END} DO NOT REMOVE THIS LINE!

	constant FREQ_C : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(1, 32)); --!< NCO frequency, 1 Hz.

	signal sin : std_logic_vector(15 downto 0); --!< NCO sine output, Q1.15.
	signal sin_ofs : std_logic_vector(2 downto 0); --!< sin 3 MSBs, offset binary (unsigned).
	signal led : std_logic_vector(7 downto 0);  --!< One-hot decoded LED pattern.
begin
-- {ALTERA_INSTANTIATION_BEGIN} DO NOT REMOVE THIS LINE!
	component_nco : nco
		port map (
			clk     => clk_0,
			rst_n   => rst_n,
			freq_i  => FREQ_C,
			sin_o   => sin,
			cos_o   => open,
			valid_o => open
		);

	component_decoder : decoder
		generic map (
			N_B => 3
		)
		port map (
			num_i => sin_ofs,
			dec_o => led
		);
-- {ALTERA_INSTANTIATION_END} DO NOT REMOVE THIS LINE!

	-- Q1.15 signed -> offset binary: invert the sign bit so -1..+1 maps to 0..7
	sin_ofs <= not sin(15) & sin(14 downto 13);

	led_0 <= led(0);
	led_1 <= led(1);
	led_2 <= led(2);
	led_3 <= led(3);
	led_4 <= led(4);
	led_5 <= led(5);
	led_6 <= led(6);
	led_7 <= led(7);

end;
