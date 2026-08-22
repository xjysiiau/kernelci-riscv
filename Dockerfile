# KernelCI RISC-V pipeline environment box (x86 build host).
# Contains the full cross toolchain + QEMU so the pipeline can run anywhere.
# The repo, kernel source and test images are mounted at runtime.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc-riscv64-linux-gnu make \
        flex bison bc libssl-dev libelf-dev \
        qemu-system-misc opensbi \
        openssh-client rsync python3 curl git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
# Mount at runtime (see scripts/docker-run-pipeline.sh):
#   /work/kernelci-riscv  <- this repo
#   /work/linux           <- kernel source tree
#   /work/images          <- seeded test image dir
CMD ["bash"]
