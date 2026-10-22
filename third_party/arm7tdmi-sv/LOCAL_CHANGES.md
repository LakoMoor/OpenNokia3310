# Local integration change

Base: birdybro/arm7tdmi-sv commit 2b350d9c3902062329d9fdc55432fd4080bd88c9.

rtl/core/arm7tdmis_core_pipelined.sv: ordinary IRQ/FIQ entry is recognized
before the next instruction in S_EXEC. Exception entry cancels any decoded
multicycle transition. It no longer coincides with a prior load/multiply
register writeback: that boundary shares one register-file write port and
previously lost the exception LR while changing the normal destination bank.

Reproducer: python tools/test.py --case arm_fiq. Original RTL fails with
FIQ LR=0; this change preserves LR=0x5c, commits the stalled load to user r8,
returns from FIQ and resumes the interrupted stream. The test asserts FIQ
while an external-memory load is stalled. This is directed integration
evidence, not complete ARM architectural or cycle conformance sign-off.
