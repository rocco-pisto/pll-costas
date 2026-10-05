import numpy as np


class Phase(object):
    """Integer model of phase.vhd's phase accumulator.

    The accumulator holds the phase in cycles as an unsigned integer in units
    of 2**t_clk_l (UQ32.-t_clk_l). Each clock it adds freq * T_CLK, where
    T_CLK is 1/f_clk rounded to 2**t_clk_l -- same rounding as board.vhd.
    """

    def __init__(self, f_clk=50e6, t_clk_l=-40):
        self.frac = -t_clk_l  # accumulator fractional bits
        self.t_clk = int(round(2**self.frac / f_clk))  # raw T_CLK

    def step(self, freq, n_cycles):
        """Phase after 1..n_cycles clocks at constant freq.

        Returns (phase_high, phase_low) as raw integers: UQ32.0 and UQ0.32.
        """
        n = np.arange(1, n_cycles + 1, dtype=object)  # object: exact big ints
        phi = (n * (freq * self.t_clk)) % 2 ** (32 + self.frac)
        phase_high = np.array([int(p) >> self.frac for p in phi], dtype=np.int64)
        phase_low = np.array(
            [(int(p) >> (self.frac - 32)) & 0xFFFFFFFF for p in phi], dtype=np.int64
        )
        return phase_high, phase_low
