import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display inside the simulator's embedded interpreter
import matplotlib.pyplot as plt
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly

from mod_nco import Nco

CLK_PERIOD_NS = 20
F_CLK = 50e6  # must match board.vhd
T_CLK_L = -40  # must match board.vhd
Q_OUT = 15  # sin_o/cos_o fractional bits (Q1.15)

FREQ = 50_000  # [Hz] -> 1000 clocks per output cycle
N_OUT_CYCLES = 3
N_CYCLES = int(N_OUT_CYCLES * F_CLK / FREQ)

# Clocks from the phase accumulator update to sin_o/cos_o: 1 (sincos samples
# phase_low) + 5 (sincos pipeline).
LATENCY = 6

# vs. quantized model: the sincos model is within 1 LSB of the RTL (see
# mod_sincos.py). vs. ideal float: LUT interpolation error (as in
# test/math_sincos) plus the 16-bit phase truncation (2*pi*2**-16 rad ~ 13 LSB
# at Q1.15).
MAX_ERR_MODEL_LSB = 1
MAX_ERR_FLOAT_LSB = 32


def to_float(raw_signed: int) -> float:
    """Decode a Q1.15 signed raw value (sin_o/cos_o format) to float."""
    return raw_signed / 2**Q_OUT


async def reset(dut):
    dut.rst_n.value = 0
    dut.freq_i.value = FREQ

    # Hold reset past the sincos pipeline depth.
    for _ in range(8):
        await dut.clk.rising_edge

    await ReadOnly()
    assert dut.valid_o.value == 0

    await dut.clk.rising_edge
    dut.rst_n.value = 1


@cocotb.test()
async def tb_nco(dut):
    this_dir = Path(__file__).parent
    res_dir = this_dir / "results"
    os.makedirs(res_dir, exist_ok=True)

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    await reset(dut)

    # Sample after each rising edge once the registers have settled. Sample
    # n (1-based) of sin_o/cos_o belongs to the phase after n - LATENCY
    # accumulations; drop the first LATENCY samples (reset phase).
    n_run = N_CYCLES + LATENCY
    sin_hw = np.empty(n_run)
    cos_hw = np.empty(n_run)
    valid_hw = np.empty(n_run, dtype=bool)
    for i in range(n_run):
        await dut.clk.rising_edge
        await ReadOnly()
        valid_hw[i] = dut.valid_o.value == 1
        sin_hw[i] = to_float(dut.sin_o.value.to_signed())
        cos_hw[i] = to_float(dut.cos_o.value.to_signed())

    assert valid_hw[LATENCY - 1 :].all(), "valid_o not continuously high after reset"
    sin_hw = sin_hw[LATENCY:]
    cos_hw = cos_hw[LATENCY:]

    n = np.arange(1, N_CYCLES + 1)
    t_us = n * CLK_PERIOD_NS * 1e-3

    sin_model, cos_model = Nco(f_clk=F_CLK, t_clk_l=T_CLK_L).step(FREQ, N_CYCLES)

    phase_ref = 2 * np.pi * FREQ * n / F_CLK
    sin_ref = np.sin(phase_ref)
    cos_ref = np.cos(phase_ref)

    # --- plot ----------------------------------------------------------------
    fig, axes = plt.subplots(2, 3, figsize=(20, 9), sharex=True)
    fig.suptitle(f"nco — freq_i = {FREQ} Hz, F_CLK = {F_CLK / 1e6:g} MHz")

    for row, (hw, ref, model_v, name) in enumerate(
        [
            (sin_hw, sin_ref, sin_model, "sin"),
            (cos_hw, cos_ref, cos_model, "cos"),
        ]
    ):
        ax_out, ax_err_float, ax_err_model = axes[row]

        ax_out.set_title(f"{name}_o — output")
        ax_out.plot(t_us, ref, "--b", linewidth=0.8, label="ideal")
        ax_out.plot(t_us, hw, "-r", linewidth=0.8, label="hw")
        ax_out.legend()

        ax_err_float.set_title(f"{name}_o — LSB error vs. ideal float")
        ax_err_float.plot(t_us, (hw - ref) * 2**Q_OUT, "-g", linewidth=0.8)

        ax_err_model.set_title(f"{name}_o — LSB error vs. quantized model")
        ax_err_model.plot(t_us, (hw - model_v) * 2**Q_OUT, "-m", linewidth=0.8)

        for ax in (ax_out, ax_err_float, ax_err_model):
            ax.set_xlabel("Time [us]")
            ax.grid(which="both")

    fig.tight_layout()
    fig.savefig(res_dir / "nco.svg")
    plt.close(fig)

    # --- checks --------------------------------------------------------------
    for hw, ref, model_v, name in [
        (sin_hw, sin_ref, sin_model, "sin"),
        (cos_hw, cos_ref, cos_model, "cos"),
    ]:
        err_model = np.abs(hw - model_v) * 2**Q_OUT
        err_float = np.abs(hw - ref) * 2**Q_OUT
        dut._log.info(
            f"{name}: max err vs model {err_model.max():.0f} LSB, "
            f"vs float {err_float.max():.1f} LSB"
        )
        i = np.argmax(err_model)
        assert (
            err_model[i] <= MAX_ERR_MODEL_LSB
        ), f"cycle {n[i]}: {name} hw={hw[i]} model={model_v[i]}"
        i = np.argmax(err_float)
        assert (
            err_float[i] <= MAX_ERR_FLOAT_LSB
        ), f"cycle {n[i]}: {name} hw={hw[i]} ideal={ref[i]}"
