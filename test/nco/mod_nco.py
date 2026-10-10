from mod_phase import Phase
from mod_sincos import SinCos


class Nco(object):
    """Model of nco.vhd: phase accumulator followed by the sin/cos generator.

    The fractional phase (phase_low, UQ0.16) is the Q0.16 BAM angle fed to
    the sin/cos model. f_clk is the DUT clock (F_CLK * CLK_MULT). Pipeline
    latency is not modelled.
    """

    def __init__(self, f_clk=50e6, t_clk_r=-40, w_angle=16, w_lut=5):
        self.w_angle = w_angle
        self.phase = Phase(f_clk=f_clk, t_clk_r=t_clk_r, w_low=w_angle)
        self.sincos = SinCos(w_angle=w_angle, w_lut=w_lut, q_out=w_angle - 1)

    def step(self, freq, n_cycles):
        """sin/cos (float) after 1..n_cycles clocks at constant freq."""
        _, bam = self.phase.step(freq, n_cycles)
        return self.sincos.step_bam(bam)
