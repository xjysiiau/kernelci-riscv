# Regression pass-rate history

Runs: 3 | XFAIL = known upstream failure (expected) | XPASS = known failure fixed upstream

| test | 7.2.0<br>0821-073 | 7.2.0<br>0821-074 | 7.2.0<br>0821-074 | pass% |
|---|---|---|---|---|
| cpuinfo | PASS | PASS | PASS | 100% |
| kselftest/abi/pointer_masking | FAIL | XFAIL | XFAIL | 67% |
| kselftest/hwprobe/cbo | PASS | PASS | PASS | 100% |
| kselftest/hwprobe/hwprobe | PASS | PASS | PASS | 100% |
| kselftest/hwprobe/which-cpus | PASS | PASS | PASS | 100% |
| kselftest/mm/run_mmap.sh | PASS | PASS | PASS | 100% |
| kselftest/sigreturn/sigreturn | PASS | PASS | PASS | 100% |
| kselftest/vector/v_initval | PASS | PASS | PASS | 100% |
| kselftest/vector/validate_v_ptrace | PASS | PASS | PASS | 100% |
| kselftest/vector/vstate_prctl | PASS | PASS | PASS | 100% |
| kselftest/vector/vstate_ptrace | PASS | PASS | PASS | 100% |
| vector | PASS | PASS | PASS | 100% |
| **overall** | FAIL | PASS | PASS | 67% |
