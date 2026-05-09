"""
cocotb tests for tt_um_ross_systolic – 3×3 Systolic Array Matrix Multiplier
============================================================================

Run with:  cd test && python run_tests.py
Requires:  iverilog, cocotb, pytest

Output protocol (uo_out):
  [7:0] = result_data – 8-bit matrix element result

Control (uio_in):
  [0] = wren  – load ui_in into next matrix byte
  [1] = start – begin computation
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def pack2_3bit(e0, e1):
    """Pack two 3-bit elements into a byte: {2'b0, e1, e0}"""
    return (e1 << 3) | e0


def matmul_3x3(A, B):
    """Reference 3×3 integer matrix multiply."""
    C = [[0]*3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            s = 0
            for k in range(3):
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
    """Read 9 results after fixed delay. Returns flat list [C00..C22]."""
    # Wait for systolic array to finish (~9 cycles) then read 9 outputs
    await ClockCycles(dut.clk, 9)
    results = []
    for _ in range(9):
        results.append(int(dut.uo_out.value) & 0xFF)
        await RisingEdge(dut.clk)
    return results


async def run_multiply(dut, A, B):
    """Full flow: load matrices, start, wait, read and return C as flat list."""
    # Load 10 bytes: A (5 bytes), then B (5 bytes)
    await load_byte(dut, pack2_3bit(A[0][0], A[0][1]))
    await load_byte(dut, pack2_3bit(A[0][2], A[1][0]))
    await load_byte(dut, pack2_3bit(A[1][1], A[1][2]))
    await load_byte(dut, pack2_3bit(A[2][0], A[2][1]))
    await load_byte(dut, A[2][2])
    await load_byte(dut, pack2_3bit(B[0][0], B[0][1]))
    await load_byte(dut, pack2_3bit(B[0][2], B[1][0]))
    await load_byte(dut, pack2_3bit(B[1][1], B[1][2]))
    await load_byte(dut, pack2_3bit(B[2][0], B[2][1]))
    await load_byte(dut, B[2][2])

    # Start computation
    await start_compute(dut)

    return await read_results(dut)


# ─────────────────────────────────────────────────────────────────────────────
# Tests
# ─────────────────────────────────────────────────────────────────────────────

@cocotb.test()
async def test_reset_state(dut):
    """After reset, outputs should be 0."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)
    await ClockCycles(dut.clk, 2)

    assert int(dut.uo_out.value) == 0, \
        f"Expected uo_out=0 after reset, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0, "uio_out should be 0"
    assert int(dut.uio_oe.value) == 0, "uio_oe should be 0 (all inputs)"


@cocotb.test()
async def test_identity_times_identity(dut):
    """I × I = I"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[1,0,0], [0,1,0], [0,0,1]]
    B = [[1,0,0], [0,1,0], [0,0,1]]
    C = matmul_3x3(A, B)
    expected = [C[i][j] for i in range(3) for j in range(3)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"I×I: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_all_ones(dut):
    """All-ones × all-ones = [[3,3,3], ...]"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[1,1,1] for _ in range(3)]
    B = [[1,1,1] for _ in range(3)]
    C = matmul_3x3(A, B)
    expected = [C[i][j] for i in range(3) for j in range(3)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"1s×1s: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_max_inputs(dut):
    """All 7s × all 7s = [[147,147,147], ...] (maximum possible)"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[7,7,7] for _ in range(3)]
    B = [[7,7,7] for _ in range(3)]
    C = matmul_3x3(A, B)
    expected = [C[i][j] for i in range(3) for j in range(3)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"max: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_asymmetric(dut):
    """Mixed non-symmetric case"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[2,1,0], [0,2,1], [3,0,2]]
    B = [[1,2,3], [0,1,2], [3,0,1]]
    C = matmul_3x3(A, B)
    expected = [C[i][j] for i in range(3) for j in range(3)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"asym: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_zero_matrix(dut):
    """A=0, B=anything → C=0"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[0,0,0] for _ in range(3)]
    B = [[3,2,1], [1,2,3], [0,1,2]]
    expected = [0] * 9

    results = await run_multiply(dut, A, B)
    dut._log.info(f"0×B: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_diagonal_scaling(dut):
    """Diagonal matrix multiplication"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[2,0,0], [0,2,0], [0,0,2]]
    B = [[1,3,2], [3,1,3], [2,3,1]]
    C = matmul_3x3(A, B)
    expected = [C[i][j] for i in range(3) for j in range(3)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"diag: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_consecutive_runs(dut):
    """Verify correct results across 3 back-to-back runs."""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    cases = [
        ([[1,0,0], [0,1,0], [0,0,1]],
         [[2,3,1], [1,2,3], [0,1,2]]),
        ([[2,1,0], [0,2,1], [3,0,2]],
         [[2,1,0], [0,2,1], [3,0,2]]),
        ([[3,0,0], [0,3,0], [0,0,3]],
         [[1,1,1], [1,1,1], [1,1,1]]),
    ]

    for A, B in cases:
        results = await run_multiply(dut, A, B)
        C = matmul_3x3(A, B)
        expected = [C[i][j] for i in range(3) for j in range(3)]
        dut._log.info(f"consecutive: got {results}, expected {expected}")
        assert results == expected, f"Mismatch: {results} vs {expected}"
