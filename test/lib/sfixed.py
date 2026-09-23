import math


class SFixed:
    def __init__(self, left_index, right_index, value: float = 0, raw: int = None):
        """
        Replicates sfixed(left_index downto right_index).
        Total bits = left_index - right_index + 1
        """
        self.left = left_index
        self.right = right_index
        self.width = left_index - right_index + 1
        self.scale = 2 ** (-right_index)

        if raw is not None:
            self.raw = self.mask(raw)
        elif type(value) is SFixed:
            self.set(value)
        else:
            self.set(float(value))

    def mask(self, val):
        # Handle Two's Complement wrap-around (like VHDL logic)
        mask = (1 << self.width) - 1
        val = val & mask
        # Sign extension
        return int(val)

    def from_float(self, f):
        return int(round(f * self.scale))

    def set(self, val):
        if type(val) is SFixed:
            self.raw = self.mask(self.from_float(val.f))
        else:
            self.raw = self.mask(self.from_float(val))

    @property
    def f(self):
        return self.i / self.scale

    @property
    def i(self):
        i = self.raw
        if i & (1 << (self.width - 1)):
            i -= 1 << self.width
        return i

    @property
    def u(self):
        u = self.raw
        return u

    ## COMPARISON OPERATORS
    def __eq__(self, other):
        # Checks if values are mathematically equal
        val_other = other.f if isinstance(other, SFixed) else other
        return self.f == val_other

    def __lt__(self, other):
        val_other = other.f if isinstance(other, SFixed) else other
        return self.f < val_other

    def __le__(self, other):
        val_other = other.f if isinstance(other, SFixed) else other
        return self.f <= val_other

    def __gt__(self, other):
        val_other = other.f if isinstance(other, SFixed) else other
        return self.f > val_other

    def __ge__(self, other):
        val_other = other.f if isinstance(other, SFixed) else other
        return self.f >= val_other

    def __ne__(self, other):
        return not self.__eq__(other)

    ## ARITHMETICAL OPERATORS
    def __neg__(self):
        return SFixed(self.left, self.right, raw=-self.raw)

    def __add__(self, other):
        # VHDL sfixed addition: result is max(lefts)+1 downto min(rights)
        if type(other) in (int, float):
            other = SFixed(31, 32, other)
        res_left = max(self.left, other.left) + 1
        res_right = min(self.right, other.right)

        # Align decimal points and add
        self_val = self.i << (self.right - res_right)
        other_val = other.i << (other.right - res_right)
        res_val = self_val + other_val
        return SFixed(res_left, res_right, raw=res_val)

    def __sub__(self, other):
        # VHDL sfixed addition: result is max(lefts)+1 downto min(rights)
        if type(other) in (int, float):
            other = SFixed(31, 32, other)
        res_left = max(self.left, other.left) + 1
        res_right = min(self.right, other.right)

        # Align decimal points and subtract
        self_val = self.i << (self.right - res_right)
        other_val = other.i << (other.right - res_right)
        res_val = self_val - other_val
        return SFixed(res_left, res_right, raw=res_val)

    def __mul__(self, other):
        # VHDL sfixed multiplication: result is (L1+L2+1) downto (R1+R2)
        if type(other) in (int, float):
            other = SFixed(31, -32, other)
        res_left = self.left + other.left + 1
        res_right = self.right + other.right

        res_val = self.i * other.i
        return SFixed(res_left, res_right, raw=res_val)

    def __repr__(self):
        return f"sfixed({self.left} downto {self.right}): {self.f} (hex: {self.raw & ((1<<self.width)-1):08X})"

    def resize(self, *args):
        """Equivalent to VHDL's resize() function"""
        if len(args) == 1 and type(args[0]) == SFixed:
            return SFixed(args[0].left, args[0].right, self.f)
        elif len(args) == 2:
            return SFixed(args[0], args[1], self.f)
        else:
            raise Exception("Incorrect use of resize")
