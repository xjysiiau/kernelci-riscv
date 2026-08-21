# Regression pass-rate history

Runs: 1 | XFAIL = known upstream failure (expected) | XPASS = known failure fixed upstream

| test | 7.2.0<br>0821-073 | pass% |
|---|---|---|
| cpuinfo | PASS | 100% |
| kselftest/abi/pointer_masking | FAIL | 0% |
| kselftest/hwprobe/cbo | PASS | 100% |
| kselftest/hwprobe/hwprobe | PASS | 100% |
| kselftest/hwprobe/which-cpus | PASS | 100% |
| kselftest/mm/run_mmap.sh | PASS | 100% |
| kselftest/sigreturn/sigreturn | PASS | 100% |
| kselftest/vector/v_initval | PASS | 100% |
| kselftest/vector/validate_v_ptrace | PASS | 100% |
| kselftest/vector/vstate_prctl | PASS | 100% |
| kselftest/vector/vstate_ptrace | PASS | 100% |
| vector | PASS | 100% |
| **overall** | FAIL | 0% |
