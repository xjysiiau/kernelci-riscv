# Prepared patches for the pointer_masking finding

See docs/findings-pointer-masking.md for the finding, the experimental
results below, and the upstream discussion
(linux-riscv@lists.infradead.org, 2026-08-22).

All experiments were run on kernel v7.2.0-rc7 (defconfig, SUPM=y) booting
a seeded openKylin image on QEMU virt -cpu max, with the selftest built
from the same tree.

## Experimental results (each variant was built and run in the guest)

| Variant | Result in guest |
|---|---|
| unpatched | test_pmlen fails every "constraint" assertion (PMLEN=1..16), PR_GET always reports PMLEN=0. Reproduces upstream behavior. |
| A: test passes PR_TAGGED_ADDR_ENABLE | **SIGSEGV (rc=139)** after the first successful SET: enabling the ABI applies pointer masking to the test process itself; its untagged stack addresses (top bits set) become invalid, so the next access faults. The TAP log stops after PMLEN=0 (skipped, EINVAL). |
| B: kernel remembers rounded PMLEN without touching envcfg | **No effect** — still fails identically. get_tagged_addr_ctrl() derives the effective PMLEN from envcfg.PMM (hardware register), not from mm->context.pmlen; the code comment states the invariant ("mm context's pmlen is set only when the tagged address ABI is enabled"). B would also break that invariant for uaccess/mmap masking. **Retired.** |

## Conclusion

The test's expectation (PMLEN-only set is rounded and remembered) contradicts
the kernel's documented, coherent design:

- set_tagged_addr_ctrl(): PMLEN-only request resets the effective PMLEN to 0
  (commit 3033b2b1e3); PMLEN is applied only together with
  PR_TAGGED_ADDR_ENABLE;
- get_tagged_addr_ctrl(): effective PMLEN is read from envcfg.PMM; the
  ENABLE flag is reported from mm->context.pmlen.

The correct fix is a **test rewrite**: probe the round-up behavior in a way
that survives having the ABI enabled, e.g. a child process performing the
SET + GET with raw syscalls (no libc/stack access after enabling) and
reporting the result via its exit status. The kernel should not change.

The naive test-side patch (`0001-selftests-riscv-pointer_masking-pass-ENABLE.patch`)
is kept only as a record of the failed experiment (it crashes); the kernel
patch (`0001-riscv-alternative-remember-pmlen.patch`) is kept as a record of
the other failed experiment (it has no effect and is undesirable). Neither
should be sent upstream. Send the rewritten-test patch once written (to be
done together with maintainer guidance).
