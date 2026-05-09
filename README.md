![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 2×2 Systolic Array Matrix Multiplier

A 2×2 systolic array that computes **C = A × B** where A and B are 2×2 matrices with 4-bit unsigned elements (values 0–15). Internal accumulators are 9-bit (max 450); output is lower 8 bits on `uo_out`.

- [Read the documentation](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## How it works

- **4 PEs** in a 2×2 grid, each with a 4×4 multiplier + 9-bit accumulator
- **Skewed input feeding** via a 4-cycle counter
- **Byte-serial loading**: load 4 bytes (2 for A + 2 for B), then pulse `start`
- **Serial output**: 4 results streamed over 4 clock cycles
- **Debug/status outputs** on `uio_out[7:2]`: busy_core, out_valid, out_busy
- **`ena` gating**: `start` is only accepted when `ena` is HIGH

See [docs/info.md](docs/info.md) for the full pinout and protocol description.

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
| `src/mult_4x4.v` | 4×4 unsigned multiplier |
| `test/tb_vivado.v` | Self-checking Vivado testbench (7 test cases) |
| `test/test.py` | cocotb Python tests |

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/)
- Share your project on social media with #tinytapeout
