# 1. RTL Design
1. In a VHDL file check if doxygen comments are present.
2. If requested to generate a design ask to point toward a python model and some other design for reference on naming convention and design pattern.
3. Always requires full-specification of a new componemnt and do take any non-trivial architectural decision.

# 2. Model
1. We create python models to create replica of the rtl duts.
2. The model should be as simple as possible, using high-level methods and library (e.g. numpy) such that it is very readable.
3. Do not generate models trying to capture every details of the RTL design, otherwise we can pull bugs that are difficult to capture in the model -- a model should replicate at the numerical level by using integer or sfixed operation, but not fully emulate the RTL implementation.

# 3. Test
1. Use cocotb and Questa.
2. Generate subfolder in test/
3. Use a `tb_run.py` file to compile and launch the testbench.
4. Use a `tb_<component>.py` to execute the testbench.
5. Do not forget reset.
6. Use models for very-close comparison (e.g. max 1 LSB error).
7. If applicable (e.g. DSP) use very high-level model (e.g. in float) and allow wider error threshold.
8. Make plots of results in subfolder results/

# Way of Working
1. Ask for examles and keep style coherent.