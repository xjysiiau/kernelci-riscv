# Regression pass-rate history

Runs: 4 | XFAIL = known upstream failure (expected) | XPASS = known failure fixed upstream

| test | 7.2.0<br>0821-073 | 7.2.0<br>0821-074 | 7.2.0<br>0821-074 | 7.2.0<br>0821-102 | pass% |
|---|---|---|---|---|---|
| cpuinfo | PASS | PASS | PASS | PASS | 100% |
| kselftest/abi/pointer_masking | FAIL | XFAIL | XFAIL | XFAIL | 75% |
| kselftest/hwprobe/cbo | PASS | PASS | PASS | PASS | 100% |
| kselftest/hwprobe/hwprobe | PASS | PASS | PASS | PASS | 100% |
| kselftest/hwprobe/which-cpus | PASS | PASS | PASS | PASS | 100% |
| kselftest/mm/run_mmap.sh | PASS | PASS | PASS | PASS | 100% |
| kselftest/sigreturn/sigreturn | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/v_initval | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/validate_v_ptrace | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/vstate_prctl | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/vstate_ptrace | PASS | PASS | PASS | PASS | 100% |
| vector | PASS | PASS | PASS | PASS | 100% |
| **overall** | FAIL | PASS | PASS | PASS | 75% |
