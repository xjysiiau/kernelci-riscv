#!/bin/bash

set -e

KERNEL_SRC=$HOME/linux

BUILD_DIR=$HOME/kernelci-riscv/build

ARCH=riscv

CROSS_COMPILE=riscv64-linux-gnu-

echo "=============================="
echo " Build RISC-V Linux Kernel"
echo "=============================="


mkdir -p $BUILD_DIR


echo "[1/3] Copy kernel config"

cp configs/riscv-qemu/defconfig \
$KERNEL_SRC/.config


echo "[2/3] Build Image"


make -C $KERNEL_SRC \
ARCH=$ARCH \
CROSS_COMPILE=$CROSS_COMPILE \
-j$(nproc) \
Image


echo "[3/3] Result"


ls -lh \
$KERNEL_SRC/arch/riscv/boot/Image


echo "Build success!"
