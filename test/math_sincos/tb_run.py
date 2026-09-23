import shutil
import sys
from pathlib import Path

from cocotb_tools.runner import VHDL, Questa

TEST_DIR = Path(__file__).resolve().parent
TEST_ROOT = TEST_DIR.parent
PROJECT_DIR = TEST_ROOT.parent

# Make the fixed-point helpers and interpolation model importable from the test
# module, regardless of whether PYTHONPATH was picked up from .env.
sys.path.insert(0, str(TEST_DIR))
sys.path.insert(0, str(TEST_ROOT / "lib"))

# rom_sin.vhd / rom_cos.vhd hardcode their .mif init_file with a path relative to
# the simulator's working directory (e.g. "./src/lib/altera/rom_sin/sin_table.mif").
# cocotb runs vsim with cwd=build_dir, so mirror that same relative layout there.
MIF_FILES = [
    "src/lib/altera/rom_sin/sin_table.mif",
    "src/lib/altera/rom_cos/cos_table.mif",
]


def _stage_mif_files(build_dir: Path) -> None:
    for rel in MIF_FILES:
        dst = build_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(PROJECT_DIR / rel, dst)


def test_sincos():
    altera_dir = PROJECT_DIR / "src" / "lib" / "altera"
    build_dir = TEST_DIR / "sim_build"

    vhdl_sources = [
        altera_dir / "rom_sin" / "rom_sin.vhd",
        altera_dir / "rom_cos" / "rom_cos.vhd",
        altera_dir / "mult_16" / "mult_16.vhd",
        PROJECT_DIR / "src" / "lib" / "math" / "sincos.vhd",
    ]

    runner = Questa()

    runner.build(
        vhdl_sources=vhdl_sources,
        hdl_toplevel="sincos",
        build_args=[VHDL("-2008")],
        build_dir=build_dir,
    )

    _stage_mif_files(build_dir)

    runner.test(
        hdl_toplevel="sincos",
        test_module="tb_sincos",
    )


if __name__ == "__main__":
    test_sincos()
