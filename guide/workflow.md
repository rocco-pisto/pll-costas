Written for: you, working through your first compile of this project in the Quartus GUI.

Your project won't compile as it stands. Fix the items in step 0 first, then run the flow. I checked the project files but haven't run Quartus.

## 0. Fix the project first

1. **Add the missing source files.** The QSF only lists `pll_costas.vhd` and the three IP `.qip` files. Add these through *Project → Add/Remove Files in Project*, or paste the lines into the QSF:
   ```
   set_global_assignment -name VHDL_FILE src/conf/board.vhd
   set_global_assignment -name VHDL_FILE src/lib/base/decoder.vhd
   set_global_assignment -name VHDL_FILE src/lib/time/phase.vhd
   set_global_assignment -name VHDL_FILE src/lib/math/sincos.vhd
   set_global_assignment -name VHDL_FILE src/nco/nco.vhd
   ```
2. **Switch to VHDL-2008.** `phase.vhd` and `board.vhd` use `ieee.fixed_pkg`, and your install only provides it for VHDL-2008. Set it under *Assignments → Settings → Compiler Settings → VHDL Input → VHDL 2008*, or add:
   ```
   set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008
   ```
3. **Remove the third-party synthesis setting.** The QSF has `EDA_DESIGN_ENTRY_SYNTHESIS_TOOL "Precision Synthesis"` with VQM input, which tells Quartus to expect a netlist from Mentor Precision. Set it to *None* under *Settings → EDA Tool Settings → Design Entry/Synthesis*. It's probably a leftover from the New Project wizard.
4. **Check the clock pin.** EP4CE22F17C6 with LEDs on A15/A13/B13/… and KEY0 on J15 looks like a DE0-Nano. On that board the 50 MHz clock is on PIN_R8, not the PIN_B8 you have. Check your board's manual.

## 1. Analysis & Elaboration
Run *Processing → Start → Start Analysis & Elaboration*. It only parses and elaborates the design, so it's the quickest way to catch VHDL errors and missing files.
- Check the result in *Tools → Netlist Viewers → RTL Viewer*: you should see `nco` (containing `phase` and `sincos`) feeding `decoder`.

## 2. Analysis & Synthesis (Ctrl+K)
In the Compilation Report, look at:
- **Flow Summary:** logic elements, registers, embedded multipliers and memory bits used.
- **Analysis & Synthesis → Resource Utilization by Entity:** the breakdown per block.
  - Because `freq_i` is a constant (1 Hz), synthesis folds the `freq × T_CLK` multiplier down to a constant. Don't expect a DSP block for it.
- **Messages:** read the warnings for inferred latches (there should be none), signals truncated or with no driver, and pins stuck at GND/VCC.

## 3. Pins
Open *Assignments → Pin Planner* and check that all 10 pins have a location and use 3.3-V LVTTL. Yours do.

## 4. Full compile (Ctrl+L)
This runs Synthesis, then the Fitter (place and route), then the Assembler (which writes the `.sof`), then the Timing Analyzer. Everything lands in `output_files/`.

## 5. Timing analysis
**First, complete the SDC.** Right now it only defines the clock, so the reset and LED paths show up as unconstrained:
```tcl
create_clock -name clk_0 -period 20 [get_ports clk_0]
derive_clock_uncertainty
# Push-button and LEDs: asynchronous to the design, not timed
set_false_path -from [get_ports rst_n]
set_false_path -to   [get_ports led_*]
```
`rst_n` comes straight from a push-button, but the design uses it as a synchronous reset. Put a 2-flip-flop synchronizer in front of it in the top level; the false path only makes sense with that in place.

**In the Compilation Report → Timing Analyzer**, check:
- **Fmax Summary** for each corner. It should be above 50 MHz.
- **Setup Summary / Hold Summary:** the worst slack must be positive in all three corners (Slow 1200mV 85C, Slow 1200mV 0C, Fast 1200mV 0C).
- **Unconstrained Paths:** should be 0 after the SDC fix.

**To dig deeper, open *Tools → Timing Analyzer*:**
1. Under *Tasks*, double-click *Create Timing Netlist*, then *Read SDC File*, then *Update Timing Netlist*.
2. Run *Report Setup Summary* and *Report Hold Summary*.
3. Run *Report Top Failing Paths*, or *Report Timing* with `-npaths 10`, to see the worst paths. The likely critical paths are the 72-bit phase accumulator adder and the sincos multiply-add.
4. Run *Report Unconstrained Paths* and *Check Timing* to confirm nothing is left untimed.

**From the command line instead of the GUI:**
```
C:\altera_lite\25.1std\quartus\bin64\quartus_sh --flow compile pll_costas
C:\altera_lite\25.1std\quartus\bin64\quartus_sta pll_costas
```

## 6. Program the board
Open *Tools → Programmer*, select the USB-Blaster, add `output_files/pll_costas.sof`, and click *Start*.