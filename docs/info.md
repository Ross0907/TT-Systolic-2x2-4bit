# 2×2 Systolic Array Matrix Multiplier

## Overview

This project implements a **2×2 systolic array** that computes the matrix product  
**C = A × B**, where A and B are 2×2 matrices with 2-bit elements (values 0–3).  
Each result element is a 5-bit accumulator (maximum value = 18 = 3×3 + 3×3).

The design was ported from a Nexys 4 DDR FPGA demo that used manual clock-stepping  
buttons. In the Tiny Tapeout version the array runs free-running at full clock speed  
(one complete multiply every 5 clock cycles), and results are serialised onto the  
8-bit output bus.

---

## How it works

### Processing Element (PE)

Each PE performs one MAC per clock cycle:

```
acc = acc + (a_in × b_in)
```

`a_in` propagates **right** to the next column PE; `b_in` propagates **down** to the  
next row PE. The 2-bit operands are zero-extended to avoid truncation before  
multiplication, giving a 5-bit accumulator.

### 2×2 PE Grid

```
         col 0        col 1
row 0  [PE(0,0)] --> [PE(0,1)]
           |               |
row 1  [PE(1,0)] --> [PE(1,1)]
```

The state machine feeds skewed data into the grid so each PE sees the correct  
A-row and B-column operands in the correct pipeline stage:

| Cycle | State | PE(0,0)        | PE(0,1)       | PE(1,0)       | PE(1,1)       |
|-------|-------|----------------|---------------|---------------|---------------|
| 1     | CY1   | a00 × b00 ✓    | 0 × 0         | 0 × 0         | 0 × 0         |
| 2     | CY2   | += a01 × b10 ✓ | a00 × b01     | a10 × b00     | 0 × 0         |
| 3     | CY3   | 0              | += a01×b11 ✓  | += a11×b10 ✓  | a10 × b01     |
| 4     | FLUSH | 0              | 0             | 0             | += a11×b11 ✓  |
| 5     | IDLE  | *(next run)*   | —             | —             | —             |

✓ = accumulation complete for that element.

### IO Protocol

| Pin group | Direction | Meaning |
|-----------|-----------|---------|
| `ui_in[1:0]`   | input  | `a00` – Matrix A element [0,0] |
| `ui_in[3:2]`   | input  | `a01` – Matrix A element [0,1] |
| `ui_in[5:4]`   | input  | `a10` – Matrix A element [1,0] |
| `ui_in[7:6]`   | input  | `a11` – Matrix A element [1,1] |
| `uio[1:0]`     | input  | `b00` – Matrix B element [0,0] |
| `uio[3:2]`     | input  | `b01` – Matrix B element [0,1] |
| `uio[5:4]`     | input  | `b10` – Matrix B element [1,0] |
| `uio[7:6]`     | input  | `b11` – Matrix B element [1,1] |
| `uo_out[4:0]`  | output | Selected 5-bit result |
| `uo_out[6:5]`  | output | Result selector (00→C00, 01→C01, 10→C10, 11→C11) |
| `uo_out[7]`    | output | `done` – HIGH for 4 cycles while results are valid |

All bidirectional (`uio`) pins are permanently configured as **inputs** (`uio_oe = 0`).

---

## How to test

### Using the Tiny Tapeout dev board

1. Configure the RP2040 to drive a ~10 MHz clock on `clk`.
2. Use the board's input DIP switches / PMOD headers to set:
   - `ui_in` = Matrix A elements (2 bits each at positions [1:0], [3:2], [5:4], [7:6])
   - `uio` = Matrix B elements (same encoding)
3. Toggle `rst_n` low → high to start a computation.
4. Watch `uo_out[7]` — when it goes HIGH, read four consecutive bytes:
   - Byte 0: `uo_out[6:5]=00`, `uo_out[4:0]` = C[0][0]
   - Byte 1: `uo_out[6:5]=01`, `uo_out[4:0]` = C[0][1]
   - Byte 2: `uo_out[6:5]=10`, `uo_out[4:0]` = C[1][0]
   - Byte 3: `uo_out[6:5]=11`, `uo_out[4:0]` = C[1][1]

### Quick sanity checks

| Test | ui_in | uio_in | Expected C |
|------|-------|--------|------------|
| Identity | `0x41` (`01_00_00_01`) | `0x41` | [1, 0, 0, 1] |
| All-ones | `0x55` (`01_01_01_01`) | `0x55` | [2, 2, 2, 2] |
| Maximum | `0xFF` | `0xFF` | [18, 18, 18, 18] |
| Mixed | `0x27` (A=[[3,1],[2,0]]) | `0x4B` (B=[[3,0],[1,2]]) | compute manually |

### Using Vivado simulation

See `test/tb_vivado.v` — add all source files and `tb_vivado.v` to a Vivado project,  
set `tb_vivado` as the simulation top, and run for 2000 ns.  All 8 self-checking  
test cases print PASS/FAIL to the Tcl console.

### Using cocotb (Linux / WSL)

```bash
pip install cocotb pytest
sudo apt install iverilog
cd test && make
gtkwave tb.vcd     # visualise waveforms
```
