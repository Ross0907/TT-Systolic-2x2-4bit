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

    # Poll for out_valid, then read 4 results with per-cycle overflow/sign check
    await ClockCycles(dut.clk, 2)
    while ((int(dut.uio_out.value) >> 3) & 1) == 0:
        await RisingEdge(dut.clk)

    flat_C = [C[i][j] for i in range(2) for j in range(2)]
    results = []
    for k in range(4):
        uio = int(dut.uio_out.value)
        results.append(int(dut.uo_out.value) & 0xFF)
        # Check per-result overflow_8bit (uio[4]) and acc_sign (uio[7])
        exp_overflow = (flat_C[k] > 127) or (flat_C[k] < -128)
        exp_sign = 1 if flat_C[k] < 0 else 0
        got_overflow = (uio >> 4) & 1
        got_sign = (uio >> 7) & 1
        assert got_overflow == exp_overflow, \
            f"Result {k}: overflow_8bit={got_overflow}, expected={exp_overflow}"
        assert got_sign == exp_sign, \
            f"Result {k}: acc_sign={got_sign}, expected={exp_sign}"
        if k < 3:
            await RisingEdge(dut.clk)

    # Let serializer finish (out_valid goes 0 on next edge)
    await RisingEdge(dut.clk)
    # After stream: out_valid=0, so overflow_8bit=0, acc_sign=0, busy_core=0
    uio = int(dut.uio_out.value)
    assert ((uio >> 2) & 1) == 0, f"busy_core should be 0 after done"
    assert ((uio >> 3) & 1) == 0, f"out_valid should be 0 after stream"
    assert ((uio >> 4) & 1) == 0, f"overflow_8bit should be 0 after stream"
    assert ((uio >> 7) & 1) == 0, f"acc_sign should be 0 after stream"

    return results


async def step_pulse(dut, base_val):
    """Pulse manual_clk while keeping base_val on other bits."""
    dut.uio_in.value = base_val | 0x20   # set manual_clk=1
    await RisingEdge(dut.clk)
    dut.uio_in.value = base_val           # clear manual_clk
    await RisingEdge(dut.clk)


async def load_byte_step(dut, data):
    """Load one byte in step mode."""
    dut.ui_in.value = data
    await step_pulse(dut, 0x41)           # step_mode=1, wren=1
    dut.uio_in.value = 0x40
    await RisingEdge(dut.clk)


async def start_compute_step(dut):
    """Start computation in step mode."""
    await step_pulse(dut, 0x42)           # step_mode=1, start=1
    dut.uio_in.value = 0x40
    await RisingEdge(dut.clk)


async def run_multiply_step(dut, A, B):
    """Full flow in manual step mode."""
    C = matmul_2x2(A, B)

    await load_byte_step(dut, pack2_4bit(A[0][0], A[0][1]))
    await load_byte_step(dut, pack2_4bit(A[1][0], A[1][1]))
    await load_byte_step(dut, pack2_4bit(B[0][0], B[0][1]))
    await load_byte_step(dut, pack2_4bit(B[1][0], B[1][1]))

    await start_compute_step(dut)

    # Step until out_valid goes high, with timeout
    for _ in range(50):
        uio_val = dut.uio_out.value
        out_valid_bit = int(uio_val) >> 3 & 1 if uio_val.is_resolvable else -1
        if out_valid_bit == 1:
            break
        await step_pulse(dut, 0x40)
    else:
        assert False, "Timeout waiting for out_valid in step mode"

    results = []
    for k in range(4):
        results.append(int(dut.uo_out.value) & 0xFF)
        if k < 3:
            await step_pulse(dut, 0x40)

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
    assert int(dut.uio_oe.value) == 0x9C, \
        "uio_oe should be 0x9C (bits 7,4,3,2 out; 6,5,1,0 in)"


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
    """Overflow: (-8)×(-8) + (-8)×(-8) = 128 wraps to 0x80 in 8-bit output"""
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
async def test_all_negative(dut):
    """All -8 inputs — maximum negative values."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[-8, -8], [-8, -8]]
    B = [[-8, -8], [-8, -8]]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"all-neg: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_boundary_mix(dut):
    """Boundary mix of max positive and max negative."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[-8, 7], [-8, 7]]
    B = [[7, -8], [7, -8]]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply(dut, A, B)
    dut._log.info(f"boundary: got {results}, expected {expected}")
    assert results == expected


@cocotb.test()
async def test_step_mode(dut):
    """Manual step mode produces same results as free-running."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    A = [[3, 2], [-1, 4]]
    B = [[5, -2], [3, 1]]
    C = matmul_2x2(A, B)
    expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]

    results = await run_multiply_step(dut, A, B)
    dut._log.info(f"step mode: got {results}, expected {expected}")
    assert results == expected, f"step mode mismatch: got {results}, expected {expected}"


@cocotb.test()
async def test_ena_gating(dut):
    """Start is ignored when ena=0."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Load identity matrices
    await load_byte(dut, pack2_4bit(1, 0))
    await load_byte(dut, pack2_4bit(0, 1))
    await load_byte(dut, pack2_4bit(1, 0))
    await load_byte(dut, pack2_4bit(0, 1))

    # Assert start with ena=0
    dut.ena.value = 0
    dut.uio_in.value = 0x02
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 4)

    # busy_core (uio_out[2]) and out_busy (uio_out[4]) should still be 0
    uio = int(dut.uio_out.value)
    assert ((uio >> 2) & 1) == 0, "busy_core should be 0 when ena=0"
    assert ((uio >> 4) & 1) == 0, "out_busy should be 0 when ena=0"
    dut.ena.value = 1


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
        ([[2,3], [5,1]],
         [[6,2], [3,7]]),
    ]

    for A, B in cases:
        C = matmul_2x2(A, B)
        expected = [C[i][j] & 0xFF for i in range(2) for j in range(2)]
        results = await run_multiply(dut, A, B)
        dut._log.info(f"consecutive: got {results}, expected {expected}")
        assert results == expected, f"Mismatch: {results} vs {expected}"
