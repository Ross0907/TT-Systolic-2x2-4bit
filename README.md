![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 4×4 Systolic Array Matrix Multiplier

A 4×4 systolic array that computes **C = A × B** where A and B are 4×4 matrices with 2-bit unsigned elements. Each Processing Element contains an explicit Wallace tree multiplier for speed. Results are 6-bit accumulators (max 36).

- [Read the documentation](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## How it works

- **16 PEs** in a 4×4 grid, each with a 2×2 Wallace tree multiplier + 6-bit accumulator
- **Skewed input feeding** via a 10-cycle counter
- **Byte-serial loading**: load 8 bytes (4 for A + 4 for B), then pulse `start`
- **Serial output**: 16 results streamed over 16 clock cycles

See [docs/info.md](docs/info.md) for the full pinout and protocol description.

## Simulation

### iverilog (command line)
```bash
cd TT_Systolic_
iverilog -g2012 -Wall -o sim.out \
  test/tb_vivado.v \
  src/project.v \
  src/systolic_4x4.v \
  src/systolic_pe.v \
  src/wallace_mult_2x2.v
vvp sim.out
```

### Vivado
1. Add `src/wallace_mult_2x2.v`, `src/systolic_pe.v`, `src/systolic_4x4.v`, `src/project.v`
2. Add `test/tb_vivado.v` as simulation top
3. Run Behavioral Simulation, then in Tcl console: `run 5000ns`

### cocotb
```bash
cd TT_Systolic_/test
pip install -r requirements.txt
make
```

## Project structure

| File | Description |
|------|-------------|
| `src/project.v` | Tiny Tapeout top module (`tt_um_ross_systolic`) |
| `src/systolic_4x4.v` | 4×4 systolic grid with skewed input controller |
| `src/systolic_pe.v` | Processing element (Wallace mult + 6-bit accumulator) |
| `src/wallace_mult_2x2.v` | Explicit 2×2 Wallace tree multiplier |
| `test/tb.v` | cocotb testbench |
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
