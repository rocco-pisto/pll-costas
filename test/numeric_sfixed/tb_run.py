import json
import sys
from pathlib import Path

from cocotb_tools.runner import VHDL, Questa, get_results

TEST_DIR = Path(__file__).resolve().parent
TEST_ROOT = TEST_DIR.parent
PROJECT_DIR = TEST_ROOT.parent

# Make the model and shared helpers importable from the test module,
# regardless of whether PYTHONPATH was picked up from .env.
sys.path.insert(0, str(TEST_DIR))
sys.path.insert(0, str(TEST_ROOT / "lib"))

# Operand / resize formats, one simulation each (sfixed_ops generics).
# See the docstring of tb_sfixed.py for what each one covers.
CONFIGS = [
    dict(name="aligned", A_L=0, A_R=-15, B_L=0, B_R=-15, RS_L=0, RS_R=-15),
    dict(name="misaligned", A_L=3, A_R=-4, B_L=1, B_R=-6, RS_L=2, RS_R=-3),
    dict(name="integer", A_L=7, A_R=0, B_L=5, B_R=0, RS_L=6, RS_R=1),
    dict(name="fractional", A_L=-1, A_R=-8, B_L=-3, B_R=-10, RS_L=-4, RS_R=-12),
    dict(name="int_frac", A_L=5, A_R=0, B_L=-2, B_R=-9, RS_L=3, RS_R=-4),
]

GENERICS = ("A_L", "A_R", "B_L", "B_R", "RS_L", "RS_R")


def test_sfixed():
    build_dir = TEST_DIR / "sim_build"

    runner = Questa()

    runner.build(
        vhdl_sources=[
            PROJECT_DIR / "src" / "lib" / "numeric" / "ufixed_pkg.vhd",
            PROJECT_DIR / "src" / "lib" / "numeric" / "sfixed_pkg.vhd",
            TEST_DIR / "sfixed_ops.vhd",
        ],
        hdl_toplevel="sfixed_ops",
        build_args=[VHDL("-2008")],
        build_dir=build_dir,
    )

    failed = []
    for cfg in CONFIGS:
        results = runner.test(
            hdl_toplevel="sfixed_ops",
            test_module="tb_sfixed",
            parameters={k: cfg[k] for k in GENERICS},
            extra_env={"SFIXED_CFG": json.dumps(cfg)},
            results_xml=f"results_{cfg['name']}.xml",
        )
        _, num_failed = get_results(results)
        if num_failed:
            failed.append(cfg["name"])

    assert not failed, f"failing configurations: {failed}"


if __name__ == "__main__":
    test_sfixed()
