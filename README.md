![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 3×3 Systolic Array Matrix Multiplier

A 3×3 systolic array that computes **C = A × B** where A and B are 3×3 matrices with 3-bit unsigned elements (values 0–7). Results are 8-bit accumulators (max 147).

- [Read the documentation](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## How it works

- **9 PEs** in a 3×3 grid, each with a 3×3 multiplier + 8-bit accumulator
- **Skewed input feeding** via an 8-cycle counter
- **Byte-serial loading**: load 10 bytes (5 for A + 5 for B), then pulse `start`
- **Serial output**: 9 results streamed over 9 clock cycles

See [docs/info.md](docs/info.md) for the full pinout and protocol description.

## Simulation

### iverilog (command line)
```bash
cd TT_Systolic_
iverilog -g2012 -Wall -o sim.out \
  test/tb_vivado.v \
  src/project.v \
  src/systolic_3x3.v \
  src/systolic_pe.v \
  src/mult_3x3.v
vvp sim.out
```

### Vivado
1. Add `src/mult_3x3.v`, `src/systolic_pe.v`, `src/systolic_3x3.v`, `src/project.v`
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
| `src/systolic_3x3.v` | 3×3 systolic grid with skewed input controller |
| `src/systolic_pe.v` | Processing element (3×3 mult + 8-bit accumulator) |
| `src/mult_3x3.v` | 3×3 unsigned multiplier |
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
