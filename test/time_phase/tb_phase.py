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

F_CLK = 50e6  # must match board.vhd
T_CLK_R = -40  # must match phase.vhd (T_CLK_L - W_T_CLK)
CLK_MULT = int(os.environ["CLK_MULT"])  # must match the CLK_MULT generic set by tb_run.py

F_DUT = F_CLK * CLK_MULT  # DUT clock frequency
CLK_PERIOD_PS = round(1e12 / F_DUT)

FREQ = 50_000  # [Hz] -> one phase cycle every F_DUT / FREQ clocks
N_PER = round(F_DUT / FREQ)  # clocks per phase cycle (1000 at CLK_MULT=1)
N_CYCLES = int(2.5 * N_PER)

W_LOW = 16  # phase_low_o fractional bits (UQ0.16)
LSB = 2.0**-W_LOW  # phase_low_o LSB [cycles]

# Exact clock period vs. the one used by the DUT (rounded to 2**T_CLK_R): the
# relative difference is a constant frequency error, i.e. a phase drift that
# grows linearly with time.
T_CLK_RAW = round(2.0 ** (-T_CLK_R) / F_DUT)
DRIFT_REL = T_CLK_RAW * 2.0**T_CLK_R * F_DUT - 1  # (T_CLK - 1/F_DUT) * F_DUT

# Ideal float phase vs. hw: drift (< half a T_CLK LSB per clock) plus the
# truncation of phase_low_o to W_LOW bits (< 1 LSB).
DRIFT_MAX = FREQ * 2.0 ** (T_CLK_R - 1)  # [cycles / clock]


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

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_PS, unit="ps").start())

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
    high_model, low_model = Phase(f_clk=F_DUT, t_clk_r=T_CLK_R, w_low=W_LOW).step(
        FREQ, N_CYCLES
    )

    # Ideal float phase with the exact clock period.
    phase_ref = n * FREQ / F_DUT
    err = phase_hw - phase_ref  # [cycles]
    tol = n * DRIFT_MAX + LSB

    # Measured drift: slope of the error vs. the ideal phase (least squares),
    # which averages out the phase_low_o truncation.
    drift_meas = np.polyfit(phase_ref, err, 1)[0]

    # --- plot ----------------------------------------------------------------
    fig, axes = plt.subplots(2, 2, figsize=(16, 9), sharex=True)
    fig.suptitle(
        f"phase - freq_i = {FREQ / 1e3:g} kHz, "
        f"clk = {F_DUT / 1e6:g} MHz (CLK_MULT = {CLK_MULT})"
    )

    ax = axes[0, 0]
    ax.set_title("phase_high_o [cycles]")
    ax.step(n, high_hw, "-r", where="post", linewidth=0.8, label="hw")
    ax.plot(n, np.floor(phase_ref), "--b", linewidth=0.8, label="ideal")
    ax.legend()

    ax = axes[1, 0]
    ax.set_title("phase_low_o [cycles]")
    ax.plot(n, low_hw * LSB, "-r", linewidth=0.8, label="hw")
    ax.plot(n, phase_ref % 1, "--b", linewidth=0.8, label="ideal")
    ax.set_ylim(0, 1)
    ax.legend()

    ax = axes[0, 1]
    ax.set_title("phase error vs. ideal float")
    ax.plot(n, err / LSB, "-g", linewidth=0.8, label="hw - ideal")
    ax.plot(n, phase_ref * DRIFT_REL / LSB, "--k", linewidth=0.8, label="expected drift")
    ax.plot(n, -tol / LSB, ":", color="grey", linewidth=0.8, label="tolerance")
    ax.plot(n, tol / LSB, ":", color="grey", linewidth=0.8)
    ax.set_ylabel("[LSB of phase_low_o = 2^-16 cycles]")
    # Same error as a percentage of one phase cycle (100 % = 360 deg).
    ax.secondary_yaxis(
        "right", functions=(lambda lsb: lsb * LSB * 100, lambda pct: pct / 100 / LSB)
    ).set_ylabel("[% of one cycle]")
    ax.legend(
        title=(
            f"relative drift (freq. error): expected {DRIFT_REL * 100:+.4f} %, "
            f"measured {drift_meas * 100:+.4f} %"
        ),
        loc="best",
    )

    ax = axes[1, 1]
    ax.set_title("phase error vs. model [LSB of phase_low_o]")
    ax.plot(n, (high_hw - high_model) * 2**W_LOW + (low_hw - low_model), "-m", linewidth=0.8)
    ax.set_ylim(-2, 2)

    for ax in axes.flat:
        for k in range(1, N_CYCLES // N_PER + 1):
            ax.axvline(N_PER * k, color="grey", linewidth=0.6, linestyle="--")
        ax.set_xlabel("Clock cycles")
        ax.ticklabel_format(axis="y", useOffset=False, style="plain")
        ax.grid(which="both")

    fig.tight_layout()
    fig.savefig(res_dir / f"phase_mult_{CLK_MULT}.svg")
    plt.close(fig)

    # --- checks --------------------------------------------------------------
    dut._log.info(
        f"drift: expected {DRIFT_REL * 100:+.6f} %, measured {drift_meas * 100:+.6f} %"
    )
    for i in range(N_CYCLES):
        assert (
            high_hw[i] == high_model[i] and low_hw[i] == low_model[i]
        ), f"cycle {n[i]}: hw=({high_hw[i]}, {low_hw[i]}) model=({high_model[i]}, {low_model[i]})"
        assert (
            abs(err[i]) <= tol[i]
        ), f"cycle {n[i]}: hw={phase_hw[i]} ideal={phase_ref[i]} err={err[i]}"
    assert abs(drift_meas - DRIFT_REL) < 0.1 * abs(DRIFT_REL), "measured drift != expected"

    # phase_high_o reaches 1 after N_PER clocks, within one clock due to the
    # T_CLK rounding (low_o wraps at the same instant).
    first_one = n[np.argmax(high_hw >= 1)]
    dut._log.info(f"phase_high_o reached 1 at cycle {first_one} (ideal {N_PER})")
    assert abs(first_one - N_PER) <= 1, f"phase_high_o reached 1 at cycle {first_one}"
    assert low_hw[first_one - 1] < low_hw[first_one - 2], "phase_low_o did not wrap"
