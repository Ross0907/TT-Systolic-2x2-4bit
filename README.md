![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 2×2 Signed Systolic Array Matrix Multiplier

A 2×2 systolic array that computes **C = A × B** where A and B are 2×2 matrices with **signed 4-bit elements** (values -8 to +7). Internal accumulators are **9-bit signed** (max +98); output is lower 8 bits (two's complement) on `uo_out`.

- [Read the documentation](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## How it works

- **4 PEs** in a 2×2 grid, each with a signed 4×4 multiplier + 9-bit signed accumulator
- **Skewed input feeding** via a 4-cycle counter
- **Byte-serial loading**: load 4 bytes (2 for A + 2 for B), then pulse `start`
- **Serial output**: 4 results streamed over 4 clock cycles
- **Manual step mode**: pulse `manual_clk` to advance one cycle at a time for human-visible demos
- **`ena` gating**: `start` is only accepted when `ena` is HIGH

### Pinout (all 24 pins used)

| Pin | Dir | Name | Function |
|-----|-----|------|----------|
| `ui[0-7]` | Input | `data_byte` | Matrix data (4 bytes = 8 elements) |
| `uo[0-7]` | Output | `result_data` | 8-bit two's complement result (lower 8 bits) |
| `uio[0]` | Input | `wren` | Write enable — loads `ui_in` into next matrix byte |
| `uio[1]` | Input | `start` | Begin computation |
| `uio[2]` | Output | `busy_core` | Systolic array is computing |
| `uio[3]` | Output | `out_valid` | Result data on `uo_out` is valid |
| `uio[4]` | Output | `overflow_8bit` | `acc[8]^acc[7]` for **current** result (1 = truncated) |
| `uio[5]` | Input | `manual_clk` | Rising edge = advance one step |
| `uio[6]` | Input | `step_mode` | 1 = manual step, 0 = free-running |
| `uio[7]` | Output | `acc_sign` | `acc[8]` sign bit for **current** result (9th bit) |

**{`acc_sign`, `uo_out[7:0]`} reconstructs the full 9-bit signed value.**

See [docs/info.md](docs/info.md) for the full protocol description.

## Simulation

### iverilog (command line)
```bash
cd TT_Systolic_
iverilog -g2012 -Wall -o sim.out \
  test/tb_vivado.v \
  src/project.v \
  src/systolic_2x2.v \
  src/systolic_pe.v \
  src/mult_4x4.v
vvp sim.out
```

### Vivado
1. Add `src/mult_4x4.v`, `src/systolic_pe.v`, `src/systolic_2x2.v`, `src/project.v`
2. Add `test/tb_vivado.v` as simulation top
3. Run Behavioral Simulation, then in Tcl console: `run 5000ns`

### cocotb
```bash
cd TT_Systolic_/test
pip install -r requirements.txt
python run_tests.py
```

## Project structure

| File | Description |
|------|-------------|
| `src/project.v` | Tiny Tapeout top module (`tt_um_ross_systolic`) |
| `src/systolic_2x2.v` | 2×2 systolic grid with skewed input controller |
| `src/systolic_pe.v` | Processing element (4×4 mult + 9-bit accumulator) |
| `src/mult_4x4.v` | 4×4 signed multiplier (8-bit product) |
| `test/tb_vivado.v` | Self-checking Verilog testbench (14 test cases) |
| `test/test.py` | cocotb Python tests (13 test cases) |

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/)
- Share your project on social media with #tinytapeout
