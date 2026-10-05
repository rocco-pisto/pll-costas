import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")  # no display inside the simulator's embedded interpreter
import matplotlib.pyplot as plt
import numpy as np

import cocotb
from cocotb.triggers import Timer

N_B = int(os.environ["N_B"])  # must match the N_B generic set by tb_run.py


@cocotb.test()
async def tb_decoder(dut):
    this_dir = Path(__file__).parent
    res_dir = this_dir / "results"
    os.makedirs(res_dir, exist_ok=True)

    assert len(dut.num_i) == N_B, f"num_i width {len(dut.num_i)} != N_B={N_B}"
    assert len(dut.dec_o) == 2**N_B, f"dec_o width {len(dut.dec_o)} != 2**N_B"

    # Combinational DUT: no clock/reset, sweep every input value.
    n_in = 2**N_B
    dec_hw = np.empty((n_in, n_in), dtype=np.int64)  # [input, output bit]
    for num in range(n_in):
        dut.num_i.value = num
        await Timer(1, unit="ns")
        dec = dut.dec_o.value.to_unsigned()
        dec_hw[num] = [(dec >> b) & 1 for b in range(n_in)]
        assert dec == 1 << num, f"num_i={num}: dec_o={dec:#x}, expected {1 << num:#x}"

    # --- plot ----------------------------------------------------------------
    fig, ax = plt.subplots(figsize=(6, 6))
    ax.set_title(f"decoder — N_B = {N_B}")
    ax.imshow(dec_hw, cmap="Greys", origin="lower")
    ax.set_xlabel("dec_o bit")
    ax.set_ylabel("num_i")
    fig.tight_layout()
    fig.savefig(res_dir / f"decoder_n_b_{N_B}.svg")
    plt.close(fig)
