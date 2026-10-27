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

rtl/datapath/arm7tdmis_multiplier.sv: represent each 32-bit operand as a signed
33-bit value with a conditional sign bit, multiply to 66 bits and retain the
low 64 bits before accumulation. This is equivalent to the former extended
64x64 expression for signed/unsigned short/long multiply and accumulate, but
allows Gowin to infer a single 36x36 DSP instead of an oversized product.
Flag and cycle-count logic is unchanged. `python tools/test.py --case multiplier`
compares all result/flag/cycle outputs against the old expression for 512
boundary cases and 20,000 deterministic randomized input combinations.
Actual board resource/timing and original-ROM checks remain separate gates.

rtl/datapath/arm7tdmis_regfile.sv: replace reset writes to all data words with
31 architectural validity bits. Reads of unwritten words return zero; reset
clears validity synchronously, preserving the prior visible reset behavior.
The data array has one explicit write address/data port, with unchanged priority
(save state, debug, enabled architectural write), allowing LUT RAM inference.
PC handling, all banks, debug reads, STATE_RDATA and VER_GPRS use the same visible
values; Nokia's simulation trace also masks invalid raw words. Raw RAM contents
are deliberately unspecified after reset and must not be used as architectural
state. `python tools/test.py --case regfile` tests all 30 restore slots and
5,000 deterministic randomized cycles, including resets, bank/PC/force-user
reads, debug while CLKEN=0, write priority and physical-state snapshots.
