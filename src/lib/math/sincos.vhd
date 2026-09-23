library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @brief Sine/cosine LUT with linear interpolation.
--!
--! Evaluates sin and cos using a NADDR-entry first-quadrant LUT and linear
--! interpolation. The angle is reduced to the first quadrant via symmetry.
--!
--! @generic DEG      When true input is degrees [0, 360); false = normalized [0, 1).
--!
--! @port clk         Clock input.
--! @port rst_n       Synchronous active-low reset.
--! @port start_i     Pulse high to start; latches angle on that rising edge.
--! @port angle_i     Input angle (SLV 32-bit): Q16.16 degrees when DEG=true,
--!                   Q0.32 unsigned normalized phase [0,1) when DEG=false.
--! @port sin_o       Sine result, valid when done_o='1' (SLV, Q15.16 signed).
--! @port cos_o       Cosine result, valid when done_o='1' (SLV, Q15.16 signed).
--! @port done_o      Pulses high for one cycle when outputs are valid.
--!
--! @note Computation latency is 2 clock cycles from start_i assertion.
--! @note Requires VHDL-2008 (ieee.fixed_pkg).
entity sincos is
    port (
        clk     : in  std_logic;                    --!< Clock.
        rst_n   : in  std_logic;                    --!< Synchronous active-low reset.
        en_i   : in  std_logic;                    --!< Enable input.
        angle_i : in  std_logic_vector(15 downto 0);        --!< Q0.16 BAM
        sin_o   : out std_logic_vector(15 downto 0);      --!< Sine output, Q2.14.
        cos_o   : out std_logic_vector(15 downto 0);       --!< Cosine output, Q2.14.
        done_o : out std_logic                     --!< Pulses high for one cycle when outputs are valid.
    );
end entity sincos;

architecture rtl of sincos is

    constant W_ROM : integer := 5; --!< Width of LUT address.
    constant W_INT : integer := 16-2-W_ROM; --!< Width of interpolation factor.

    component rom_sin
        PORT
        (
            address_a		: IN STD_LOGIC_VECTOR (4 DOWNTO 0);
            address_b		: IN STD_LOGIC_VECTOR (4 DOWNTO 0);
            clock		: IN STD_LOGIC  := '1';
            q_a		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
            q_b		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
        );
    end component;
    component rom_cos
        PORT
        (
            address_a		: IN STD_LOGIC_VECTOR (4 DOWNTO 0);
            address_b		: IN STD_LOGIC_VECTOR (4 DOWNTO 0);
            clock		: IN STD_LOGIC  := '1';
            q_a		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
            q_b		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0)
        );
    end component;
    component mult_16
        PORT
        (
            dataa		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
            datab		: IN STD_LOGIC_VECTOR (15 DOWNTO 0);
            result		: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
        );
    end component;
    
    -- Angle slicing
    signal in_sign : std_logic; -- MSB
    signal in_qdr : std_logic; -- MSB -1
    signal in_rom : std_logic_vector(W_ROM-1 downto 0); -- MSB - 2 downto MSB - 2 - WADDR + 1
    signal in_intp  : std_logic_vector(W_INT-1 downto 0); -- MSB - 2 - WADDR downto 0

    -- LUT readings
    signal angle_0 : unsigned(W_ROM downto 0);
    signal angle_1 : unsigned(W_ROM downto 0);
    signal angle_0_sign : std_logic;
    signal angle_1_sign : std_logic;

    constant C_ONE : signed(15 downto 0) := to_signed(2 ** 14, 16);
    constant C_ZERO : signed(15 downto 0) := to_signed(0, 16);
    

    signal sin_raw_0 : std_logic_vector(15 downto 0);
    signal sin_raw_1 : std_logic_vector(15 downto 0);
    signal sin_0 : signed(15 downto 0);
    signal sin_1 : signed(15 downto 0);
    signal sin_d : signed(15 downto 0);
    signal sin_intp : std_logic_vector(31 downto 0);
    signal sin_v : signed(15 downto 0);
    

    signal cos_raw_0 : std_logic_vector(15 downto 0);
    signal cos_raw_1 : std_logic_vector(15 downto 0);
    signal cos_0 : signed(15 downto 0);
    signal cos_1 : signed(15 downto 0);
    signal cos_d : signed(15 downto 0);
    signal cos_intp : std_logic_vector(31 downto 0);
    signal cos_v : signed(15 downto 0);

    -- Interpolation factor
    signal k_intp : std_logic_vector(15 downto 0);

    constant NPIPE : integer := 4; --!< Number of pipeline stages.
    type sign_array_t is array (0 to NPIPE-1) of std_logic;
    type done_array_t is array (0 to NPIPE-1) of std_logic;
    type k_array_t is array (0 to NPIPE-1) of std_logic_vector(W_INT-1 downto 0);
    signal sign_array : sign_array_t;
    signal k_array : k_array_t;
    signal done_array : done_array_t;
begin

    -- Slice angle into quadrant, LUT index, and interpolation factor
    in_sign <= angle_i(15);
    in_qdr <= angle_i(14);
    in_rom <= angle_i(13 downto 9);
    in_intp  <= angle_i(8 downto 0);

    component_sin : rom_sin
        port map (
            address_a => std_logic_vector(angle_0(W_ROM-1 downto 0)),
            address_b => std_logic_vector(angle_1(W_ROM-1 downto 0)),
            clock     => clk,
            q_a       => sin_raw_0,
            q_b       => sin_raw_1
        );
    
    component_cos : rom_cos
        port map ( 
            address_a => std_logic_vector(angle_0(W_ROM-1 downto 0)),
            address_b => std_logic_vector(angle_1(W_ROM-1 downto 0)),
            clock     => clk,
            q_a       => cos_raw_0,
            q_b       => cos_raw_1
        );
    
    -- Q2.14 * Q7.9 = Q9.23, then truncate to Q2.14
    interp_sin : mult_16
        port map (
            dataa  => std_logic_vector(sin_d),
            datab  => k_intp,
            result => sin_intp
        );
    
    interp_cos : mult_16
        port map (
            dataa  => std_logic_vector(cos_d),
            datab  => k_intp,
            result => cos_intp
        );

PIPELINE:
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                sign_array <= (others => '0');
                k_array <= (others => (others => '0'));
                done_array <= (others => '0');
            else
                -- Pipeline signals
                sign_array(0) <= in_sign;
                k_array(0) <= in_intp;
                done_array(0) <= en_i;
                for i in 1 to NPIPE-1 loop
                    sign_array(i) <= sign_array(i-1);
                    k_array(i) <= k_array(i-1);
                    done_array(i) <= done_array(i-1);
                end loop;
            end if;
        end if;
    end process;

LUT_addressing:
    process (clk)
    begin
        -- 0) Compute LUT addresses for the two nearest angles
        if rising_edge(clk) then
            if in_qdr = '0' then
                angle_0 <= "0" & unsigned(in_rom);     -- theta
                angle_1 <= angle_0 + 1;      -- theta + 1
            else
                angle_1 <= "0" & not unsigned(in_rom); -- 90 - theta - 1
                angle_0 <= angle_1 + 1;      -- 90 - theta
            end if;

            -- 1-cycle delay to match LUT reading latency
            angle_0_sign <= angle_0(W_ROM);
            angle_1_sign <= angle_1(W_ROM);
        end if;
    end process;

LUT_reading:
    process (clk)
        variable sin_0_var : signed(15 downto 0);
        variable sin_1_var : signed(15 downto 0);
        variable cos_0_var : signed(15 downto 0);
        variable cos_1_var : signed(15 downto 0);
    begin
        if rising_edge(clk) then
            -- 2) Read LUT values and compute differences
            if angle_0_sign = '1' then
                sin_0_var := C_ONE;
                sin_1_var := signed(sin_raw_1);
                cos_0_var := C_ZERO;
                cos_1_var := signed(cos_raw_1);
            elsif angle_1_sign = '1' then
                sin_0_var := signed(sin_raw_0);
                sin_1_var := C_ONE;
                cos_0_var := signed(cos_raw_0);
                cos_1_var := C_ZERO;
            else
                sin_0_var := signed(sin_raw_0);
                sin_1_var := signed(sin_raw_1);
                cos_0_var := signed(cos_raw_0);
                cos_1_var := signed(cos_raw_1);
            end if;
            sin_0 <= sin_0_var;
            cos_0 <= cos_0_var;
            sin_1 <= sin_1_var;
            cos_1 <= cos_1_var;
            sin_d <= sin_1_var - sin_0_var;
            cos_d <= cos_1_var - cos_0_var;
        end if;
    end process;

    -- Multiplier inputs ready at the end of stage 2
    k_intp(W_INT-1 downto 0) <= k_array(2);
    k_intp(15 downto W_INT) <= (others => '0');


MULTIPLY_read:
    process (clk)
    begin
        if rising_edge(clk) then
            -- 3) Sum base and interpolated values
            sin_v <= sin_0 + signed(sin_intp(15+9 downto 9));
            cos_v <= cos_0 + signed(cos_intp(15+9 downto 9));
        end if;
    end process;

OUTPUT_write:
    process (clk)
    begin   
        if rising_edge(clk) then
            -- 4) Apply quadrant sign
            if sign_array(3) = '1' then
                sin_o <= std_logic_vector(-sin_v);
                cos_o <= std_logic_vector(-cos_v);
            else
                sin_o <= std_logic_vector(sin_v);
                cos_o <= std_logic_vector(cos_v);
            end if;
        end if;
    end process;

    done_o <= done_array(4);

end architecture rtl;
