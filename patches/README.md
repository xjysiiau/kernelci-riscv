# Prepared patches for the pointer_masking finding

See docs/findings-pointer-masking.md for the finding and the upstream
discussion (linux-riscv@lists.infradead.org, 2026-08-22).

Both patches are generated against torvalds/linux v7.2.0-rc7 (plain
`git diff` output; apply with `git am` or `patch -p1` from the kernel
tree root).

## A. Test-side fix (recommended to send first)

`0001-selftests-riscv-pointer_masking-pass-ENABLE.patch`

The kernel treats a PMLEN-only `PR_SET_TAGGED_ADDR_CTRL` as "reset to 0"
(commit 3033b2b1e3), so probing the PMLEN round-up behavior requires
passing `PR_TAGGED_ADDR_ENABLE`. With this patch:

- test_pmlen sets PR_TAGGED_ADDR_ENABLE for every request, so the kernel's
  round-up logic (request <= 7 -> PMLEN_7, <= 16 -> PMLEN_16) is actually
  exercised and the "constraint" assertions pass;
- request = 0 combined with ENABLE is rejected by the kernel (-EINVAL,
  "ABI cannot be enabled when PMLEN == 0"), so PMLEN=0 is reported as
  SKIP — consistent with test_tagged_addr_abi()'s existing expectation.

## B. Kernel-side alternative (only if maintainers prefer the test's reading)

`0001-riscv-alternative-remember-pmlen.patch`

Keeps the rounded PMLEN in mm->context.pmlen (so PR_GET reports the
rounded value, satisfying the test as written) but still leaves
envcfg.PMM at PMLEN_0 while the tagged-address ABI is not enabled,
preserving the security intent of commit 3033b2b1e3. This changes the
prctl ABI semantics and requires maintainer review before sending.
