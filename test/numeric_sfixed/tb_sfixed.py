"""Testbench for sfixed_pkg (src/lib/numeric/sfixed_pkg.vhd).

The package has no ports of its own, so the DUT is the harness sfixed_ops.vhd:
a combinational entity that takes two raw operands a_i, b_i and brings out
a + b, a - b, a * b, resize(a * b) and the six comparisons.

tb_run.py runs this test once per operand format (generics of sfixed_ops):

  aligned     a, b = sfixed(0 downto -15) (Q1.15), resize to Q1.15.
              Same ranges: + and - are a plain wrapping signed add/sub.
  misaligned  a = sfixed(3 downto -4), b = sfixed(1 downto -6), resize to
              sfixed(2 downto -3). Different ranges on both sides: + and - and
              the comparisons must align b to a's MSB (sign extension) and a
              to b's LSB (zero padding) before operating.
  integer     a = sfixed(7 downto 0), b = sfixed(5 downto 0), resize to
              sfixed(6 downto 1): no fractional bits; the resize target has a
              positive right index (drops the LSB, i.e. floor(x / 2)).
  fractional  a = sfixed(-1 downto -8), b = sfixed(-3 downto -10), resize to
              sfixed(-4 downto -12): no integer bits, the sign bit itself has
              a negative index (|value| < 0.5 and < 0.125).
  int_frac    a = sfixed(5 downto 0) integer, b = sfixed(-2 downto -9) purely
              fractional: disjoint ranges, so the common range of + and - is
              (5 downto -9) and both operands get padded.

What is checked, for every operand pair, against the integer model
mod_sfixed.Fx (bit exact, no tolerance):

  sum_o, diff_o  a + b and a - b on the common range (max L downto min R),
                 no extra bit: overflow must wrap.
  eq_o .. ge_o   =, /=, <, <=, >, >= on the exact values.
  prod_o         a * b at full precision, (A_L+B_L+1 downto A_R+B_R): the
                 same width as the signed multiplication of the raw operands.
  rsz_o          resize(a * b) to (RS_L downto RS_R): MSBs dropped (wrap),
                 LSBs dropped (truncation towards -inf).
  us_o           to_sfixed(u) for u = ufixed(A_L downto A_R) driven with a's
                 bit patterns: same bits with a '0' sign bit on top, i.e. the
                 same (non-negative) value, also when u's MSB is set.

Operand pairs:

  corners  every pair of 0, +1 LSB, -1 LSB, max, min, min + 1 LSB: hits
           wrap-around of + and -, the min * min product and the comparison
           of the extremes.
  random   N_RANDOM uniformly random raw operands.
  equal    pairs with a = b in value (a rounded into b's format, kept only
           when exact), so that =, <= and >= are also seen true for
           misaligned operands.
"""

import json
import os
import random

import cocotb
from cocotb.triggers import Timer

from mod_sfixed import Fx

# Formats set by tb_run.py (must match the generics of sfixed_ops)
CFG = json.loads(os.environ["SFIXED_CFG"])
A_L, A_R = CFG["A_L"], CFG["A_R"]
B_L, B_R = CFG["B_L"], CFG["B_R"]
RS_L, RS_R = CFG["RS_L"], CFG["RS_R"]
NAME = CFG["name"]

N_RANDOM = 2000


def corners(width):
    """Raw bit patterns: 0, +-1 LSB, max, min, min + 1 LSB."""
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    return [v & ((1 << width) - 1) for v in (0, 1, -1, hi, lo, lo + 1)]


@cocotb.test()
async def tb_sfixed(dut):
    w_a, w_b = A_L - A_R + 1, B_L - B_R + 1
    assert len(dut.a_i) == w_a and len(dut.b_i) == w_b

    rng = random.Random(0)
    pairs = [(a, b) for a in corners(w_a) for b in corners(w_b)]
    pairs += [(rng.getrandbits(w_a), rng.getrandbits(w_b)) for _ in range(N_RANDOM)]
    for a_bits, _ in pairs[:500]:
        a = Fx.from_bits(a_bits, A_L, A_R)
        b = a.resize(B_L, B_R)
        if a.cmp(b) == 0:
            pairs.append((a_bits, b.bits()))

    n_equal = 0
    for a_bits, b_bits in pairs:
        dut.a_i.value = a_bits
        dut.b_i.value = b_bits
        dut.u_i.value = a_bits
        await Timer(1, unit="ns")  # combinational DUT: let it settle

        a = Fx.from_bits(a_bits, A_L, A_R)
        b = Fx.from_bits(b_bits, B_L, B_R)
        p = a * b
        expected = {
            "sum_o": (a + b).bits(),
            "diff_o": (a - b).bits(),
            "prod_o": p.bits(),
            "rsz_o": p.resize(RS_L, RS_R).bits(),
            "us_o": a_bits,  # zero-extended: '0' & u
        }
        c = a.cmp(b)
        n_equal += c == 0
        expected_cmp = {
            "eq_o": c == 0,
            "ne_o": c != 0,
            "lt_o": c < 0,
            "le_o": c <= 0,
            "gt_o": c > 0,
            "ge_o": c >= 0,
        }

        for port, exp in expected.items():
            got = getattr(dut, port).value.to_unsigned()
            assert got == exp, f"{port}: a={a.value} b={b.value} hw={got:#x} model={exp:#x}"
        for port, exp in expected_cmp.items():
            got = getattr(dut, port).value == 1
            assert got == exp, f"{port}: a={a.value} b={b.value} hw={got} model={exp}"

    dut._log.info(f"{NAME}: {len(pairs)} operand pairs ({n_equal} equal) match the model")
