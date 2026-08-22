# Regression pass-rate history

Runs: 8 | XFAIL = known upstream failure (expected) | XPASS = known failure fixed upstream

| test | 7.2.0<br>0821-073 | 7.2.0<br>0821-074 | 7.2.0<br>0821-074 | 7.2.0<br>0821-101 | 7.2.0<br>0821-102 | 7.2.0<br>0822-065 | 7.2.0<br>0822-071 | 7.2.0<br>0822-074 | pass% |
|---|---|---|---|---|---|---|---|---|---|
| cpuinfo | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/abi/pointer_masking | FAIL | XFAIL | XFAIL | XFAIL | XFAIL | XFAIL | XFAIL | XFAIL | 88% |
| kselftest/hwprobe/cbo | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/hwprobe/hwprobe | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/hwprobe/which-cpus | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/mm/run_mmap.sh | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/sigreturn/sigreturn | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/v_initval | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/validate_v_ptrace | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/vstate_prctl | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| kselftest/vector/vstate_ptrace | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| vector | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 100% |
| **overall** | FAIL | PASS | PASS | PASS | PASS | PASS | PASS | PASS | 88% |
