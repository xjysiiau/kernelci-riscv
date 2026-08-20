# KernelCI RISC-V 本地化测试流水线 — 项目报告

> 对应 SOW: [riscv-admin/dev-partners#49 — KernelCI: Statement of Work](https://github.com/riscv-admin/dev-partners/issues/49)
> 仓库: https://github.com/xjysiiau/kernelci-riscv
> 日期: 2026-08-20

## 1. 项目概述

### 1.1 背景

RISC-V 架构规范和软件使能 profile(如 RVA23)持续成熟,但 Linux 主线对 RISC-V
的持续集成测试仍存在缺口:架构扩展(侧信道、Vector、Hypervisor 等)与不同
微架构行为差异缺乏一致、可重复的自动化验证。KernelCI 是 Linux 社区的持续
内核测试基础设施,本项目的目标是把 RISC-V 特有的测试需求以**本地化、可复现、
可上游化**的方式接入该体系。

### 1.2 目标

1. 在 x86 宿主上搭建 RISC-V 内核的**全自动测试流水线**(构建 → 启动 → 测试 → 报告);
2. 覆盖 SOW 要求的 **Vector/Hypervisor** 等目标扩展的回归测试(QEMU 虚拟化目标);
3. 实现**配置漂移检测**,防止测试基线被悄悄破坏;
4. 以开源形式沉淀,为 Phase 3 的 KernelCI 上游集成做准备。

### 1.3 完成度对照(SOW 四阶段)

| 阶段 | 要求 | 状态 |
|---|---|---|
| Phase 1 | 容器化流水线、tracking issue、首个验证脚本 | ✅ 完成(容器化方案已验证,主流程脚本化) |
| Phase 2 | 配置漂移检测 + Vector/Hypervisor 回归测试 | 🟡 Vector 完成;Hypervisor 待真实硬件 |
| Phase 3 | 向 KernelCI 主线提 PR | ⬜ 待社区接洽(findings 已备) |
| Phase 4 | runbook / 博客 / demo / 徽章 | 🟡 runbook 已备(附录),其余待做 |

## 2. 技术架构

```
┌─ Windows 11 ─────────────────────────────── 控制台 / 仓库管理
│
├─ WSL2 Ubuntu (x86_64) ────────────────────── 构建 + 测试宿主
│     工具: qemu-system-riscv64 10.2 / riscv64-linux-gnu-gcc 15.2 / docker 29
│     职责: 交叉编译内核、编排 QEMU、漂移检测、汇总报告
│
│   ┌─ QEMU (TCG) ──────────────────────────── 虚拟化测试目标
│   │
│   ├─ Ubuntu 25.04 riscv64 (开发机) ──────── 功能测试原生环境
│   │     ISA: rv64imafdcvh (+V/H 扩展)  8核/12G
│   │
│   └─ openkylin-test.img (测试靶子) ──────── 每次 -snapshot 启动,零污染
│         被「新编译的内核」直接启动(绕过 U-Boot)
│
└─ GitHub: xjysiiau/kernelci-riscv ─────────── 代码与基线配置
```

**核心设计决策**:
- 采用 **x86 宿主交叉编译 + QEMU TCG 模拟 riscv64** 的标准 KernelCI 模型,放弃
  "RISC-V 内再嵌套 QEMU"方案(TCG 套 TCG 性能不可用,且非上游模型);
- 测试靶子使用**闲置的 openkylin.img 复制品**,启动一律加 `-snapshot`,
  任何写操作退出即丢弃——测试内核的 bug 永远不会污染镜像;
- 主力开发环境(ubuntu.img)全程不参与测试。

## 3. 交付物(仓库结构)

```
kernelci-riscv/
├── configs/
│   ├── riscv-qemu/defconfig          # 基准内核配置(与构建工具链同步)
│   └── riscv-qemu/required-opts.txt  # 17 项必需选项合同(V/virtio/ext4/串口/KVM...)
├── scripts/
│   ├── build-kernel.sh               # 交叉编译(ARCH=riscv, 环境变量可覆盖)
│   ├── boot-test.sh                  # 自动 boot 测试(-snapshot + 登录提示判定)
│   ├── check-config-drift.sh         # 配置漂移检测(合同层 + 全量 diff 层)
│   ├── seed-test-image.sh            # 一次性:播种测试镜像 SSH 公钥
│   └── run-closed-loop.sh            # ★ 闭环流水线:一条命令跑完整测试
├── tests/
│   ├── run-tests.sh                  # 统一入口 → build/results.json
│   ├── cpuinfo/run.sh                # ISA 解析,断言 v/h 扩展
│   ├── vector/{run.sh, vector_add.c} # RVV 向量加法自测(VLEN 读取)
│   └── kselftest/run.sh              # 内核官方 selftests/riscv 构建+运行
├── docs/
│   ├── findings-pointer-masking.md   # 上游 bug 报告底稿
│   └── project-report.md             # 本文档
└── configs/dsh-test.pub              # 测试 guest SSH 公钥
```

## 4. 流水线设计

### 4.1 闭环流水线(scripts/run-closed-loop.sh)

```
[0]  配置漂移检查(FAIL 级直接中止)
[1]  用新内核 + -snapshot 启动测试镜像(独立 SSH 端口)
[2]  轮询等待 guest SSH 上线(超时判定 boot FAIL)
[3]  scp 推送测试套件(预编译的静态二进制)
[4]  guest 内执行 cpuinfo / vector / kselftest
[5]  拉回结果 → 输出 verdict
```

### 4.2 boot 判定(scripts/boot-test.sh)

- 判定依据: 串口出现 `login:` 提示或 systemd `Login Prompts` 目标
  (而非开机最早的 "Linux version" —— 那会漏掉 init 之前的 panic);
- 超时机制 + `-no-reboot` 防 panic 重启循环;
- 产出结构化 `result.json`(内核版本/根文件系统/判定依据/时间戳)。

### 4.3 配置漂移检测(scripts/check-config-drift.sh)

| 层级 | 内容 | 触发 |
|---|---|---|
| 必需选项合同 | 17 项关键配置(ISA_V/SUPM/ZICBOM/virtio/ext4/串口/KVM) | 缺失或变值 → FAIL |
| 全量 diff | 基准 defconfig vs 实际 .config | 丢失/禁用 → FAIL;变值 → WARN;新增 → INFO |

实际使用中即发现:基准 defconfig 由 gcc 14.2 生成,而交叉编译使用 gcc 15.2,
存在 4 项工具链版本漂移 + 9 项新增选项——已同步基线。模拟关闭
`CONFIG_RISCV_ISA_V` 的漂移攻击被两层同时捕获。

## 5. 测试矩阵与结果

### 5.1 boot 测试
| 内核 | 目标 | 结果 |
|---|---|---|
| 7.2.0-rc7(defconfig,交叉编译) | openkylin-test.img | ✅ 到达 `openkylin login:` |

### 5.2 功能测试(在 7.2.0-rc7 新内核的 guest 内执行)

| 测试 | 内容 | 结果 |
|---|---|---|
| cpuinfo | 解析 ISA,断言 V/H 扩展 | ✅ PASS |
| vector | RVV 向量加法(vsetvl/vle/vadd/vse, VLEN=128bit) | ✅ PASS |
| kselftest/hwprobe | 扩展探测 syscall | ✅ PASS |
| kselftest/cbo, which-cpus | 缓存块操作/每核一致性 | ✅ PASS |
| kselftest/vstate_prctl | 向量状态 prctl 语义(13 项) | ✅ PASS |
| kselftest/v_initval, vstate_ptrace, validate_v_ptrace | 向量初始化/ptrace | ✅ PASS |
| kselftest/sigreturn | 信号返回向量状态恢复 | ✅ PASS |
| kselftest/mm(mmap 双布局) | 栈限制无穷时 bottom-up | ✅ PASS |
| kselftest/abi/pointer_masking | 指针掩码 prctl 语义 | ❌ FAIL(见 §6) |

**总计: 9/10 通过,1 项真实失败,0 跳过。**

### 5.3 同一套件在 Ubuntu 6.14 开发机上的对照
✅ 全部通过(pointer_masking 的两组约束测试在该内核上被 SKIP——这正是 §6 的关键线索)。

## 6. 关键发现:abi/pointer_masking selftest 在上游主线同样失败

### 6.1 症状
`test_pmlen()` 对 PMLEN=1..16 的每一个 "constraint" 断言全部失败
("validity" 断言却全部通过),即内核**接受**任意 PMLEN 请求,但
`PR_GET_TAGGED_ADDR_CTRL` 报告的实际生效值恒为 0。

### 6.2 根因(逐行比对确认)
- 测试(7.2-rc7 与 master 相同):只设置 PMLEN 字段(不带
  `PR_TAGGED_ADDR_ENABLE`),期望内核**向上取整并记住**请求
  (`pmlen >= request`);
- 内核(7.2-rc7 与 master 相同):`set_tagged_addr_ctrl()` 在未设置 ENABLE
  时执行 `pmlen = PMLEN_0`(commit `3033b2b1e3`,2026-03-22,
  "riscv: Reset pmm when PR_TAGGED_ADDR_ENABLE is not set")并返回成功。

### 6.3 为什么上游 CI 看不到
无 ZPM(指针掩码)扩展的平台上,内核直接拒绝 prctl,测试进入 SKIP 分支。
**QEMU `-cpu max` 恰好模拟了 Smnpm/Ssnpm**,使该矛盾暴露。真实硬件大多
无 ZPM,故该失败是"虚拟 ZPM 目标"特有问题。

### 6.4 影响与建议
低实际影响(指针掩码尚属小众特性),但测试与内核对 "仅设 PMLEN" 的语义
存在分歧,二者之一应修改。建议向 `kernelci@lists.linux.dev` /
`linux-riscv@lists.infradead.org` 报告。完整底稿见
[docs/findings-pointer-masking.md](findings-pointer-masking.md)。

## 7. 工程经验(踩坑记录)

1. **selftests 必须显式传 `ARCH=riscv`**:Makefile 用 `uname -m` 判断架构,
   riscv64 匹配不上 `riscv`,会静默什么都不编;
2. **vector 测试须在其构建目录内运行**:它们 fork 子进程 exec 同目录辅助程序;
3. **mm 测试须经 `run_mmap.sh`**:`mmap_bottomup` 依赖 `ulimit -s unlimited`
   才切 bottom-up 布局;
4. **GCC 的 RVV 内建函数带 `__riscv_` 前缀**(`__riscv_vadd_vv_i32m1`),与
   Clang 裸名不同;
5. **`/proc/cpuinfo` 的 isa 行**是 `isa\t\t: value` 格式,按列取值会取到冒号;
6. **交叉编译产物用静态链接**,避免 guest glibc 版本差异;
7. WSL 下 `sudo` 前缀运行脚本会使 `$HOME` 变为 `/root`,需用 `SUDO_USER` 解析;
8. Windows ssh 传脚本经 base64 过 stdin,规避 PowerShell 管道 CRLF 问题。

## 8. 后续计划

1. [ ] 发布 kernelci-project tracking issue(草稿已备)
2. [ ] 向 KernelCI / linux-riscv 报告 pointer-masking findings
3. [ ] Hypervisor(KVM)真机测试:RISE / 生态实验室硬件
4. [ ] 回归通过率历史统计(results.json 趋势)
5. [ ] 容器化整合(podman 方案已验证)与 GitHub Actions
6. [ ] Phase 3:KernelCI Maestro/kci-dev 集成 PR
7. [ ] 博客 / demo 视频 / LF 徽章

## 附录:复现指南

### A. 一次性准备(需要 sudo)
```bash
# WSL 内:
git clone https://github.com/xjysiiau/kernelci-riscv.git ~/kernelci-riscv
git clone --depth=1 https://github.com/torvalds/linux.git ~/linux
sudo apt install gcc-riscv64-linux-gnu qemu-system-riscv flex bison bc libssl-dev libelf-dev
~/kernelci-riscv/scripts/seed-test-image.sh   # 播种 openkylin 测试镜像
```

### B. 全自动闭环(无需 sudo)
```bash
cd ~/kernelci-riscv
scripts/run-closed-loop.sh
# 输出: BOOT OK → guest 测试结果 → OVERALL 判定
```

### C. 单独运行某一层
```bash
scripts/check-config-drift.sh      # 配置漂移
scripts/boot-test.sh               # boot 测试
cd tests && ./run-tests.sh         # 功能测试(riscv64 上原生)
```
