"""Testbench for ufixed_pkg (src/lib/numeric/ufixed_pkg.vhd).

Same structure as test/numeric_sfixed, for the unsigned type. The package has
no ports of its own, so the DUT is the harness ufixed_ops.vhd: a combinational
entity that takes two raw operands a_i, b_i and brings out a + b, a - b,
a * b, resize(a * b) and the six comparisons.

tb_run.py runs this test once per operand format (generics of ufixed_ops):

  aligned     a, b = ufixed(-1 downto -16) (UQ0.16), resize to UQ0.16.
              Same ranges: + and - are a plain wrapping unsigned add/sub.
  misaligned  a = ufixed(3 downto -4), b = ufixed(1 downto -6), resize to
              ufixed(2 downto -3). Different ranges on both sides: + and - and
              the comparisons must pad b on the left and a on the right with
              zeros before operating.
  integer     a = ufixed(7 downto 0), b = ufixed(5 downto 0), resize to
              ufixed(6 downto 1): no fractional bits; the resize target has a
              positive right index (drops the LSB, i.e. floor(x / 2)).
  fractional  a = ufixed(-1 downto -8), b = ufixed(-3 downto -10), resize to
              ufixed(-4 downto -12): no integer bits, the MSB itself has a
              negative index (value < 0.5 and < 0.125).
  int_frac    a = ufixed(5 downto 0) integer, b = ufixed(-2 downto -9) purely
              fractional: disjoint ranges, so the common range of + and - is
              (5 downto -9) and both operands get padded.

What is checked, for every operand pair, against the integer model
mod_ufixed.Ux (bit exact, no tolerance):

  sum_o, diff_o  a + b and a - b on the common range (max L downto min R),
                 no extra bit: overflow and negative differences must wrap.
  eq_o .. ge_o   =, /=, <, <=, >, >= on the exact values.
  prod_o         a * b at full precision, (A_L+B_L+1 downto A_R+B_R): the
                 same width as the unsigned multiplication of the raw operands.
  rsz_o          resize(a * b) to (RS_L downto RS_R): MSBs dropped (wrap),
                 LSBs dropped (truncation).

Operand pairs:

  corners  every pair of 0, 1 LSB, max, max - 1 LSB, MSB only, MSB - 1 LSB:
           hits wrap-around of + and -, the max * max product and the
           comparison of the extremes.
  random   N_RANDOM uniformly random raw operands.
  equal    pairs with a = b in value (a moved into b's format, kept only when
           exact), so that =, <= and >= are also seen true for misaligned
           operands.
"""

import json
import os
import random

import cocotb
from cocotb.triggers import Timer

from mod_ufixed import Ux

# Formats set by tb_run.py (must match the generics of ufixed_ops)
CFG = json.loads(os.environ["UFIXED_CFG"])
A_L, A_R = CFG["A_L"], CFG["A_R"]
B_L, B_R = CFG["B_L"], CFG["B_R"]
RS_L, RS_R = CFG["RS_L"], CFG["RS_R"]
NAME = CFG["name"]

N_RANDOM = 2000


def corners(width):
    """Raw bit patterns: 0, 1 LSB, max, max - 1 LSB, MSB only, MSB - 1 LSB."""
    hi, msb = (1 << width) - 1, 1 << (width - 1)
    return [0, 1, hi, hi - 1, msb, msb - 1]


@cocotb.test()
async def tb_ufixed(dut):
    w_a, w_b = A_L - A_R + 1, B_L - B_R + 1
    assert len(dut.a_i) == w_a and len(dut.b_i) == w_b

    rng = random.Random(0)
    pairs = [(a, b) for a in corners(w_a) for b in corners(w_b)]
    pairs += [(rng.getrandbits(w_a), rng.getrandbits(w_b)) for _ in range(N_RANDOM)]
    for a_bits, _ in pairs[:500]:
        a = Ux(a_bits, A_L, A_R)
        b = a.resize(B_L, B_R)
        if a.cmp(b) == 0:
            pairs.append((a_bits, b.raw))

    n_equal = 0
    for a_bits, b_bits in pairs:
        dut.a_i.value = a_bits
        dut.b_i.value = b_bits
        await Timer(1, unit="ns")  # combinational DUT: let it settle

        a = Ux(a_bits, A_L, A_R)
        b = Ux(b_bits, B_L, B_R)
        p = a * b
        expected = {
            "sum_o": (a + b).raw,
            "diff_o": (a - b).raw,
            "prod_o": p.raw,
            "rsz_o": p.resize(RS_L, RS_R).raw,
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
