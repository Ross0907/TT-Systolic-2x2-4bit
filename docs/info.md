# 2×2 Systolic Array Matrix Multiplier

## Overview

This project implements a **2×2 systolic array** that computes the matrix product  
**C = A × B**, where A and B are 2×2 matrices with 4-bit unsigned elements (values 0–15).  
Each result element is a **9-bit accumulator** (maximum value = 450 = 2 × 15×15).  
The output port `uo_out` provides the **lower 8 bits**; results > 255 will appear modulo 256.

Each Processing Element (PE) contains a 4×4 multiplier. The array uses skewed input  
feeding controlled by a cycle counter, completing one full 2×2 multiply in 4 clock cycles.

Matrix data is loaded serially via a byte-streaming protocol (perfect 4-bit packing:  
2 elements per byte), and the 4 results are streamed out serially over 4 clock cycles.

---

## How it works

### Processing Element (PE)

Each PE performs one MAC per active clock cycle:

```
acc = clear ? (a_in × b_in) : acc + (a_in × b_in)
```

`a_in` propagates **right** to the next column PE; `b_in` propagates **down** to the  
next row PE. Each PE contains a 4×4 multiplier producing an 8-bit product, which is  
zero-extended to 9 bits before accumulation.

### 2×2 PE Grid

Four PEs are arranged in a 2×2 grid. Data flows into the left edge (A elements)  
and top edge (B elements), then propagates rightward and downward through the array.

The controller uses a 4-cycle counter (t = 0 … 3) with skewed feeding:

| t | feed_a0 | feed_a1 | feed_b0 | feed_b1 |
|---|---------|---------|---------|---------|
| 0 | a00     | —       | b00     | —       |
| 1 | a01     | a10     | b10     | b01     |
| 2 | —       | a11     | —       | b11     |
| 3 | done    | done    | done    | done    |

PE(i,j) receives its first useful operands at t = i + j and accumulates for 2 cycles.
All accumulators are stable by t = 3, when `done` is asserted.

### IO Protocol

| Pin | Direction | Function |
|-----|-----------|----------|
| `ui_in[7:0]`  | input  | Data byte to load |
| `uio_in[0]`   | input  | `wren` — write enable, loads `ui_in` into next matrix byte |
| `uio_in[1]`   | input  | `start` — pulse HIGH to begin computation (gated by `ena`) |
| `uio_in[7:2]` | input  | Unused (tie LOW) |
| `uo_out[7:0]` | output | Result data (8-bit matrix element) |
| `uio_out[2]`  | output | `busy_core` — systolic array is computing |
| `uio_out[3]`  | output | `out_valid` — result data on `uo_out` is valid |
| `uio_out[4]`  | output | `out_busy` — output serializer is active |
| `uio_out[7:5]`| output | Reserved (always 0) |
| `uio_oe`      | output | `0xFC` — bits 7:2 are outputs, bits 1:0 are inputs |
| `ena`         | input  | Must be HIGH for `start` to be accepted |

### Operation Steps

1. **Reset** — hold `rst_n` LOW for ≥4 cycles, then release.
2. **Load** — drive each of 4 bytes on `ui_in` and pulse `uio_in[0]` (wren) HIGH:
   - Byte 0: `{a01[3:0], a00[3:0]}`
   - Byte 1: `{a11[3:0], a10[3:0]}`
   - Byte 2: `{b01[3:0], b00[3:0]}`
   - Byte 3: `{b11[3:0], b10[3:0]}`
3. **Start** — pulse `uio_in[1]` (start) HIGH for one cycle (gated by `ena`).
4. **Read** — wait ~6 cycles, then read `uo_out[7:0]` for **4 consecutive cycles**:  
   C[0][0], C[0][1], C[1][0], C[1][1].
   
   **Note:** `uo_out` carries the lower 8 bits of each 9-bit result. For results ≤ 255  
   (e.g., all inputs ≤ 11), the value is exact. For larger inputs, the value wraps mod 256.

---

## How to test

### Quick sanity checks

| Test | Bytes to load (hex) | Expected C |
|------|---------------------|------------|
| Identity | `01 10 01 10` | diagonal = 1, rest = 0 |
| All-ones | `11 11 11 11` | all elements = 2 |
| Near-max | `BB BB BB BB` | all elements = 242 (11×11, fits in 8 bits) |

### Vivado simulation

Add these source files to a Vivado project:
- `src/mult_4x4.v`
- `src/systolic_pe.v`
- `src/systolic_2x2.v`
- `src/project.v`

Add `test/tb_vivado.v` as a simulation source, **set it as Top**, and run Behavioral  
Simulation. In the Tcl console: `run 5000ns`. All 7 self-checking test cases print  
PASS/FAIL to the transcript.

### cocotb (Linux / WSL / GitHub Actions)

```bash
pip install -r test/requirements.txt
cd test && python run_tests.py
```

Results are checked in `test/sim_build/results.xml`.
