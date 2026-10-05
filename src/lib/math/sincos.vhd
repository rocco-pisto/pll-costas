library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

--! @brief Sine/cosine LUT with linear interpolation.
--!
--! Evaluates sin and cos using a 32-entry first-quadrant LUT and linear
--! interpolation. The angle is reduced to the first quadrant via symmetry;
--! sin negates on the half bit (angle_i(15)) alone, cos negates on the half
--! bit xor the quadrant bit (angle_i(15) xor angle_i(14)).
--!
--! @port clk         Clock input.
--! @port rst_n       Synchronous active-low reset.
--! @port en_i        Pulse high to latch angle_i on that rising edge.
--! @port angle_i     Input angle, Q0.16 unsigned BAM (SLV, angle/360 in [0,1)).
--! @port sin_o       Sine result, valid when done_o='1' (SLV, Q1.15 signed).
--! @port cos_o       Cosine result, valid when done_o='1' (SLV, Q1.15 signed).
--! @port done_o      Pulses high for one cycle when outputs are valid.
--!
--! @note Computation latency is 5 clock cycles from en_i assertion.
entity sincos is
    port (
        clk     : in  std_logic;                    --!< Clock.
        rst_n   : in  std_logic;                    --!< Synchronous active-low reset.
        en_i   : in  std_logic;                    --!< Enable input.
        angle_i : in  std_logic_vector(15 downto 0);        --!< Q0.16 BAM
        sin_o   : out std_logic_vector(15 downto 0);      --!< Sine output, Q1.15.
        cos_o   : out std_logic_vector(15 downto 0);       --!< Cosine output, Q1.15.
        done_o : out std_logic                     --!< Pulses high for one cycle when outputs are valid.
    );
end entity sincos;

architecture rtl of sincos is
    constant W_QUAD : integer := 2; --!< Width of quadrant signal.
    constant W_ROM : integer := 5; --!< Width of LUT address.
    constant W_INT : integer := 16-W_QUAD-W_ROM; --!< Width of interpolation factor.

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
            q_a		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0);
            q_b		: OUT STD_LOGIC_VECTOR (15 DOWNTO 0)
        );
    end component;
    
    -- Angle slicing
    signal in_sin_sign : std_logic; -- sin negates on H alone (angle_i(15))
    signal in_cos_sign : std_logic; -- cos negates on H xor Q, not H alone (see in_sin_sign)
    signal in_qdr : std_logic; -- MSB -1
    signal in_rom : std_logic_vector(W_ROM-1 downto 0); -- MSB - 2 downto MSB - 2 - WADDR + 1
    signal in_intp  : std_logic_vector(W_INT-1 downto 0); -- MSB - 2 - WADDR downto 0

    -- LUT readings
    signal angle_0 : unsigned(W_ROM downto 0);
    signal angle_1 : unsigned(W_ROM downto 0);
    signal angle_0_max : std_logic;
    signal angle_1_max : std_logic;

    constant C_ONE : signed(15 downto 0) := to_signed(2 ** 15 - 1, 16);
    constant C_ZERO : signed(15 downto 0) := to_signed(0, 16);
    

    signal sin_raw_0 : std_logic_vector(15 downto 0);
    signal sin_raw_1 : std_logic_vector(15 downto 0);
    signal sin_d : signed(15 downto 0);
    signal sin_intp : signed(16+W_INT downto 0);
    signal sin_v : signed(15 downto 0);
    

    signal cos_raw_0 : std_logic_vector(15 downto 0);
    signal cos_raw_1 : std_logic_vector(15 downto 0);
    signal cos_d : signed(15 downto 0);
    signal cos_intp : signed(16+W_INT downto 0);
    signal cos_v : signed(15 downto 0);

    constant NPIPE : integer := 6; --!< Number of pipeline stages.
    type sign_array_t is array (0 to NPIPE-1) of std_logic;
    type done_array_t is array (0 to NPIPE-1) of std_logic;
    type k_array_t is array (0 to NPIPE-1) of std_logic_vector(W_INT-1 downto 0);
    type lut_array_t is array (0 to 2) of signed(15 downto 0);
    signal sin_sign_array : sign_array_t;
    signal cos_sign_array : sign_array_t;
    signal k_array : k_array_t;
    signal done_array : done_array_t;
    signal cos_0 : lut_array_t;
    signal cos_1 : signed(15 downto 0);
    signal sin_0 : lut_array_t;
    signal sin_1 : signed(15 downto 0);

begin

    -- Slice angle into quadrant, LUT index, and interpolation factor
    in_sin_sign <= angle_i(15);
    in_cos_sign <= angle_i(15) xor angle_i(14);
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

PIPELINE:
    process (clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                sin_sign_array <= (others => '0');
                cos_sign_array <= (others => '0');
                k_array <= (others => (others => '0'));
                done_array <= (others => '0');
            else
                -- Pipeline signals
                sin_sign_array(0) <= in_sin_sign;
                cos_sign_array(0) <= in_cos_sign;
                k_array(0) <= in_intp;
                done_array(0) <= en_i;
                for i in 1 to NPIPE-1 loop
                    sin_sign_array(i) <= sin_sign_array(i-1);
                    cos_sign_array(i) <= cos_sign_array(i-1);
                    k_array(i) <= k_array(i-1);
                    done_array(i) <= done_array(i-1);
                end loop;
            end if;
        end if;
    end process;

LUT_addressing:
    process (clk)
        variable angle_0_ext : unsigned(W_ROM downto 0);
        variable angle_1_ext : unsigned(W_ROM downto 0);
    begin
        -- 0) Compute LUT addresses for the two nearest angles
        if rising_edge(clk) then
            if in_qdr = '0' then
                angle_0_ext := "0" & unsigned(in_rom);     -- theta
                angle_1_ext := angle_0_ext + 1;      -- theta + 1
            else
                angle_1_ext := "0" & not unsigned(in_rom); -- 90 - theta - 1
                angle_0_ext := angle_1_ext + 1;      -- 90 - theta
            end if;

            angle_0 <= angle_0_ext;
            angle_1 <= angle_1_ext;

            -- 1) 1-cycle delay to match LUT reading latency
            angle_0_max <= angle_0(W_ROM);
            angle_1_max <= angle_1(W_ROM);
        end if;
    end process;

LUT_reading:
    process (clk)
    begin
        if rising_edge(clk) then
            -- 2) Read LUT values and compute differences
            if angle_0_max = '1' then
                sin_0(0) <= C_ONE;
                sin_1 <= signed(sin_raw_1);
                cos_0(0) <= C_ZERO;
                cos_1 <= signed(cos_raw_1);
            elsif angle_1_max = '1' then
                sin_0(0) <= signed(sin_raw_0);
                sin_1 <= C_ONE;
                cos_0(0) <= signed(cos_raw_0);
                cos_1 <= C_ZERO;
            else
                sin_0(0) <= signed(sin_raw_0);
                sin_1 <= signed(sin_raw_1);
                cos_0(0) <= signed(cos_raw_0);
                cos_1 <= signed(cos_raw_1);
            end if;

            -- 3) 1-cycle delay to compute differences after LUT read; delay
            -- the base values too so they stay aligned with the differences
            sin_d <= sin_1 - sin_0(0);
            cos_d <= cos_1 - cos_0(0);

            -- Delay the base values to align with the multiplier output
            for i in 1 to 2 loop
                sin_0(i) <= sin_0(i-1);
                cos_0(i) <= cos_0(i-1);
            end loop;
        end if;
    end process;

MULTIPLY_intp:
    process (clk)
        variable k_intp : signed(W_INT downto 0);
    begin
        if rising_edge(clk) then
            -- 4) Sum base and interpolated values
            k_intp := "0" & signed(k_array(3));
            sin_intp <= sin_d * k_intp;
            cos_intp <= cos_d * k_intp;
        end if;
    end process;

ADD_intp:
    process (clk)
    begin
        if rising_edge(clk) then
            -- 5) Sum base and interpolated values
            sin_v <= sin_0(2) + sin_intp(15+W_INT downto W_INT);
            cos_v <= cos_0(2) + cos_intp(15+W_INT downto W_INT);
        end if;
    end process;

OUTPUT_write:
    process (clk)
    begin   
        if rising_edge(clk) then
            -- 6) Apply quadrant sign (sin negates on H, cos negates on H xor Q)
            if cos_sign_array(5) = '1' then
                cos_o <= std_logic_vector(-cos_v);
            else
                cos_o <= std_logic_vector(cos_v);
            end if;
            if sin_sign_array(5) = '1' then
                sin_o <= std_logic_vector(-sin_v);
            else
                sin_o <= std_logic_vector(sin_v);
            end if;
            done_o <= done_array(5);
        end if;
    end process;


end architecture rtl;
