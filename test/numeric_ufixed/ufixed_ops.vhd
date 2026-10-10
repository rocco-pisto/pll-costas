library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ufixed_pkg.all;

--! @brief Test harness for ufixed_pkg: applies the operations under test to
--!        a_i and b_i and brings every result out to a port.
--!
--! Purely combinational. The operand formats are generics, so the same harness
--! covers aligned (same range) and misaligned operands.
--!
--! @generic A_L, A_R   a_i format, ufixed(A_L downto A_R).
--! @generic B_L, B_R   b_i format, ufixed(B_L downto B_R).
--! @generic RS_L, RS_R Target format of resize(a * b).
--!
--! @port a_i, b_i  Operands (SLV, raw bits).
--! @port sum_o     a + b, ufixed(max(A_L,B_L) downto min(A_R,B_R)).
--! @port diff_o    a - b, same format as sum_o.
--! @port prod_o    a * b, ufixed(A_L+B_L+1 downto A_R+B_R).
--! @port rsz_o     resize(a * b) to ufixed(RS_L downto RS_R).
--! @port eq_o .. ge_o  a = b, a /= b, a < b, a <= b, a > b, a >= b.
entity ufixed_ops is
    generic (
        A_L  : integer := 3;
        A_R  : integer := -4;
        B_L  : integer := 1;
        B_R  : integer := -6;
        RS_L : integer := 2;
        RS_R : integer := -3
    );
    port (
        a_i    : in  std_logic_vector(A_L-A_R downto 0) := (others => '0');
        b_i    : in  std_logic_vector(B_L-B_R downto 0) := (others => '0');
        sum_o  : out std_logic_vector(maximum(A_L, B_L)-minimum(A_R, B_R) downto 0);
        diff_o : out std_logic_vector(maximum(A_L, B_L)-minimum(A_R, B_R) downto 0);
        prod_o : out std_logic_vector(A_L+B_L+1-(A_R+B_R) downto 0);
        rsz_o  : out std_logic_vector(RS_L-RS_R downto 0);
        eq_o   : out std_logic;
        ne_o   : out std_logic;
        lt_o   : out std_logic;
        le_o   : out std_logic;
        gt_o   : out std_logic;
        ge_o   : out std_logic
    );
end entity ufixed_ops;

architecture rtl of ufixed_ops is

    function to_sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        end if;
        return '0';
    end function;

    -- Format templates: the range helpers take constants, not signals
    constant A_T : ufixed(A_L downto A_R) := (others => '0');
    constant B_T : ufixed(B_L downto B_R) := (others => '0');

    signal a    : ufixed(A_L downto A_R) := (others => '0');
    signal b    : ufixed(B_L downto B_R) := (others => '0');
    signal prod : ufixed(mult_left(A_T, B_T) downto mult_right(A_T, B_T));
    signal rsz  : ufixed(RS_L downto RS_R);

begin

    a <= to_ufixed(a_i, a);
    b <= to_ufixed(b_i, b);

    prod <= a * b;
    rsz  <= resize(prod, rsz);

    sum_o  <= to_slv(a + b);
    diff_o <= to_slv(a - b);
    prod_o <= to_slv(prod);
    rsz_o  <= to_slv(rsz);

    eq_o <= to_sl(a = b);
    ne_o <= to_sl(a /= b);
    lt_o <= to_sl(a < b);
    le_o <= to_sl(a <= b);
    gt_o <= to_sl(a > b);
    ge_o <= to_sl(a >= b);

end architecture rtl;
