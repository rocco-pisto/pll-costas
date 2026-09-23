import numpy as np


class SinCos(object):
    def __init__(self, w_angle, w_lut):
        self.w_angle = w_angle
        self.w_lut = w_lut
        lut_n = 2**w_lut
        tot_n = 4 * lut_n
        self.angle_lut = np.arange(tot_n, dtype=np.uint32) * (360 // tot_n)
        self.sin_lut = np.sin(np.deg2rad(self.angle_lut))
        self.cos_lut = np.cos(np.deg2rad(self.angle_lut))

    def step(self, angle):
        # Normalize angle to [0, 360)
        angle = angle % 360
        # Convert to LUT index
        sin_v = np.interp(angle, self.angle_lut, self.sin_lut)
        cos_v = np.interp(angle, self.angle_lut, self.cos_lut)
        return sin_v, cos_v

    def to_bam(self, angle):
        # Normalize angle to [0, 1)
        bam_float = (angle % 360) / 360
        # Convert to BAM representation
        bam_value = int(bam_float * (2**self.w_angle))
        return bam_value

    def to_value(self, int_value):
        # sin/cos from Q2.W_ANGLE-2 to float
        return int_value / (2 ** (self.w_angle - 2))
