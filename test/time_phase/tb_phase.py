import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display inside the simulator's embedded interpreter
import matplotlib.pyplot as plt
import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly

from mod_phase import Phase

CLK_PERIOD_NS = 20
F_CLK = 50e6  # must match board.vhd
T_CLK_L = -40  # must match board.vhd

FREQ = 50_000  # [Hz] -> one phase cycle every F_CLK / FREQ = 1000 clocks
N_CYCLES = 2500

# phase_high_o + phase_low_o * 2**-32 vs. ideal float phase: T_CLK is rounded
# to 2**T_CLK_L, so the drift grows linearly by up to FREQ * 2**(T_CLK_L-1)
# cycles per clock, plus 1 LSB of phase_low_o truncation.
LSB = 2**-32


async def reset(dut):
    dut.rst_n.value = 0
    dut.freq_i.value = FREQ

    for _ in range(8):
        await dut.clk.rising_edge

    await ReadOnly()
    assert dut.phase_high_o.value == 0
    assert dut.phase_low_o.value == 0

    await dut.clk.rising_edge
    dut.rst_n.value = 1


@cocotb.test()
async def tb_phase(dut):
    this_dir = Path(__file__).parent
    res_dir = this_dir / "results"
    os.makedirs(res_dir, exist_ok=True)

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    await reset(dut)

    # Sample after each rising edge once the registers have settled: sample
    # n (1-based) is the phase after n accumulations.
    high_hw = np.empty(N_CYCLES, dtype=np.int64)
    low_hw = np.empty(N_CYCLES, dtype=np.int64)
    for i in range(N_CYCLES):
        await dut.clk.rising_edge
        await ReadOnly()
        high_hw[i] = dut.phase_high_o.value.to_unsigned()
        low_hw[i] = dut.phase_low_o.value.to_unsigned()

    n = np.arange(1, N_CYCLES + 1)
    phase_hw = high_hw + low_hw * LSB

    # Bit-accurate model: must match exactly.
    high_model, low_model = Phase(f_clk=F_CLK, t_clk_l=T_CLK_L).step(FREQ, N_CYCLES)
    phase_model = high_model + low_model * LSB

    # Ideal float phase with exact 1/F_CLK.
    phase_ref = n * FREQ / F_CLK
    tol = n * FREQ * 2.0 ** (T_CLK_L - 1) + LSB

    # --- plot ----------------------------------------------------------------
    fig, axes = plt.subplots(2, 2, figsize=(16, 9), sharex=True)
    fig.suptitle(f"phase — freq_i = {FREQ} Hz, F_CLK = {F_CLK / 1e6:g} MHz")

    ax = axes[0, 0]
    ax.set_title("phase_high_o [cycles]")
    ax.step(n, high_hw, "-r", where="post", linewidth=0.8, label="hw")
    ax.plot(n, np.floor(phase_ref), "--b", linewidth=0.8, label="ideal")
    ax.legend()

    ax = axes[1, 0]
    ax.set_title("phase_low_o [cycles]")
    ax.plot(n, low_hw * LSB, "-r", linewidth=0.8, label="hw")
    ax.plot(n, phase_ref % 1, "--b", linewidth=0.8, label="ideal")
    ax.legend()

    ax = axes[0, 1]
    ax.set_title("phase error vs. ideal float [LSB of phase_low_o]")
    ax.plot(n, (phase_hw - phase_ref) / LSB, "-g", linewidth=0.8, label="hw - ideal")
    ax.plot(n, -tol / LSB, ":k", linewidth=0.8, label="tolerance")
    ax.plot(n, tol / LSB, ":k", linewidth=0.8)
    # Same error as a percentage of one phase cycle (360 deg).
    ax.secondary_yaxis(
        "right", functions=(lambda lsb: lsb * LSB * 100, lambda pct: pct / 100 / LSB)
    ).set_ylabel("[% of cycle]")
    # Relative drift: constant, since the T_CLK rounding is a frequency error.
    drift_pct = (phase_hw[-1] - phase_ref[-1]) / phase_ref[-1] * 100
    ax.plot([], [], " ", label=f"drift = {drift_pct:.3e} % of phase")
    ax.legend()

    ax = axes[1, 1]
    ax.set_title("phase error vs. model [LSB of phase_low_o]")
    ax.plot(n, (phase_hw - phase_model) / LSB, "-m", linewidth=0.8)

    for ax in axes.flat:
        for k in range(1, N_CYCLES // 1000 + 1):
            ax.axvline(1000 * k, color="grey", linewidth=0.6, linestyle="--")
        ax.set_xlabel("Clock cycles")
        ax.grid(which="both")

    fig.tight_layout()
    fig.savefig(res_dir / "phase.svg")
    plt.close(fig)

    # --- checks --------------------------------------------------------------
    for i in range(N_CYCLES):
        assert (
            high_hw[i] == high_model[i] and low_hw[i] == low_model[i]
        ), f"cycle {n[i]}: hw=({high_hw[i]}, {low_hw[i]}) model=({high_model[i]}, {low_model[i]})"
        assert (
            abs(phase_hw[i] - phase_ref[i]) <= tol[i]
        ), f"cycle {n[i]}: hw={phase_hw[i]} ideal={phase_ref[i]} err={phase_hw[i] - phase_ref[i]}"

    # phase_high_o reaches 1 after F_CLK / FREQ = 1000 clocks, within one
    # clock due to the T_CLK rounding (low_o wraps at the same instant).
    first_one = n[np.argmax(high_hw >= 1)]
    dut._log.info(f"phase_high_o reached 1 at cycle {first_one}")
    assert abs(first_one - F_CLK / FREQ) <= 1, f"phase_high_o reached 1 at cycle {first_one}"
    assert low_hw[first_one - 1] < low_hw[first_one - 2], "phase_low_o did not wrap"
