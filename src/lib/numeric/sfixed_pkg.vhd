library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

use work.ufixed_pkg.all;

--! @brief Signed fixed-point type and arithmetic, synthesizable in Quartus
--!        Prime Standard (replacement for the unsupported ieee.fixed_pkg).
--!
--! The format is carried by the index range, as in ieee.fixed_pkg:
--! sfixed(L downto R) is a two's complement number of L-R+1 bits with value
--! raw * 2**R. Index L is the sign bit; R may be negative (fractional bits)
--! or positive, e.g. Q1.15 = sfixed(0 downto -15), Q8.8 = sfixed(7 downto -8).
--!
--! Rules (all operations are implemented on numeric_std signed):
--!  - align: lossless padding to a wider range (sign extension on the left,
--!    zeros on the right). Every two-operand operation first aligns both
--!    operands to the common range (max L downto min R).
--!  - "+", "-": no growth. Result range is the common range; overflow wraps.
--!  - "*": full precision, result range (L1+L2+1 downto R1+R2), i.e. the
--!    same width as the signed multiplication of the raw operands (no
--!    padding). Never wraps.
--!  - Comparisons: exact, on the aligned operands.
--!  - resize: wrap on the left (drop MSBs), truncate on the right (drop LSBs,
--!    i.e. round towards -inf).
--!
--! The unsigned type ufixed and the integer maximum/minimum are in
--! ufixed_pkg; this package only converts ufixed to sfixed (to_sfixed
--! prepends a '0' sign bit).
--!
--! @note Ranges must be descending (L >= R).
--! @note to_sfixed(signed/std_logic_vector, ...) reinterprets the raw bits
--!       (unlike ieee.fixed_pkg, where a signed argument is an integer value).
package sfixed_pkg is

    --! Signed fixed-point number, value = raw * 2**'right.
    type sfixed is array (integer range <>) of std_logic;

    --! Raw bits to sfixed(left downto right); arg'length must be left-right+1.
    function to_sfixed(arg : signed; left, right : integer) return sfixed;
    function to_sfixed(arg : std_logic_vector; left, right : integer) return sfixed;
    function to_sfixed(arg : signed; size_res : sfixed) return sfixed;
    function to_sfixed(arg : std_logic_vector; size_res : sfixed) return sfixed;

    --! Real value to sfixed(left downto right), rounded to nearest (ties away
    --! from zero). For constants only (not synthesizable on signals). Fails
    --! if out of range or if the raw value (value / LSB) needs more than a
    --! 32-bit integer.
    function to_sfixed(arg : real; left, right : integer) return sfixed;
    function to_sfixed(arg : real; size_res : sfixed) return sfixed;

    --! Raw bits of arg, (arg'length-1 downto 0).
    function to_signed(arg : sfixed) return signed;
    function to_slv(arg : sfixed) return std_logic_vector;

    --! ufixed to sfixed(arg'left+1 downto arg'right): '0' prepended, same value.
    function to_sfixed(arg : ufixed) return sfixed;

    --! Lossless padding to (left downto right): requires left >= arg'left and
    --! right <= arg'right.
    function align(arg : sfixed; left, right : integer) return sfixed;

    --! Change format: wrap on the left, truncate on the right.
    function resize(arg : sfixed; left, right : integer) return sfixed;
    function resize(arg : sfixed; size_res : sfixed) return sfixed;

    --! Common range of two operands: max(l'left, r'left), min(l'right, r'right).
    function align_left(l, r : sfixed) return integer;
    function align_right(l, r : sfixed) return integer;

    --! Product range: (l'left + r'left + 1 downto l'right + r'right).
    --! Only the ranges of l and r are used: pass constants (format templates)
    --! when declaring signals, since Questa warns (vcom-1013) on signals.
    function mult_left(l, r : sfixed) return integer;
    function mult_right(l, r : sfixed) return integer;

    function "+" (l, r : sfixed) return sfixed;  --!< Common range, wraps.
    function "-" (l, r : sfixed) return sfixed;  --!< Common range, wraps.
    function "-" (arg : sfixed) return sfixed;   --!< Same range, -min wraps to min.
    function "*" (l, r : sfixed) return sfixed;  --!< Full precision, l'length + r'length bits.

    function "="  (l, r : sfixed) return boolean;
    function "/=" (l, r : sfixed) return boolean;
    function "<"  (l, r : sfixed) return boolean;
    function "<=" (l, r : sfixed) return boolean;
    function ">"  (l, r : sfixed) return boolean;
    function ">=" (l, r : sfixed) return boolean;

end package sfixed_pkg;

package body sfixed_pkg is

    -- Conversions ------------------------------------------------------------

    function to_sfixed(arg : signed; left, right : integer) return sfixed is
        variable res : sfixed(left downto right);
    begin
        assert arg'length = res'length
            report "sfixed_pkg.to_sfixed: length mismatch" severity failure;
        res := sfixed(arg);  -- by position
        return res;
    end function;

    function to_sfixed(arg : std_logic_vector; left, right : integer) return sfixed is
    begin
        return to_sfixed(signed(arg), left, right);
    end function;

    function to_sfixed(arg : signed; size_res : sfixed) return sfixed is
    begin
        return to_sfixed(arg, size_res'left, size_res'right);
    end function;

    function to_sfixed(arg : std_logic_vector; size_res : sfixed) return sfixed is
    begin
        return to_sfixed(signed(arg), size_res'left, size_res'right);
    end function;

    function to_sfixed(arg : real; left, right : integer) return sfixed is
        constant W : natural := left - right + 1;
        constant X : real    := arg * 2.0**(-right);  -- value / LSB
    begin
        assert X >= -2.0**(W-1) and X < 2.0**(W-1) - 0.5
            report "sfixed_pkg.to_sfixed: real value out of range" severity failure;
        assert abs(X) < 2.0**31
            report "sfixed_pkg.to_sfixed: raw value exceeds integer range" severity failure;
        return to_sfixed(to_signed(integer(round(X)), W), left, right);
    end function;

    function to_sfixed(arg : real; size_res : sfixed) return sfixed is
    begin
        return to_sfixed(arg, size_res'left, size_res'right);
    end function;

    function to_signed(arg : sfixed) return signed is
        variable v : sfixed(arg'length-1 downto 0);
    begin
        v := arg;  -- by position, natural range for the conversion
        return signed(v);
    end function;

    function to_slv(arg : sfixed) return std_logic_vector is
    begin
        return std_logic_vector(to_signed(arg));
    end function;

    -- From ufixed -------------------------------------------------------------

    function to_sfixed(arg : ufixed) return sfixed is
        variable res : sfixed(arg'left + 1 downto arg'right);
    begin
        res(arg'left + 1)              := '0';  -- sign bit
        res(arg'left downto arg'right) := sfixed(arg);
        return res;
    end function;

    -- Format -----------------------------------------------------------------

    function align(arg : sfixed; left, right : integer) return sfixed is
        variable res : sfixed(left downto right);
    begin
        assert left >= arg'left and right <= arg'right
            report "sfixed_pkg.align: target range narrower than argument" severity failure;
        res(arg'left downto arg'right) := arg;
        if left > arg'left then
            res(left downto arg'left + 1) := (others => arg(arg'left));  -- sign extension
        end if;
        if right < arg'right then
            res(arg'right - 1 downto right) := (others => '0');          -- zero padding
        end if;
        return res;
    end function;

    function resize(arg : sfixed; left, right : integer) return sfixed is
        constant AL : integer := maximum(left, arg'left);
        constant AR : integer := minimum(right, arg'right);
        variable a  : sfixed(AL downto AR);
    begin
        assert left >= right
            report "sfixed_pkg.resize: null or ascending range" severity failure;
        -- Pad to cover both ranges, then keep (left downto right): dropping
        -- MSBs wraps, dropping LSBs truncates
        a := align(arg, AL, AR);
        return a(left downto right);
    end function;

    function resize(arg : sfixed; size_res : sfixed) return sfixed is
    begin
        return resize(arg, size_res'left, size_res'right);
    end function;

    function align_left(l, r : sfixed) return integer is
    begin
        return maximum(l'left, r'left);
    end function;

    function align_right(l, r : sfixed) return integer is
    begin
        return minimum(l'right, r'right);
    end function;

    function mult_left(l, r : sfixed) return integer is
    begin
        return l'left + r'left + 1;
    end function;

    function mult_right(l, r : sfixed) return integer is
    begin
        return l'right + r'right;
    end function;

    -- Arithmetic -------------------------------------------------------------

    function "+" (l, r : sfixed) return sfixed is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : signed(AL - AR downto 0);
        variable b  : signed(AL - AR downto 0);
    begin
        a := to_signed(align(l, AL, AR));
        b := to_signed(align(r, AL, AR));
        return to_sfixed(a + b, AL, AR);  -- same width: wraps
    end function;

    function "-" (l, r : sfixed) return sfixed is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : signed(AL - AR downto 0);
        variable b  : signed(AL - AR downto 0);
    begin
        a := to_signed(align(l, AL, AR));
        b := to_signed(align(r, AL, AR));
        return to_sfixed(a - b, AL, AR);  -- same width: wraps
    end function;

    function "-" (arg : sfixed) return sfixed is
    begin
        return to_sfixed(-to_signed(arg), arg'left, arg'right);
    end function;

    function "*" (l, r : sfixed) return sfixed is
        variable p : signed(l'length + r'length - 1 downto 0);
    begin
        p := to_signed(l) * to_signed(r);
        return to_sfixed(p, mult_left(l, r), mult_right(l, r));
    end function;

    -- Comparison -------------------------------------------------------------

    function "=" (l, r : sfixed) return boolean is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : signed(AL - AR downto 0);
        variable b  : signed(AL - AR downto 0);
    begin
        a := to_signed(align(l, AL, AR));
        b := to_signed(align(r, AL, AR));
        return a = b;
    end function;

    function "/=" (l, r : sfixed) return boolean is
    begin
        return not (l = r);
    end function;

    function "<" (l, r : sfixed) return boolean is
        constant AL : integer := align_left(l, r);
        constant AR : integer := align_right(l, r);
        variable a  : signed(AL - AR downto 0);
        variable b  : signed(AL - AR downto 0);
    begin
        a := to_signed(align(l, AL, AR));
        b := to_signed(align(r, AL, AR));
        return a < b;
    end function;

    function "<=" (l, r : sfixed) return boolean is
    begin
        return not (r < l);
    end function;

    function ">" (l, r : sfixed) return boolean is
    begin
        return r < l;
    end function;

    function ">=" (l, r : sfixed) return boolean is
    begin
        return not (l < r);
    end function;

end package body sfixed_pkg;
