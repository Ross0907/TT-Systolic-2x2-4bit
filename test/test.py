"""
cocotb tests for tt_um_ross_systolic – 2×2 Systolic Array Matrix Multiplier
(signed 4-bit elements, 9-bit internal accumulators, 8-bit two's complement output)
============================================================================

Run with:  cd test && python run_tests.py
Requires:  iverilog, cocotb, pytest

Output protocol (uo_out):
  [7:0] = result_data – lower 8 bits of 9-bit accumulator
  Note: max theoretical result = 98 (0x62) for all +7 inputs.
        Negative results appear as 8-bit two's complement on uo_out.

Control (uio_in):
  [0] = wren  – load ui_in into next matrix byte
  [1] = start – begin computation
  [7:2] = unused (tie LOW)
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def pack2_4bit(e0, e1):
    """Pack two 4-bit elements into a byte: {e1[3:0], e0[3:0]}"""
    return ((e1 & 0xF) << 4) | (e0 & 0xF)


def matmul_2x2(A, B):
    """Reference 2×2 integer matrix multiply (returns full 9-bit values)."""
    C = [[0]*2 for _ in range(2)]
    for i in range(2):
        for j in range(2):
            s = 0
            for k in range(2):
                s += A[i][k] * B[k][j]
            C[i][j] = s
    return C


async def reset_dut(dut):
    """Apply reset for 5 clock cycles."""
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1


async def load_byte(dut, data):
    """Load one byte into the matrix register."""
    dut.ui_in.value = data
    dut.uio_in.value = 0x01  # wren=1
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0x00
    await RisingEdge(dut.clk)


async def start_compute(dut):
    """Pulse start to begin computation."""
    dut.uio_in.value = 0x02  # start=1
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0x00
    await RisingEdge(dut.clk)


async def read_results(dut):
    """Read 4 results after fixed delay. Returns flat list [C00,C01,C10,C11]."""
    # Wait for systolic array to finish (~5 cycles) then read 4 outputs
    await ClockCycles(dut.clk, 5)
    results = []
    for _ in range(4):
        results.append(int(dut.uo_out.value) & 0xFF)
        await RisingEdge(dut.clk)
    return results


async def run_multiply(dut, A, B):
    """Full flow: load matrices, start, wait, read and return C as flat list.
    Compares lower 8 bits only since uo_out is 8-bit and acc is 9-bit.
    Also verifies debug pins after result stream completes."""
    C = matmul_2x2(A, B)

    # Load 4 bytes: A (2 bytes), then B (2 bytes)
    # Perfect 4-bit packing: byte = {e1, e0}
    await load_byte(dut, pack2_4bit(A[0][0], A[0][1]))
    await load_byte(dut, pack2_4bit(A[1][0], A[1][1]))
    await load_byte(dut, pack2_4bit(B[0][0], B[0][1]))
    await load_byte(dut, pack2_4bit(B[1][0], B[1][1]))

    # Start computation
    await start_compute(dut)

    results = await read_results(dut)

    # Verify debug pins after result stream
    # uio_out: [7]=any_negative, [6]=overflow_8bit, [5]=done, [4]=out_busy,
    #          [3]=out_valid, [2]=busy_core, [1:0]=0 (input pins)
    uio = int(dut.uio_out.value)
    any_negative = (uio >> 7) & 1
    overflow_8bit = (uio >> 6) & 1
    out_busy = (uio >> 4) & 1
    out_valid = (uio >> 3) & 1
    busy_core = (uio >> 2) & 1

    exp_any_neg = any(c < 0 for row in C for c in row)
    exp_overflow = any(c > 127 or c < -128 for row in C for c in row)

    assert busy_core == 0, f"busy_core should be 0 after done, got {busy_core}"
    assert out_valid == 0, f"out_valid should be 0 after stream, got {out_valid}"
    assert out_busy == 0, f"out_busy should be 0 after stream, got {out_busy}"
    assert any_negative == exp_any_neg, \
        f"any_negative={any_negative}, expected={exp_any_neg}"
    assert overflow_8bit == exp_overflow, \
        f"overflow_8bit={overflow_8bit}, expected={exp_overflow}"

    return results


# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_reset_state(dut):
    """After reset, outputs should be 0."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    await ClockCycles(dut.clk, 2)

    assert int(dut.uo_out.value) == 0, \
        f"Expected uo_out=0 after reset, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0, "uio_out should be 0"
    assert int(dut.uio_oe.value) == 0xFC, "uio_oe should be 0xFC (bits 7:2 output, 1:0 input)"


@cocotb.test()
async def test_identity_times_identity(dut):
    """I × I = I"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[1,0], [0,1]]
    B = [[1,0], [0,1]]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"I×I: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_all_ones(dut):
    """All-ones × all-ones = [[2,2],[2,2]]"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[1,1] for _ in range(2)]
    B = [[1,1] for _ in range(2)]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"1s×1s: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_max_positive(dut):
    """All +7s × all +7s = [[98,98],[98,98]] (fits in 8-bit signed)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[7,7] for _ in range(2)]
    B = [[7,7] for _ in range(2)]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"max-pos: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_asymmetric(dut):
    """Mixed non-symmetric case"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[5,3], [2,7]]
    B = [[4,6], [1,7]]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"asym: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_zero_matrix(dut):
    """A=0, B=anything → C=0"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[0,0] for _ in range(2)]
    B = [[9,12], [3,7]]
    expected = [0] * 4

    results = await run_multiply(dut, A, B)
    dut._log.info(f"0×B: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_diagonal_scaling(dut):
    """Diagonal matrix multiplication"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[4,0], [0,4]]
    B = [[2,5], [6,3]]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"diag: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_overflow(dut):
    """Overflow: (-8)×(-8) + (-8)×(-8) = 128 > +127, overflow_8bit should be 1"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[-8, -8], [0, 0]]
    B = [[-8, 0], [-8, 0]]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"overflow: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_consecutive_runs(dut):
    """Verify correct results across 3 back-to-back runs."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    cases = [
        ([[1,0], [0,1]],
         [[5,7], [3,2]]),
        ([[4,2], [1,6]],
         [[3,5], [2,4]]),
        ([[3,4], [5,6]],
         [[2,1], [3,4]]),
    ]

    for A, B in cases:
        results = await run_multiply(dut, A, B)
        C = matmul_2x2(A, B)
        expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]
        dut._log.info(f"consecutive: got {results}, expected {expected}")
        assert results == expected, f"Mismatch: {results} vs {expected}"
