# 3×3 Systolic Array Matrix Multiplier

## Overview

This project implements a **3×3 systolic array** that computes the matrix product  
**C = A × B**, where A and B are 3×3 matrices with 3-bit unsigned elements (values 0–7).  
Each result element is an 8-bit accumulator (maximum value = 147 = 3 × 7×7).

Each Processing Element (PE) contains a 3×3 multiplier. The array uses skewed input  
feeding controlled by a cycle counter, completing one full 3×3 multiply in 8 clock cycles.

Matrix data is loaded serially via a byte-streaming protocol, and the 9 results are  
streamed out serially over 9 clock cycles.

---

## How it works

### Processing Element (PE)

Each PE performs one MAC per active clock cycle:

```
acc = clear ? (a_in × b_in) : acc + (a_in × b_in)
```

`a_in` propagates **right** to the next column PE; `b_in` propagates **down** to the  
next row PE. Each PE contains a 3×3 multiplier producing a 6-bit product, which is  
zero-extended to 8 bits before accumulation.

### 3×3 PE Grid

Nine PEs are arranged in a 3×3 grid. Data flows into the left edge (A elements)  
and top edge (B elements), then propagates rightward and downward through the array.

The controller uses an 8-cycle counter (t = 0 … 7) with skewed feeding:

| t | feed_a0 | feed_a1 | feed_a2 | feed_b0 | feed_b1 | feed_b2 |
|---|---------|---------|---------|---------|---------|---------|
| 0 | a00     | —       | —       | b00     | —       | —       |
| 1 | a01     | a10     | —       | b10     | b01     | —       |
| 2 | a02     | a11     | a20     | b20     | b11     | b02     |
| 3 | —       | a12     | a21     | —       | b21     | b12     |
| 4 | —       | —       | a22     | —       | —       | b22     |
| 5 | flush   | flush   | flush   | flush   | flush   | flush   |
| 6 | flush   | flush   | flush   | flush   | flush   | flush   |
| 7 | done    | done    | done    | done    | done    | done    |

PE(i,j) receives its first useful operands at t = i + j and accumulates for 3 cycles.
All accumulators are stable by t = 7, when `done` is asserted.

### IO Protocol

| Pin | Direction | Function |
|-----|-----------|----------|
| `ui_in[7:0]`  | input  | Data byte to load |
| `uio_in[0]`   | input  | `wren` — write enable, loads `ui_in` into next matrix byte |
| `uio_in[1]`   | input  | `start` — pulse HIGH to begin computation |
| `uo_out[7:0]` | output | Result data (8-bit matrix element) |

### Operation Steps

1. **Reset** — hold `rst_n` LOW for ≥4 cycles, then release.
2. **Load** — drive each of 10 bytes on `ui_in` and pulse `uio_in[0]` (wren) HIGH:
   - Byte 0: `{2'b0, a01, a00}`
   - Byte 1: `{2'b0, a10, a02}`
   - Byte 2: `{2'b0, a12, a11}`
   - Byte 3: `{2'b0, a21, a20}`
   - Byte 4: `{5'b0, a22}`
   - Byte 5: `{2'b0, b01, b00}`
   - Byte 6: `{2'b0, b10, b02}`
   - Byte 7: `{2'b0, b12, b11}`
   - Byte 8: `{2'b0, b21, b20}`
   - Byte 9: `{5'b0, b22}`
3. **Start** — pulse `uio_in[1]` (start) HIGH for one cycle.
4. **Read** — wait ~10 cycles, then read `uo_out[7:0]` for **9 consecutive cycles**:  
   C[0][0], C[0][1], C[0][2], C[1][0], C[1][1], C[1][2], C[2][0], C[2][1], C[2][2].

---

## How to test

### Quick sanity checks

| Test | Bytes to load (hex) | Expected C |
|------|---------------------|------------|
| Identity | `01 08 20 00 01 01 08 20 00 01` | diagonal = 1, rest = 0 |
| All-ones | `09 09 09 09 01 09 09 09 09 01` | all elements = 3 |
| Maximum  | `3F 38 38 38 07 3F 38 38 38 07` | all elements = 147 |

### Vivado simulation

Add these source files to a Vivado project:
- `src/mult_3x3.v`
- `src/systolic_pe.v`
- `src/systolic_3x3.v`
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
