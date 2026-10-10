import sys
from pathlib import Path

from cocotb_tools.runner import VHDL, Questa

TEST_DIR = Path(__file__).resolve().parent
TEST_ROOT = TEST_DIR.parent
PROJECT_DIR = TEST_ROOT.parent

# Make the model and shared helpers importable from the test module,
# regardless of whether PYTHONPATH was picked up from .env.
sys.path.insert(0, str(TEST_DIR))
sys.path.insert(0, str(TEST_ROOT / "lib"))

# CLK_MULT values to test: board clock and pll_200 domain (board.PLL_MULT).
CLK_MULT_LIST = [1, 4]


def test_phase():
    vhdl_sources = [
        PROJECT_DIR / "src" / "conf" / "board.vhd",
        PROJECT_DIR / "src" / "lib" / "numeric" / "ufixed_pkg.vhd",
        PROJECT_DIR / "src" / "lib" / "time" / "phase.vhd",
    ]

    for clk_mult in CLK_MULT_LIST:
        build_dir = TEST_DIR / "sim_build" / f"mult_{clk_mult}"

        runner = Questa()

        runner.build(
            vhdl_sources=vhdl_sources,
            hdl_toplevel="phase",
            build_args=[VHDL("-2008")],
            build_dir=build_dir,
        )

        runner.test(
            hdl_toplevel="phase",
            test_module="tb_phase",
            parameters={"CLK_MULT": clk_mult},
            extra_env={"CLK_MULT": str(clk_mult)},
            test_args=["-t", "ps"],  # ps resolution: 5 ns clock period at CLK_MULT=4
        )


if __name__ == "__main__":
    test_phase()
