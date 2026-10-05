import numpy as np


class SinCos(object):
    """Quantized model of sincos.vhd's LUT + linear-interpolation algorithm.

    A flat, correctly-signed full-circle table (90/180/270/360 degrees fall
    exactly on the grid, so no special-casing is needed there), quantized to
    the DUT's Q1.q_out precision same as the .mif ROM contents -- including
    saturation, since +1.0 overflows a Q1.q_out signed value and the DUT
    clips it to the max representable value (1 - 1 LSB) instead -- queried
    at the DUT's own Q0.w_angle BAM angle precision, via plain linear
    interpolation.

    Not quite bit-exact: the RTL truncates its interpolated result *before*
    applying the quadrant sign flip, which can differ from a plain
    interpolation of already-signed values by up to 1 LSB on the sign-
    flipped quadrants. That's a deterministic RTL truncation-order artifact,
    not a bug, and not worth chasing here in exchange for a simple model.
    """

    def __init__(self, w_angle, w_lut, q_out):
        self.w_angle = w_angle
        self.w_lut = w_lut
        self.q_out = q_out  # sin_o/cos_o fractional bits (Q1.q_out)

        n_lut = 4 * 2**w_lut  # full-circle table entries (128 for w_lut=5)
        scale = 2**self.q_out

        # n_lut+1 points (0..360 inclusive) so interpolation wraps correctly
        # instead of clamping the last partial segment before 360.
        self.angle_lut = np.arange(n_lut + 1) * (360.0 / n_lut)
        # Round and saturate to the DUT's Q1.q_out precision -- same as the
        # .mif generator (test/lib/mif.py) does for the ROM contents.
        sin_raw = np.round(np.sin(np.deg2rad(self.angle_lut)) * scale)
        cos_raw = np.round(np.cos(np.deg2rad(self.angle_lut)) * scale)
        self.sin_lut = np.clip(sin_raw, -scale + 1, scale - 1) / scale
        self.cos_lut = np.clip(cos_raw, -scale + 1, scale - 1) / scale

    def to_bam(self, angle):
        """Quantize angle(s) in degrees to the DUT's Q0.w_angle BAM input."""
        bam = np.round(
            (np.asarray(angle, dtype=np.float64) % 360) / 360 * 2**self.w_angle
        )
        return bam.astype(np.int64) & (2**self.w_angle - 1)

    def step_bam(self, bam):
        """Evaluate sin/cos for an already-quantized BAM angle (int or array).

        Use this (instead of step()) when the caller already computed the
        exact BAM value driven into angle_i, so the model sees the identical
        quantized angle the DUT does rather than re-deriving its own.
        """
        angle = np.asarray(bam, dtype=np.float64) / 2**self.w_angle * 360
        sin_v = np.interp(angle, self.angle_lut, self.sin_lut)
        cos_v = np.interp(angle, self.angle_lut, self.cos_lut)
        return sin_v, cos_v

    def step(self, angle):
        """Evaluate sin/cos for angle(s) in degrees, quantizing internally.

        Convenience wrapper around to_bam() + step_bam(); prefer step_bam()
        directly when the exact BAM value driven into the DUT is available.
        """
        return self.step_bam(self.to_bam(angle))

    def to_value(self, int_value):
        # sin/cos from Q1.q_out to float
        return int_value / (2**self.q_out)
