# 4×4 Systolic Array Matrix Multiplier

## Overview

This project implements a **4×4 systolic array** that computes the matrix product  
**C = A × B**, where A and B are 4×4 matrices with 2-bit unsigned elements (values 0–3).  
Each result element is a 6-bit accumulator (maximum value = 36 = 4 × 3×3).

Each Processing Element (PE) contains an explicit **Wallace tree multiplier** for fast  
partial-product generation. The array uses skewed input feeding controlled by a cycle  
counter, completing one full 4×4 multiply in 10 clock cycles.

Matrix data is loaded serially via a byte-streaming protocol, and the 16 results are  
streamed out serially over 16 clock cycles.

---

## How it works

### Processing Element (PE)

Each PE performs one MAC per active clock cycle:

```
acc = clear ? (a_in × b_in) : acc + (a_in × b_in)
```

`a_in` propagates **right** to the next column PE; `b_in` propagates **down** to the  
next row PE. Each PE contains a dedicated 2×2 Wallace tree multiplier producing a  
4-bit product, which is zero-extended to 6 bits before accumulation.

### 4×4 PE Grid

Sixteen PEs are arranged in a 4×4 grid. Data flows into the left edge (A elements)  
and top edge (B elements), then propagates rightward and downward through the array.

The controller uses a 10-cycle counter (t = 0 … 9) with skewed feeding:

| t | feed_a0 | feed_a1 | feed_a2 | feed_a3 | feed_b0 | feed_b1 | feed_b2 | feed_b3 |
|---|---------|---------|---------|---------|---------|---------|---------|---------|
| 0 | a00     | —       | —       | —       | b00     | b01     | b02     | b03     |
| 1 | a01     | a10     | —       | —       | b10     | b11     | b12     | b13     |
| 2 | a02     | a11     | a20     | —       | b20     | b21     | b22     | b23     |
| 3 | a03     | a12     | a21     | a30     | b30     | b31     | b32     | b33     |
| 4 | —       | a13     | a22     | a31     | —       | —       | —       | —       |
| 5 | —       | —       | a23     | a32     | —       | —       | —       | —       |
| 6 | —       | —       | —       | a33     | —       | —       | —       | —       |
| 7 | flush   | flush   | flush   | flush   | flush   | flush   | flush   | flush   |
| 8 | flush   | flush   | flush   | flush   | flush   | flush   | flush   | flush   |
| 9 | done    | done    | done    | done    | done    | done    | done    | done    |

PE(i,j) receives its first useful operands at t = i + j and accumulates for 4 cycles.
All accumulators are stable by t = 9, when `done` is asserted.

### IO Protocol

| Pin | Direction | Function |
|-----|-----------|----------|
| `ui_in[7:0]`  | input  | Data byte to load |
| `uio_in[0]`   | input  | `wren` — write enable, loads `ui_in` into next matrix byte |
| `uio_in[1]`   | input  | `start` — pulse HIGH to begin computation |
| `uio_in[2]`   | input  | `debug` — HIGH enables debug output on `uio_out[3:0]` |
| `uo_out[5:0]` | output | Result data (6-bit matrix element) |
| `uo_out[6]`   | output | `valid` — HIGH when `uo_out[5:0]` is a valid result |
| `uo_out[7]`   | output | `busy` — HIGH during compute and output phases |
| `uio_out[3:0]`| output | Debug: current result index (0–15) when `debug=1` |
| `uio_oe`      | output | `8'h0F` when `debug=1`, else `8'h00` |

### Operation Steps

1. **Reset** — hold `rst_n` LOW for ≥4 cycles, then release.
2. **Load** — drive each of 8 bytes on `ui_in` and pulse `uio_in[0]` (wren) HIGH:
   - Byte 0: `{a03,a02,a01,a00}`
   - Byte 1: `{a13,a12,a11,a10}`
   - Byte 2: `{a23,a22,a21,a20}`
   - Byte 3: `{a33,a32,a31,a30}`
   - Byte 4: `{b03,b02,b01,b00}`
   - Byte 5: `{b13,b12,b11,b10}`
   - Byte 6: `{b23,b22,b21,b20}`
   - Byte 7: `{b33,b32,b31,b30}`
3. **Start** — pulse `uio_in[1]` (start) HIGH for one cycle.
4. **Read** — wait for `uo_out[6]` (`valid`) to go HIGH, then read `uo_out[5:0]` for  
   **16 consecutive cycles**: C[0][0], C[0][1], …, C[3][3].

---

## How to test

### Quick sanity checks

| Test | Bytes to load (hex) | Expected C |
|------|---------------------|------------|
| Identity | `01 04 10 40 01 04 10 40` | diagonal = 1, rest = 0 |
| All-ones | `55 55 55 55 55 55 55 55` | all elements = 4 |
| Maximum  | `FF FF FF FF FF FF FF FF` | all elements = 36 |

### Vivado simulation

Add these source files to a Vivado project:
- `src/wallace_mult_2x2.v`
- `src/systolic_pe.v`
- `src/systolic_4x4.v`
- `src/project.v`

Add `test/tb_vivado.v` as a simulation source, **set it as Top**, and run Behavioral  
Simulation. In the Tcl console: `run 5000ns`. All 7 self-checking test cases print  
PASS/FAIL to the transcript.

### cocotb (Linux / WSL / GitHub Actions)

```bash
pip install -r test/requirements.txt
cd test && make
```

Results are checked in `test/results.xml`. Waveforms are written to `test/tb.fst`.
