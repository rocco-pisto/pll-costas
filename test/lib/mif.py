from pathlib import Path
from sfixed import SFixed
from math import sin, cos, pi


def write_mif(values, width, path, address_radix="UNS", data_radix="HEX"):
    """
    Generate a Quartus .mif file from an array of integers.

    values : list[int]   - data values, MSB-aligned meaning, i.e. already
                            the final integer to store at each address
                            (negative values are wrapped to two's complement)
    width  : int          - bits per word
    path   : str           - output file path, e.g. "sin_table.mif"
    """
    depth = len(values)
    hex_digits = (width + 3) // 4
    max_unsigned = (1 << width) - 1

    with open(path, "w") as f:
        f.write(f"WIDTH = {width};\n")
        f.write(f"DEPTH = {depth};\n")
        f.write(f"ADDRESS_RADIX = {address_radix};\n")
        f.write(f"DATA_RADIX = {data_radix};\n")
        f.write("CONTENT BEGIN\n")
        for addr, val in enumerate(values):
            v = val
            if v < 0:
                v += 1 << width  # two's complement wrap
            if v > max_unsigned or v < 0:
                raise ValueError(
                    f"value {val} at address {addr} doesn't fit in {width} bits"
                )
            f.write(f"    {addr:<5}: {v:0{hex_digits}X};\n")
        f.write("END;\n")


if __name__ == "__main__":
    # Base Folder
    base_folder = Path(__file__).parents[2]

    # sin/cos table
    w_r = int(14)
    w_l = int(2)
    n_pt = 32

    rom_sin_folder = base_folder / "src" / "lib" / "altera" / "rom_sin"
    rom_cos_folder = base_folder / "src" / "lib" / "altera" / "rom_cos"
    # Generate sine and cosine tables
    sin_table = [SFixed(w_l, -w_r, sin(0.5 * pi * i / n_pt)).u for i in range(n_pt)]
    cos_table = [SFixed(w_l, -w_r, cos(0.5 * pi * i / n_pt)).u for i in range(n_pt)]

    # Write tables to MIF files
    write_mif(sin_table, width=w_l + w_r, path=rom_sin_folder / "sin_table.mif")
    write_mif(cos_table, width=w_l + w_r, path=rom_cos_folder / "cos_table.mif")
    print("Wrote sin_table.mif and cos_table.mif")
