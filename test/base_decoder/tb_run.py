from pathlib import Path

from cocotb_tools.runner import VHDL, Questa

TEST_DIR = Path(__file__).resolve().parent
TEST_ROOT = TEST_DIR.parent
PROJECT_DIR = TEST_ROOT.parent

# N_B values to elaborate and test, one build per generic value.
N_B_LIST = [1, 3, 5]


def test_decoder():
    vhdl_sources = [
        PROJECT_DIR / "src" / "lib" / "base" / "decoder.vhd",
    ]

    for n_b in N_B_LIST:
        build_dir = TEST_DIR / "sim_build" / f"n_b_{n_b}"

        runner = Questa()

        runner.build(
            vhdl_sources=vhdl_sources,
            hdl_toplevel="decoder",
            build_args=[VHDL("-2008")],
            build_dir=build_dir,
        )

        runner.test(
            hdl_toplevel="decoder",
            test_module="tb_decoder",
            parameters={"N_B": n_b},
            extra_env={"N_B": str(n_b)},
        )


if __name__ == "__main__":
    test_decoder()
