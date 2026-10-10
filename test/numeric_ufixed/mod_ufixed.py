from dataclasses import dataclass


@dataclass(frozen=True)
class Ux:
    """Integer model of ufixed_pkg's ufixed(left downto right).

    value = raw * 2**right, raw is an unsigned integer of left-right+1 bits.
    Mirrors the package rules, not its implementation: + and - on the common
    range without growth (wrap modulo 2**width), * at full precision, resize
    wraps on the left and truncates on the right.
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

    def wrapped(self):
        return Ux(self.raw & ((1 << self.width) - 1), self.left, self.right)

    def resize(self, left, right):
        shift = right - self.right
        raw = self.raw >> shift if shift >= 0 else self.raw << -shift
        return Ux(raw, left, right).wrapped()

    def align(self, other):
        """Both operands on the common range (lossless)."""
        left, right = max(self.left, other.left), min(self.right, other.right)
        return self.resize(left, right), other.resize(left, right)

    def __add__(self, other):
        a, b = self.align(other)
        return Ux(a.raw + b.raw, a.left, a.right).wrapped()

    def __sub__(self, other):
        a, b = self.align(other)
        return Ux(a.raw - b.raw, a.left, a.right).wrapped()

    def __mul__(self, other):
        # Width = self.width + other.width, as an unsigned multiplication
        return Ux(
            self.raw * other.raw, self.left + other.left + 1, self.right + other.right
        )

    def cmp(self, other):
        """-1, 0, +1 for self <, ==, > other."""
        a, b = self.align(other)
        return (a.raw > b.raw) - (a.raw < b.raw)
