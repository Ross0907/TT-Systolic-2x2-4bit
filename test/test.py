"""
cocotb tests for tt_um_ross_systolic – 4×4 Systolic Array Matrix Multiplier
============================================================================

Run with:  cd test && make
Requires:  iverilog (or verilator), cocotb, pytest

Output protocol (uo_out):
  [7]   = busy   – HIGH during compute and output phases
  [6]   = valid  – HIGH when result_data is valid
  [5:0] = result_data – 6-bit matrix element result

Control (uio_in):
  [0] = wren  – load ui_in into next matrix byte
  [1] = start – begin computation
  [2] = debug – enable debug output on uio_out[3:0]
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def pack4(e0, e1, e2, e3):
    """Pack four 2-bit elements into a byte: {e3, e2, e1, e0}"""
    return (e3 << 6) | (e2 << 4) | (e1 << 2) | e0


def matmul_4x4(A, B):
    """Reference 4×4 integer matrix multiply."""
    C = [[0]*4 for _ in range(4)]
    for i in range(4):
        for j in range(4):
            s = 0
            for k in range(4):
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


async def wait_valid(dut, timeout=50):
    """Wait until uo_out[6] (valid) goes HIGH. Returns False on timeout."""
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if (int(dut.uo_out.value) >> 6) & 1:
            return True
    return False


async def read_results(dut):
    """Read 16 results while valid=1. Returns flat list [C00, C01, ..., C33]."""
    results = []
    for _ in range(16):
        raw = int(dut.uo_out.value)
        valid = (raw >> 6) & 1
        assert valid == 1, f"valid de-asserted unexpectedly (raw=0x{raw:02X})"
        results.append(raw & 0x3F)
        await RisingEdge(dut.clk)
    return results


async def run_multiply(dut, A, B):
    """Full flow: load matrices, start, wait, read and return C as flat list."""
    # Load 8 bytes: A rows 0-3, then B rows 0-3
    await load_byte(dut, pack4(A[0][0], A[0][1], A[0][2], A[0][3]))
    await load_byte(dut, pack4(A[1][0], A[1][1], A[1][2], A[1][3]))
    await load_byte(dut, pack4(A[2][0], A[2][1], A[2][2], A[2][3]))
    await load_byte(dut, pack4(A[3][0], A[3][1], A[3][2], A[3][3]))
    await load_byte(dut, pack4(B[0][0], B[0][1], B[0][2], B[0][3]))
    await load_byte(dut, pack4(B[1][0], B[1][1], B[1][2], B[1][3]))
    await load_byte(dut, pack4(B[2][0], B[2][1], B[2][2], B[2][3]))
    await load_byte(dut, pack4(B[3][0], B[3][1], B[3][2], B[3][3]))

    # Start computation
    await start_compute(dut)

    # Wait for output
    ok = await wait_valid(dut)
    assert ok, "Timeout waiting for valid signal"

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

    A = [[1,0,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1]]
    B = [[1,0,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1]]
    C = matmul_4x4(A, B)
    expected = [C[i][j] for i in range(4) for j in range(4)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"I×I: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_all_ones(dut):
    """All-ones × all-ones = [[4,4,4,4], ...]"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[1,1,1,1] for _ in range(4)]
    B = [[1,1,1,1] for _ in range(4)]
    C = matmul_4x4(A, B)
    expected = [C[i][j] for i in range(4) for j in range(4)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"1s×1s: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_max_inputs(dut):
    """All 3s × all 3s = [[36,36,36,36], ...] (maximum possible)"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[3,3,3,3] for _ in range(4)]
    B = [[3,3,3,3] for _ in range(4)]
    C = matmul_4x4(A, B)
    expected = [C[i][j] for i in range(4) for j in range(4)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"max: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_asymmetric(dut):
    """Mixed non-symmetric case"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[2,1,0,3], [0,2,1,0], [3,0,2,1], [1,3,0,2]]
    B = [[1,2,3,0], [0,1,2,3], [3,0,1,2], [2,3,0,1]]
    C = matmul_4x4(A, B)
    expected = [C[i][j] for i in range(4) for j in range(4)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"asym: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_zero_matrix(dut):
    """A=0, B=anything → C=0"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[0,0,0,0] for _ in range(4)]
    B = [[3,2,1,3], [1,2,3,0], [0,1,2,3], [3,0,1,2]]
    expected = [0] * 16

    results = await run_multiply(dut, A, B)
    dut._log.info(f"0×B: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_diagonal_scaling(dut):
    """Diagonal matrix multiplication"""
    clock = Clock(dut.clk, 10, units="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[2,0,0,0], [0,2,0,0], [0,0,2,0], [0,0,0,2]]
    B = [[1,3,2,1], [3,1,3,2], [2,3,1,3], [1,2,3,1]]
    C = matmul_4x4(A, B)
    expected = [C[i][j] for i in range(4) for j in range(4)]

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
        ([[1,0,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1]],
         [[2,3,1,0], [1,2,3,1], [0,1,2,3], [3,0,1,2]]),
        ([[2,1,0,3], [0,2,1,0], [3,0,2,1], [1,3,0,2]],
         [[2,1,0,3], [0,2,1,0], [3,0,2,1], [1,3,0,2]]),
        ([[3,0,0,0], [0,3,0,0], [0,0,3,0], [0,0,0,3]],
         [[1,1,1,1], [1,1,1,1], [1,1,1,1], [1,1,1,1]]),
    ]

    for A, B in cases:
        results = await run_multiply(dut, A, B)
        C = matmul_4x4(A, B)
        expected = [C[i][j] for i in range(4) for j in range(4)]
        dut._log.info(f"consecutive: got {results}, expected {expected}")
        assert results == expected, f"Mismatch: {results} vs {expected}"
