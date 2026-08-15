#!/bin/bash

set -euo pipefail


########################################
# KernelCI RISC-V Kernel Build Script
########################################


# 项目根目录
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)


# Linux源码路径
# 可以通过环境变量覆盖
KERNEL_SRC=${KERNEL_SRC:-"$HOME/linux"}


# 编译输出目录
BUILD_DIR=${BUILD_DIR:-"$PROJECT_ROOT/build"}


# Kernel配置
CONFIG=${CONFIG:-"$PROJECT_ROOT/configs/riscv-qemu/defconfig"}


# 编译参数

ARCH=riscv

CROSS_COMPILE=${CROSS_COMPILE:-riscv64-linux-gnu-}

JOBS=${JOBS:-$(nproc)}



echo "======================================"
echo " KernelCI RISC-V Kernel Build"
echo "======================================"

echo "Kernel source:"
echo "  $KERNEL_SRC"

echo "Build directory:"
echo "  $BUILD_DIR"

echo "Config:"
echo "  $CONFIG"

echo "Compiler:"
echo "  $CROSS_COMPILE"

echo



########################################
# 检查环境
########################################


if ! command -v ${CROSS_COMPILE}gcc >/dev/null
then
    echo "ERROR: RISC-V compiler not found"
    echo "Install:"
    echo "sudo apt install gcc-riscv64-linux-gnu"
    exit 1
fi


if [ ! -d "$KERNEL_SRC" ]
then
    echo "ERROR: Linux kernel source not found"
    exit 1
fi


if [ ! -f "$CONFIG" ]
then
    echo "ERROR: Kernel config not found"
    exit 1
fi



########################################
# 准备编译目录
########################################


mkdir -p "$BUILD_DIR"



########################################
# 导入配置
########################################


echo "[1/3] Prepare kernel config"


cp "$CONFIG" "$BUILD_DIR/.config"



########################################
# 编译
########################################


echo "[2/3] Build kernel"


make \
-C "$KERNEL_SRC" \
O="$BUILD_DIR" \
ARCH="$ARCH" \
CROSS_COMPILE="$CROSS_COMPILE" \
-j"$JOBS" \
olddefconfig Image



########################################
# 检查结果
########################################


echo "[3/3] Check kernel image"


IMAGE="$BUILD_DIR/arch/riscv/boot/Image"


if [ -f "$IMAGE" ]
then

    echo "Kernel Image generated:"
    ls -lh "$IMAGE"

#!/bin/bash

set -euo pipefail


########################################
# KernelCI RISC-V Kernel Build Script
########################################


# 项目根目录
PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)


# Linux源码路径
# 可以通过环境变量覆盖
KERNEL_SRC=${KERNEL_SRC:-"$HOME/linux"}


# 编译输出目录
BUILD_DIR=${BUILD_DIR:-"$PROJECT_ROOT/build"}


# Kernel配置
CONFIG=${CONFIG:-"$PROJECT_ROOT/configs/riscv-qemu/defconfig"}


# 编译参数

ARCH=riscv

CROSS_COMPILE=${CROSS_COMPILE:-riscv64-linux-gnu-}

JOBS=${JOBS:-$(nproc)}



echo "======================================"
echo " KernelCI RISC-V Kernel Build"
echo "======================================"

echo "Kernel source:"
echo "  $KERNEL_SRC"

echo "Build directory:"
echo "  $BUILD_DIR"

echo "Config:"
echo "  $CONFIG"

echo "Compiler:"
echo "  $CROSS_COMPILE"

echo



########################################
# 检查环境
########################################


if ! command -v ${CROSS_COMPILE}gcc >/dev/null
then
    echo "ERROR: RISC-V compiler not found"
    echo "Install:"
    echo "sudo apt install gcc-riscv64-linux-gnu"
    exit 1
fi


if [ ! -d "$KERNEL_SRC" ]
then
    echo "ERROR: Linux kernel source not found"
    exit 1
fi


if [ ! -f "$CONFIG" ]
then
    echo "ERROR: Kernel config not found"
    exit 1
fi



########################################
# 准备编译目录
########################################


mkdir -p "$BUILD_DIR"



########################################
# 导入配置
########################################


echo "[1/3] Prepare kernel config"


cp "$CONFIG" "$BUILD_DIR/.config"



########################################
# 编译
########################################


echo "[2/3] Build kernel"


make \
-C "$KERNEL_SRC" \
O="$BUILD_DIR" \
ARCH="$ARCH" \
CROSS_COMPILE="$CROSS_COMPILE" \
-j"$JOBS" \
olddefconfig Image



########################################
# 检查结果
########################################


echo "[3/3] Check kernel image"


IMAGE="$BUILD_DIR/arch/riscv/boot/Image"


if [ -f "$IMAGE" ]
then

    echo "Kernel Image generated:"
    ls -lh "$IMAGE"

#!/bin/bash

set -euo pipefail

PROJECT_ROOT=$(cd "$(dirname "$0")/.." && pwd)

KERNEL_SRC=${KERNEL_SRC:-"$HOME/linux"}

BUILD_DIR=${BUILD_DIR:-"$PROJECT_ROOT/build"}

CONFIG=${CONFIG:-"$PROJECT_ROOT/configs/riscv-qemu/defconfig"}

ARCH=riscv

CROSS_COMPILE=${CROSS_COMPILE:-riscv64-linux-gnu-}

JOBS=${JOBS:-$(nproc)}



echo "======================================"
echo " KernelCI RISC-V Kernel Build"
echo "======================================"

echo "Kernel source:"
echo "  $KERNEL_SRC"

echo "Build directory:"
echo "  $BUILD_DIR"

echo "Config:"
echo "  $CONFIG"

echo "Compiler:"
echo "  $CROSS_COMPILE"

echo



if ! command -v ${CROSS_COMPILE}gcc >/dev/null
then
    echo "ERROR: RISC-V compiler not found"
    echo "Install:"
    echo "sudo apt install gcc-riscv64-linux-gnu"
    exit 1
fi


if [ ! -d "$KERNEL_SRC" ]
then
    echo "ERROR: Linux kernel source not found"
    exit 1
fi


if [ ! -f "$CONFIG" ]
then
    echo "ERROR: Kernel config not found"
    exit 1
fi


mkdir -p "$BUILD_DIR"

echo "[1/3] Prepare kernel config"


cp "$CONFIG" "$BUILD_DIR/.config"

echo "[2/3] Build kernel"


make \
-C "$KERNEL_SRC" \
O="$BUILD_DIR" \
ARCH="$ARCH" \
CROSS_COMPILE="$CROSS_COMPILE" \
-j"$JOBS" \
olddefconfig Image

echo "[3/3] Check kernel image"


IMAGE="$BUILD_DIR/arch/riscv/boot/Image"


if [ -f "$IMAGE" ]
then

    echo "Kernel Image generated:"
    ls -lh "$IMAGE"

else

    echo "ERROR: Image not generated"
    exit 1

fi



echo

echo "======================================"
echo " Build SUCCESS"
echo "======================================"
