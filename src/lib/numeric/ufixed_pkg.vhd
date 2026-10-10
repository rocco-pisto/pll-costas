library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

--! @brief Unsigned fixed-point type and arithmetic, synthesizable in Quartus
--!        Prime Standard (replacement for the unsupported ieee.fixed_pkg).
--!
--! The format is carried by the index range: ufixed(L downto R) is an
--! unsigned number of L-R+1 bits with value raw * 2**R. Index L is the MSB
--! (no sign bit); R may be negative (fractional bits) or positive, e.g.
--! UQ16.16 = ufixed(15 downto -16). For quantities that are never negative
--! (frequencies, periods, phase in cycles). sfixed_pkg converts it to sfixed.
--!
--! Rules (all operations are implemented on numeric_std unsigned), same as
--! sfixed_pkg except for the padding on the left:
--!  - align: lossless padding to a wider range (zeros on both sides). Every
--!    two-operand operation first aligns both operands to the common range
--!    (max L downto min R).
--!  - "+", "-": no growth. Result range is the common range; overflow and
--!    a negative difference wrap (modulo 2**(L+1)).
--!  - "*": full precision, result range (L1+L2+1 downto R1+R2), i.e. the
--!    same width as the unsigned multiplication of the raw operands. Never
--!    wraps.
--!  - Comparisons: exact, on the aligned operands.
--!  - resize: wrap on the left (drop MSBs), truncate on the right (drop LSBs).
--!
--! This package also holds maximum/minimum for integers (used by both
--! packages, so declared only here).
--!
--! @note Ranges must be descending (L >= R).
package ufixed_pkg is

    --! Unsigned fixed-point number, value = raw * 2**'right.
    type ufixed is array (integer range <>) of std_logic;

    --! Integer maximum/minimum, same as the VHDL-2008 built-ins, which Quartus
    --! Standard does not provide. In Questa this explicit declaration takes
    --! precedence over the implicit built-in (same result).
    --! E.g. for port widths: maximum(A_L, B_L) - minimum(A_R, B_R).
    function maximum(a, b : integer) return integer;
    function minimum(a, b : integer) return integer;

    --! Raw bits to ufixed(left downto right); arg'length must be left-right+1.
    function to_ufixed(arg : unsigned; left, right : integer) return ufixed;
    function to_ufixed(arg : std_logic_vector; left, right : integer) return ufixed;
    function to_ufixed(arg : unsigned; size_res : ufixed) return ufixed;
    function to_ufixed(arg : std_logic_vector; size_res : ufixed) return ufixed;

    --! Real value to ufixed(left downto right), rounded to nearest. For
    --! constants only (not synthesizable on signals). Fails if out of range
    --! or if the raw value (value / LSB) needs more than a 32-bit integer.
    function to_ufixed(arg : real; left, right : integer) return ufixed;
    function to_ufixed(arg : real; size_res : ufixed) return ufixed;

    --! Raw bits of arg, (arg'length-1 downto 0).
    function to_unsigned(arg : ufixed) return unsigned;
    function to_slv(arg : ufixed) return std_logic_vector;

    --! Lossless padding to (left downto right): requires left >= arg'left and
    --! right <= arg'right.
    function align(arg : ufixed; left, right : integer) return ufixed;

    --! Change format: wrap on the left, truncate on the right.
    function resize(arg : ufixed; left, right : integer) return ufixed;
    function resize(arg : ufixed; size_res : ufixed) return ufixed;

    --! Common range of two operands: max(l'left, r'left), min(l'right, r'right).
    function align_left(l, r : ufixed) return integer;
    function align_right(l, r : ufixed) return integer;

    --! Product range: (l'left + r'left + 1 downto l'right + r'right).
    --! Only the ranges of l and r are used: pass constants (format templates)
    --! when declaring signals, since Questa warns (vcom-1013) on signals.
    function mult_left(l, r : ufixed) return integer;
    function mult_right(l, r : ufixed) return integer;

    function "+" (l, r : ufixed) return ufixed;  --!< Common range, wraps.
    function "-" (l, r : ufixed) return ufixed;  --!< Common range, wraps.
    function "*" (l, r : ufixed) return ufixed;  --!< Full precision, l'length + r'length bits.

    function "="  (l, r : ufixed) return boolean;
    function "/=" (l, r : ufixed) return boolean;
    function "<"  (l, r : ufixed) return boolean;
    function "<=" (l, r : ufixed) return boolean;
    function ">"  (l, r : ufixed) return boolean;
    function ">=" (l, r : ufixed) return boolean;

end package ufixed_pkg;

package body ufixed_pkg is

    function maximum(a, b : integer) return integer is
    begin
        if a > b then
            return a;
        end if;
        return b;
    end function;

    function minimum(a, b : integer) return integer is
    begin
        if a < b then
            return a;
        end if;
        return b;
    end function;

    -- Conversions ------------------------------------------------------------

    function to_ufixed(arg : unsigned; left, right : integer) return ufixed is
        variable res : ufixed(left downto right);
    begin
        assert arg'length = res'length
            report "ufixed_pkg.to_ufixed: length mismatch" severity failure;
        res := ufixed(arg);  -- by position
        return res;
    end function;

    function to_ufixed(arg : std_logic_vector; left, right : integer) return ufixed is
    begin
        return to_ufixed(unsigned(arg), left, right);
    end function;

    function to_ufixed(arg : unsigned; size_res : ufixed) return ufixed is
    begin
        return to_ufixed(arg, size_res'left, size_res'right);
    end function;

    function to_ufixed(arg : std_logic_vector; size_res : ufixed) return ufixed is
    begin
        return to_ufixed(unsigned(arg), size_res'left, size_res'right);
    end function;

    function to_ufixed(arg : real; left, right : integer) return ufixed is
        constant W : natural := left - right + 1;
        constant X : real    := arg * 2.0**(-right);  -- value / LSB
    begin
        assert X >= 0.0 and X < 2.0**W - 0.5
            report "ufixed_pkg.to_ufixed: real value out of range" severity failure;
        assert X < 2.0**31
            report "ufixed_pkg.to_ufixed: raw value exceeds integer range" severity failure;
        return to_ufixed(to_unsigned(natural(round(X)), W), left, right);
    end function;

    function to_ufixed(arg : real; size_res : ufixed) return ufixed is
    begin
        return to_ufixed(arg, size_res'left, size_res'right);
    end function;

    function to_unsigned(arg : ufixed) return unsigned is
        variable v : ufixed(arg'length-1 downto 0);
    begin
        v := arg;  -- by position, natural range for the conversion
        return unsigned(v);
    end function;

    function to_slv(arg : ufixed) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(arg));
    end function;

    -- Format -----------------------------------------------------------------

    function align(arg : ufixed; left, right : integer) return ufixed is
        variable res : ufixed(left downto right);
    begin
        assert left >= arg'left and right <= arg'right
            report "ufixed_pkg.align: target range narrower than argument" severity failure;
        res(arg'left downto arg'right) := arg;
        if left > arg'left then
            res(left downto arg'left + 1) := (others => '0');    -- zero extension
        end if;
        if right < arg'right then
            res(arg'right - 1 downto right) := (others => '0');  -- zero padding
        end if;
        return res;
    end function;

    function resize(arg : ufixed; left, right : integer) return ufixed is
        constant AL : integer := maximum(left, arg'left);
        constant AR : integer := minimum(right, arg'right);
        variable a  : ufixed(AL downto AR);
    begin
        assert left >= right
            report "ufixed_pkg.resize: null or ascending range" severity failure;
        -- Pad to cover both ranges, then keep (left downto right): dropping
        -- MSBs wraps, dropping LSBs truncates
        a := align(arg, AL, AR);
        return a(left downto right);
    end function;

    function resize(arg : ufixed; size_res : ufixed) return ufixed is
    begin
        return resize(arg, size_res'left, size_res'right);
    end function;

    function align_left(l, r : ufixed) return integer is
    begin
        return maximum(l'left, r'left);
    end function;

    function align_right(l, r : ufixed) return integer is
    begin
        return minimum(l'right, r'right);
    end function;

    function mult_left(l, r : ufixed) return integer is
    begin
        return l'left + r'left + 1;
    end function;

    function mult_right(l, r : ufixed) return integer is
    begin
        return l'right + r'right;
    end function;

    -- Arithmetic -------------------------------------------------------------

    function "+" (l, r : ufixed) return ufixed is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : unsigned(AL - AR downto 0);
        variable b  : unsigned(AL - AR downto 0);
    begin
        a := to_unsigned(align(l, AL, AR));
        b := to_unsigned(align(r, AL, AR));
        return to_ufixed(a + b, AL, AR);  -- same width: wraps
    end function;

    function "-" (l, r : ufixed) return ufixed is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : unsigned(AL - AR downto 0);
        variable b  : unsigned(AL - AR downto 0);
    begin
        a := to_unsigned(align(l, AL, AR));
        b := to_unsigned(align(r, AL, AR));
        return to_ufixed(a - b, AL, AR);  -- same width: wraps
    end function;

    function "*" (l, r : ufixed) return ufixed is
        variable p : unsigned(l'length + r'length - 1 downto 0);
    begin
        p := to_unsigned(l) * to_unsigned(r);
        return to_ufixed(p, mult_left(l, r), mult_right(l, r));
    end function;

    -- Comparison -------------------------------------------------------------

    function "=" (l, r : ufixed) return boolean is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : unsigned(AL - AR downto 0);
        variable b  : unsigned(AL - AR downto 0);
    begin
        a := to_unsigned(align(l, AL, AR));
        b := to_unsigned(align(r, AL, AR));
        return a = b;
    end function;

    function "/=" (l, r : ufixed) return boolean is
    begin
        return not (l = r);
    end function;

    function "<" (l, r : ufixed) return boolean is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : unsigned(AL - AR downto 0);
        variable b  : unsigned(AL - AR downto 0);
    begin
        a := to_unsigned(align(l, AL, AR));
        b := to_unsigned(align(r, AL, AR));
        return a < b;
    end function;

    function "<=" (l, r : ufixed) return boolean is
    begin
        return not (r < l);
    end function;

    function ">" (l, r : ufixed) return boolean is
    begin
        return r < l;
    end function;

    function ">=" (l, r : ufixed) return boolean is
    begin
        return not (l < r);
    end function;

end package body ufixed_pkg;
