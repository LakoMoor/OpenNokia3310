# Virtual SIM security and scope

This is a synthetic SIM inside FPGA. It contains no real subscriber secret,
cannot authenticate to a real carrier and must not be confused with an eSIM.
Original firmware accesses it through the modeled SIMI UART and T=0 APDUs.

## Test credentials

| Code | Initial value | Attempts |
| --- | --- | --- |
| PIN1 | 1234 (disabled by default) | 3 |
| PIN2 | 5678 | 3 |
| PUK1 / PUK2 | 12345678 | 10 each |

Codes are stored as eight ASCII bytes padded with FF. The implemented CHV
operations are VERIFY (20), CHANGE (24), DISABLE (26), ENABLE (28) and UNBLOCK
(2C). Directory responses report current enabled status and remaining retries.
Incorrect attempts return 9804 until exhausted, then 9840. Operations in
contradiction with enabled/disabled state return 9808. Header parameter/length
errors are rejected. PIN1 protects IMSI, ADN and SMS access when enabled.

Card power cycling and warm FPGA reset clear session verification while
retaining code changes, enable state and retry counters. FPGA reconfiguration
restores default credentials: this state is not yet stored in SPI flash.
PIN/PUK state does not provide a GSM authentication algorithm or virtual
network registration. Other SIM access conditions and complete filesystem
selection semantics still require qualification.

Directed tests cover CHV1/PIN2, change/disable/unblock, retry blocking across
reset, PUK counters and end-to-end APDU access protection. They are not proof
that every original Nokia SIM settings screen works yet.

Command formats/status semantics were checked against
[ETSI TS 151 011 v4.1.0](https://www.etsi.org/deliver/etsi_ts/151000_151099/151011/04.01.00_60/ts_151011v040100p.pdf)
and the CHV conformance cases in
[3GPP TS 51.017](https://www.3gpp.org/ftp/tsg_ct/TSG_CT/TSGC_28/Docs/PDF/CP-050212.pdf).
