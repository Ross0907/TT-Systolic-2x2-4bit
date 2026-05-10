![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 2x2 Signed Systolic Array Matrix Multiplier

- [Read the documentation for project](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [docs/info.md](docs/info.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/).

## Enable GitHub actions to build the results page

- [Enabling GitHub Pages](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part)

## How it works

This is a 2×2 systolic array that computes **C = A × B** where A and B are 2×2 matrices with **signed 4-bit elements** (values -8 to +7). Internal accumulators are **9-bit signed** (max +98); output is lower 8 bits (two's complement) on `uo_out`. The **9th bit (sign)** and **overflow flag** are exposed on bidirectional pins so the full 9-bit value can be reconstructed.

- **4 PEs** in a 2×2 grid, each with a signed 4×4 multiplier + 9-bit signed accumulator
- **Skewed input feeding** via a 4-cycle counter
- **Byte-serial loading**: load 4 bytes (2 for A + 2 for B), then pulse `start`
- **Serial output**: 4 results streamed over 4 clock cycles
- **Manual step mode**: pulse `manual_clk` to advance one cycle at a time for human-visible demos
- **Overflow detection**: `overflow_8bit` pin indicates when result doesn't fit in 8-bit output
- **9th bit access**: `acc_sign` pin provides sign bit of currently-serialized result
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
| `uio[4]` | Output | `overflow_8bit` | `acc[8]^acc[7]` for current result (1 = truncated) |
| `uio[5]` | Input | `manual_clk` | Rising edge = advance one step |
| `uio[6]` | Input | `step_mode` | 1 = manual step, 0 = free-running |
| `uio[7]` | Output | `acc_sign` | `acc[8]` sign bit for current result (9th bit) |

`uio_oe = 0x9C` (bits 7,4,3,2 = output; bits 6,5,1,0 = input)

**{`acc_sign`, `uo_out[7:0]`} reconstructs the full 9-bit signed value.**

## How to test

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

## Test Coverage

| Test Suite | Cases | Coverage |
|------------|-------|----------|
| iverilog `tb_vivado.v` | **18** | Identity, all-ones, max-positive, asymmetric, zero, diagonal, mixed-signs, overflow, all-negative, boundary-mix, step mode, `ena` gating, reset-mid-compute, start-while-busy, rapid consecutive, overflow-edge |
| cocotb `test.py` | **16** | All above + 50 random fuzz, reset-during-compute, start-while-busy |
| GitHub Actions | **7 workflows** | GDS, test, FPGA, docs, precheck, gate-level, viewer |

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)
