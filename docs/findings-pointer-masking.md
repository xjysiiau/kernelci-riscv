# Finding: riscv abi/pointer_masking selftest fails on ZPM-capable platforms

Status: reproducible on kernel 7.2.0-rc7 (defconfig) and mainline master (verified
by source comparison), QEMU virt `-cpu max`.

## Environment
- Host: x86_64 WSL2, qemu-system-riscv64 10.2.1
- Guest: openKylin 2.0 SP2 rootfs, kernel cross-built from torvalds/linux 7.2.0-rc7
  (`make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- defconfig`, CONFIG_RISCV_ISA_SUPM=y)
- QEMU `-cpu max` emulates the Smnpm/Ssnpm pointer-masking extensions, so the
  kernel exposes them via riscv_hwprobe.

## Symptom
`tools/testing/selftests/riscv/abi/pointer_masking` test_pmlen() fails every
"constraint" assertion for PMLEN=1..16:

```
not ok 5 PMLEN=1 constraint
not ok 8 PMLEN=2 constraint
...
not ok 23 PMLEN=7 constraint
...
```

"validity" assertions pass and "PR_GET_TAGGED_ADDR_CTRL" assertions pass,
which means `PR_SET_TAGGED_ADDR_CTRL` succeeds for every requested PMLEN but
`PR_GET_TAGGED_ADDR_CTRL` always reports an effective PMLEN of 0.

## Root cause
Test (`abi/pointer_masking.c`, test_pmlen):

```c
ret = prctl(PR_SET_TAGGED_ADDR_CTRL, request << PR_PMLEN_SHIFT, 0, 0, 0);
...
ksft_test_result(pmlen >= request, "PMLEN=%d constraint\n", request);
```

The test sets only the PMLEN field (no `PR_TAGGED_ADDR_ENABLE`) and expects the
kernel to round the request up to the nearest valid PMLEN and remember it.

Kernel (`arch/riscv/kernel/process.c`, set_tagged_addr_ctrl) — identical in
7.2.0-rc7 and master:

```c
/* Prefer the smallest PMLEN that satisfies the user's request ... */
pmlen = FIELD_GET(PR_PMLEN_MASK, arg);
if (pmlen == PMLEN_0) { ... }
else if (pmlen <= PMLEN_7 && have_user_pmlen_7) { pmlen = PMLEN_7; ... }
else if (pmlen <= PMLEN_16 && have_user_pmlen_16) { pmlen = PMLEN_16; ... }
else return -EINVAL;

if (!(arg & PR_TAGGED_ADDR_ENABLE)) {
	pmlen = PMLEN_0;              /* commit 3033b2b1e3, 2026-03-22:
	                                 "riscv: Reset pmm when
	                                  PR_TAGGED_ADDR_ENABLE is not set" */
	pmm = ENVCFG_PMM_PMLEN_0;
}
...
mm->context.pmlen = pmlen;
```

Without `PR_TAGGED_ADDR_ENABLE` the kernel resets the effective PMLEN to 0 and
returns success, contradicting the test's expectation.

## Why upstream CI does not see this
On platforms without the ZPM extension (`RISCV_ISA_EXT_SUPM` absent) the kernel
rejects the prctl, the test takes the skip path, and all assertions are SKIP.
Hardware with ZPM is still rare, while QEMU `-cpu max` emulates it — so the
failure only shows up on virtual ZPM-capable targets such as this one.

## Impact / suggested action
- Low practical impact (pointer masking is niche), but the test and the kernel
  disagree about the PMLEN-only set semantics; one of them should change.
- Candidate upstream report: kernelci@lists.linux.dev / linux-riscv@lists.infradead.org.

## Repro (using this repo)
```bash
# in WSL, after scripts/seed-test-image.sh:
scripts/run-closed-loop.sh
# see build/closed-loop/guest-results/kselftest/abi_pointer_masking.log
```
