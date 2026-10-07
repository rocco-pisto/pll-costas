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

use work.board.all;

--! @brief Top level: fixed 1 Hz NCO with its sin output decoded onto the LEDs.
--!
--! Clocking: clk_0 (50 MHz board clock) feeds pll_200, which generates the
--! 200 MHz clock (clk_200 = PLL_MULT * F_CLK) the NCO runs on.
--!
--! Reset: reset_pulse (clk_0 domain) asserts at configuration and drives the
--! PLL areset. Each clock domain has its own reset synchronizer:
--!  - clk_0:   reset while rst_pulse or button pressed (rst_n = '0').
--!  - clk_200: same, and also while the PLL is not locked.
--!
--! @port clk_0  Board clock, 50 MHz.
--! @port rst_n  Reset button, active low, asynchronous.
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
	component pll_200
		port (
			areset : in  std_logic := '0';
			inclk0 : in  std_logic := '0';
			c0     : out std_logic;
			locked : out std_logic
		);
	end component;

	component reset_pulse
		generic (
			N_CYCLES : positive := 16
		);
		port (
			clk   : in  std_logic;
			rst_o : out std_logic
		);
	end component;

	component synchronizer
		generic (
			N_W      : positive  := 1;
			N_STAGES : positive  := 2;
			RST_VAL  : std_logic := '0'
		);
		port (
			clk   : in  std_logic;
			rst_n : in  std_logic := '1';
			d_i   : in  std_logic_vector(N_W-1 downto 0);
			q_o   : out std_logic_vector(N_W-1 downto 0)
		);
	end component;

	component nco
		generic (
			CLK_MULT : positive := 1
		);
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

	-- Clocks and resets
	signal clk_200     : std_logic; --!< PLL output clock, 200 MHz.
	signal pll_locked  : std_logic; --!< PLL locked (asynchronous).
	signal rst_pulse   : std_logic; --!< Power-up reset pulse, active high (clk_0 domain).
	signal rst_req_0_n   : std_logic; --!< clk_0 reset request, active low (asynchronous).
	signal rst_req_200_n : std_logic; --!< clk_200 reset request, active low (asynchronous).
	signal rst_0_n     : std_logic; --!< Reset synchronized to clk_0, active low.
	signal rst_200_n   : std_logic; --!< Reset synchronized to clk_200, active low.

	-- clk_200 domain
	signal sin : std_logic_vector(15 downto 0); --!< NCO sine output, Q1.15.
	signal sin_ofs : std_logic_vector(2 downto 0); --!< sin 3 MSBs, offset binary (unsigned).
	signal led : std_logic_vector(7 downto 0);  --!< One-hot decoded LED pattern.
begin
-- {ALTERA_INSTANTIATION_BEGIN} DO NOT REMOVE THIS LINE!
	component_reset_pulse : reset_pulse
		port map (
			clk   => clk_0,
			rst_o => rst_pulse
		);

	component_pll_200 : pll_200
		port map (
			areset => rst_pulse,
			inclk0 => clk_0,
			c0     => clk_200,
			locked => pll_locked
		);

	component_sync_rst_0 : synchronizer
		port map (
			clk    => clk_0,
			d_i(0) => rst_req_0_n,
			q_o(0) => rst_0_n
		);

	component_sync_rst_200 : synchronizer
		port map (
			clk    => clk_200,
			d_i(0) => rst_req_200_n,
			q_o(0) => rst_200_n
		);

	component_nco : nco
		generic map (
			CLK_MULT => PLL_MULT
		)
		port map (
			clk     => clk_200,
			rst_n   => rst_200_n,
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

	-- Reset requests: power-up pulse or button, plus PLL unlocked for clk_200
	rst_req_0_n   <= rst_n and not rst_pulse;
	rst_req_200_n <= rst_n and not rst_pulse and pll_locked;

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
