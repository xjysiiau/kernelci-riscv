Title: RISC-V Development Partners: local QEMU boot + kselftest pipeline
 seeking the upstream integration path

## Context

RISC-V Development Partners SOW:
https://github.com/riscv-admin/dev-partners/issues/49

Repo: https://github.com/xjysiiau/kernelci-riscv

I am working on a localized KernelCI pipeline for RISC-V targets
(x86 host cross-build, QEMU virt -cpu max as the test target, seeded
openKylin image as the boot target, -snapshot so the image is never
modified). Current state:

- boot test: cross-built kernel (v7.2.0-rc7, riscv defconfig) boots the
  test image to the login prompt; detection is login-prompt/serial based
  with timeout, producing structured result.json;
- functional tests: cpuinfo (asserts Vector/Hypervisor ISA extensions)
  and an RVV vector_add self-test (vsetvl/vle/vadd/vse, VLEN reported);
- kselftests: tools/testing/selftests/riscv (hwprobe/vector/sigreturn/mm/abi)
  built on the host and run inside the booted guest (10 binaries:
  9 pass, 1 known XFAIL - see below);
- config drift detection: 17-option required contract (Vector/virtio/ext4/
  serial/KVM etc.) + full config diff with FAIL/WARN/INFO levels;
- CI: GitHub Actions - cloud job (drift check + cross-build) plus a
  self-hosted runner (WSL) executing the full closed loop; per-run results
  are archived and a pass-rate trend table is auto-committed to the repo.

## Known finding

abi/pointer_masking "constraint" assertions fail on ZPM-capable platforms
(QEMU -cpu max): the test expects PMLEN round-up without
PR_TAGGED_ADDR_ENABLE, while the kernel resets PMLEN to 0 (commit
3033b2b1e3). Tracked as XFAIL; details:
https://github.com/xjysiiau/kernelci-riscv/blob/main/docs/findings-pointer-masking.md
(reporting to linux-riscv as well)

## Questions for the KernelCI community

1. What is the currently recommended path for adding a RISC-V QEMU test
   profile: Maestro config in kci-dev, or first publishing results via
   KCIDB from our own runner?
2. Is there existing RISC-V QEMU boot/kselftest coverage we should extend
   rather than duplicate?
3. Is there interest in registering our self-hosted machine as a pull lab
   for these tests?

## Status

Phase 1 (pipeline + boot test) done; Phase 2 (Vector functional tests,
kselftests, config drift detection) done except real-hardware
Hypervisor/KVM testing, for which we are looking for lab partners per the
SOW. Aiming for a Phase 3 upstream PR once the configuration format is
settled.
