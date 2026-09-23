import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display inside the simulator's embedded interpreter
import matplotlib.pyplot as plt
import numpy as np

import cocotb
from cocotb.clock import Clock

from mod_sincos import SinCos

CLK_PERIOD_NS = 20

W_ROM = 5  # first-quadrant LUT address width, must match sincos.vhd
Q_OUT = 14  # sin_o/cos_o fractional bits (Q2.14)
W_ANGLE = 16  # angle_i / sin_o,cos_o format: Q0.16 BAM in, Q2.14 out

# Tolerance for the LUT + linear-interpolation approximation, not a bit-exact
# match: max curvature error over one LUT segment (360 / (4 * 2**W_ROM) degrees)
# is on the order of a few LSBs at Q2.14.
MAX_ERR_LSB = 10
TOL = MAX_ERR_LSB / 2**Q_OUT


def to_bam(angle_deg: float) -> int:
    """Encode an angle in degrees as Q0.16 BAM (angle_i format)."""
    return round(((angle_deg % 360) / 360) * 2**16) & 0xFFFF


def to_float(raw_signed: int) -> float:
    """Decode a Q2.14 signed raw value (sin_o/cos_o format) to float."""
    return raw_signed / 2**Q_OUT


async def reset(dut):
    dut.rst_n.value = 0
    dut.en_i.value = 0
    dut.angle_i.value = 0

    # Hold reset well past the pipeline depth: the very first rising edge
    # coincides with the clock starting, so the first reset cycle can race
    # with it and not reliably clear the pipeline registers.
    for _ in range(8):
        await dut.clk.rising_edge

    assert dut.done_o.value == 0

    dut.rst_n.value = 1
    await dut.clk.rising_edge


@cocotb.test()
async def tb_sincos(dut):
    this_dir = Path(__file__).parent
    res_dir = this_dir / "results"
    os.makedirs(res_dir, exist_ok=True)

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    await reset(dut)

    # Split [0, 360] into LUT-aligned segments so the sweep lands exactly on
    # every LUT node, then oversample each segment to also exercise the
    # interpolation between nodes.
    N_SEG = 4 * 2**W_ROM + 1
    OVERSAMPLE = 5
    n_pts = (N_SEG - 1) * OVERSAMPLE + 1
    angles = np.linspace(0, 360, n_pts)
    bams = np.empty(n_pts, dtype=np.int64)
    sin_hw = np.empty(n_pts)
    cos_hw = np.empty(n_pts)

    for i, angle in enumerate(angles):
        bam = to_bam(angle)
        bams[i] = bam
        dut.angle_i.value = bam
        dut.en_i.value = 1
        await dut.clk.rising_edge
        dut.en_i.value = 0
        await dut.done_o.rising_edge

        sin_hw[i] = to_float(dut.sin_o.value.to_signed())
        cos_hw[i] = to_float(dut.cos_o.value.to_signed())

    sin_ref = np.sin(np.radians(angles))
    cos_ref = np.cos(np.radians(angles))

    # Bit-accurate model of the DUT's own LUT + linear-interpolation algorithm
    # (quantized table, quantized angle, truncating interpolation -- see
    # mod_sincos.py). Fed the *exact* BAM values driven into angle_i (not the
    # original float angles) so the model sees what the DUT saw; a correct
    # DUT should match this exactly, isolating real bugs from the LUT's
    # inherent approximation error (which shows up against sin_ref/cos_ref
    # instead).
    model = SinCos(w_angle=W_ANGLE, w_lut=W_ROM)
    sin_model, cos_model = model.step_bam(bams)

    # --- plot ----------------------------------------------------------------
    fig, axes = plt.subplots(2, 3, figsize=(20, 9))
    fig.suptitle("sincos — sweep 0°..360°")

    for row, (hw, ref, model_v, name) in enumerate(
        [
            (sin_hw, sin_ref, sin_model, "sin"),
            (cos_hw, cos_ref, cos_model, "cos"),
        ]
    ):
        ax_out, ax_err_float, ax_err_model = axes[row]

        ax_out.set_title(f"{name} — output")
        ax_out.plot(angles, ref, "-b", linewidth=0.8, label="ideal")
        ax_out.plot(angles, hw, "-r", linewidth=0.8, label="hw")
        ax_out.legend()

        ax_err_float.set_title(f"{name} — LSB error vs. ideal float")
        ax_err_float.plot(angles, (hw - ref) * 2**Q_OUT, "-g", linewidth=0.8)

        ax_err_model.set_title(f"{name} — LSB error vs. quantized model")
        ax_err_model.plot(angles, (hw - model_v) * 2**Q_OUT, "-m", linewidth=0.8)

        for ax in (ax_out, ax_err_float, ax_err_model):
            ax.set_xlabel("Angle [deg]")
            ax.grid(which="both")

    fig.tight_layout()
    fig.savefig(res_dir / "sincos.svg")
    plt.close(fig)

    for i, angle in enumerate(angles):
        assert (
            abs(sin_hw[i] - sin_ref[i]) < TOL
        ), f"angle={angle}: sin ref={sin_ref[i]} hw={sin_hw[i]} err={sin_hw[i] - sin_ref[i]}"
        assert (
            abs(cos_hw[i] - cos_ref[i]) < TOL
        ), f"angle={angle}: cos ref={cos_ref[i]} hw={cos_hw[i]} err={cos_hw[i] - cos_ref[i]}"
