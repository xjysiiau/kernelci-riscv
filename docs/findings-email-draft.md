Subject: riscv: abi/pointer_masking kselftest fails on ZPM-capable platforms
 (test expects PMLEN round-up without PR_TAGGED_ADDR_ENABLE)

Hi all,

While building a local KernelCI-style testing pipeline for RISC-V
(QEMU virt -cpu max, kernel v7.2.0-rc7, riscv defconfig), the
tools/testing/selftests/riscv/abi/pointer_masking test fails every
"constraint" assertion for PMLEN=1..16:

    not ok 5 PMLEN=1 constraint
    ...
    not ok 23 PMLEN=7 constraint

while the "validity" assertions pass. PR_SET_TAGGED_ADDR_CTRL returns 0
for every requested PMLEN, but PR_GET_TAGGED_ADDR_CTRL always reports
an effective PMLEN of 0.

Root cause appears to be a mismatch between the test's expectation and
the kernel's semantics, both present in v7.2.0-rc7 and current master:

- test (test_pmlen): sets only the PMLEN field (without
  PR_TAGGED_ADDR_ENABLE) and asserts the effective PMLEN is rounded up
  to >= the requested value;

- kernel (arch/riscv/kernel/process.c, set_tagged_addr_ctrl): when
  PR_TAGGED_ADDR_ENABLE is not set, resets pmlen to PMLEN_0 and returns
  success. This comes from commit 3033b2b1e3 ("riscv: Reset pmm when
  PR_TAGGED_ADDR_ENABLE is not set").

Why upstream CI does not see this: on platforms without the ZPM
extension the kernel rejects the prctl, so the test takes the skip
path. QEMU -cpu max emulates Smnpm/Ssnpm, which exposes the mismatch;
most real hardware lacks ZPM.

Questions:
1. Is the intended semantics of PR_SET_TAGGED_ADDR_CTRL with only PMLEN
   set (no ENABLE) to remember the rounded PMLEN, or to reset it to 0?
2. Depending on the answer, either the test should pass
   PR_TAGGED_ADDR_ENABLE, or the kernel should keep the rounded PMLEN.

Full details, reproducer, and the failure tracked as XFAIL in our CI:
https://github.com/xjysiiau/kernelci-riscv/blob/main/docs/findings-pointer-masking.md

Best regards,
[Your Name]
