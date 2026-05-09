"""
cocotb tests for tt_um_ross_systolic – 2×2 Systolic Array Matrix Multiplier
(4-bit elements, 9-bit internal accumulators, 8-bit output)
============================================================================

Run with:  cd test && python run_tests.py
Requires:  iverilog, cocotb, pytest

Output protocol (uo_out):
  [7:0] = result_data – lower 8 bits of 9-bit accumulator
  Note: max theoretical result = 450 (0x1C2), so bit 8 may be set for
        extreme inputs. Results > 255 will appear modulo 256.

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
    return (e1 << 4) | e0


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
    Compares lower 8 bits only since uo_out is 8-bit and acc is 9-bit."""
    # Load 4 bytes: A (2 bytes), then B (2 bytes)
    # Perfect 4-bit packing: byte = {e1, e0}
    await load_byte(dut, pack2_4bit(A[0][0], A[0][1]))
    await load_byte(dut, pack2_4bit(A[1][0], A[1][1]))
    await load_byte(dut, pack2_4bit(B[0][0], B[0][1]))
    await load_byte(dut, pack2_4bit(B[1][0], B[1][1]))

    # Start computation
    await start_compute(dut)

    return await read_results(dut)


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
async def test_near_max_inputs(dut):
    """All 11s × all 11s = [[242,242],[242,242]] (fits in 8 bits)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[11,11] for _ in range(2)]
    B = [[11,11] for _ in range(2)]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"near-max: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_asymmetric(dut):
    """Mixed non-symmetric case"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[5,3], [2,7]]
    B = [[4,6], [1,8]]
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
        ([[8,0], [0,8]],
         [[2,3], [1,4]]),
    ]

    for A, B in cases:
        results = await run_multiply(dut, A, B)
        C = matmul_2x2(A, B)
        expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]
        dut._log.info(f"consecutive: got {results}, expected {expected}")
        assert results == expected, f"Mismatch: {results} vs {expected}"
