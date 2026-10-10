from dataclasses import dataclass


def wrap(raw, width):
    """Two's complement wrap of an integer to width bits (signed result)."""
    raw &= (1 << width) - 1
    return raw - (1 << width) if raw >> (width - 1) else raw


@dataclass(frozen=True)
class Fx:
    """Integer model of sfixed_pkg's sfixed(left downto right).

    value = raw * 2**right, raw is a signed integer of left-right+1 bits.
    Mirrors the package rules, not its implementation: + and - on the common
    range without growth (wrap), * at full precision, resize wraps on the
    left and truncates (floor) on the right.
    """

    raw: int
    left: int
    right: int

    @property
    def width(self):
        return self.left - self.right + 1

    @property
    def value(self):
        return self.raw * 2.0**self.right

    @classmethod
    def from_bits(cls, bits, left, right):
        """Raw (unsigned) bit pattern, as read from a port."""
        return cls(wrap(bits, left - right + 1), left, right)

    def bits(self):
        """Unsigned bit pattern, as compared against a port."""
        return self.raw & ((1 << self.width) - 1)

    def resize(self, left, right):
        # Python >> floors, i.e. truncates towards -inf like dropping LSBs
        shift = right - self.right
        raw = self.raw >> shift if shift >= 0 else self.raw << -shift
        return Fx(wrap(raw, left - right + 1), left, right)

    def align(self, other):
        """Both operands on the common range (lossless)."""
        left, right = max(self.left, other.left), min(self.right, other.right)
        return self.resize(left, right), other.resize(left, right)

    def __add__(self, other):
        a, b = self.align(other)
        return Fx(a.raw + b.raw, a.left, a.right).resize(a.left, a.right)

    def __sub__(self, other):
        a, b = self.align(other)
        return Fx(a.raw - b.raw, a.left, a.right).resize(a.left, a.right)

    def __mul__(self, other):
        # Width = self.width + other.width, as a signed multiplication
        return Fx(
            self.raw * other.raw, self.left + other.left + 1, self.right + other.right
        )

    def cmp(self, other):
        """-1, 0, +1 for self <, ==, > other."""
        a, b = self.align(other)
        return (a.raw > b.raw) - (a.raw < b.raw)
