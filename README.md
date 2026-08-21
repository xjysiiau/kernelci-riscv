# KernelCI RISC-V 本地化测试流水线实践方案

v1 ｜ 2026-08-20

## 核心结论

RISC-V 架构规范在成熟,但 Linux 主线缺一套持续、可复现的 RISC-V 内核测试。本方案用「x86 交叉编译 + QEMU 模拟」把测试做成一条命令完成的闭环:编译内核 → 检查配置漂移 → 启动测试镜像 → 在 guest 里跑扩展测试 → 拉回报告。测试靶子用闲置镜像的副本,启动永远加 `-snapshot`(写入即弃),主力环境零风险。已实测:boot 通过、cpuinfo/Vector 通过、内核官方 selftests 10 项 9 过 1 挂——那 1 挂(pointer_masking)是上游主线至今存在的测试↔内核语义矛盾,只在 QEMU 模拟的指针掩码(ZPM)平台上暴露,已写成 findings 底稿。

## 关键事实

| 事实 | 数值(以仓库实测为准) |
|---|---|
| 测试内核 | torvalds/linux 7.2.0-rc7,riscv defconfig |
| 编译方式 | WSL x86 交叉编译,riscv64-linux-gnu-gcc 15.2 |
| 虚拟化 | qemu-system-riscv64 10.2(TCG,`-cpu max` 含 V/H/ZPM 扩展) |
| 测试靶子 | openkylin-test.img(6GB 副本,每次 `-snapshot`) |
| boot 判定 | 串口出现 `login:` / systemd `Login Prompts`(不用最早的 "Linux version") |
| selftests 结果 | 10 项 9 过 1 挂 0 跳过(7.2.0-rc7 guest 内实测) |
| 必需配置合同 | 17 项(V/virtio/ext4/串口/KVM 等),漂移即 FAIL |
| CI | GitHub Actions 双流水线:云端 light(漂移+交叉编译)+ WSL self-hosted runner heavy(完整闭环) |
| 待实测 | Hypervisor(KVM)真机、回归通过率历史 |

## 分层能力

| 层 | 做法 | 状态 |
|---|---|---|
| boot 测试 | `scripts/boot-test.sh`:`-snapshot` 启动 + 超时自动判定 + result.json | 实测 PASS |
| 功能测试 | `tests/cpuinfo`(断言 v/h 扩展)、`tests/vector`(RVV 向量加法,VLEN=128bit) | 实测 PASS |
| kselftest | `tests/kselftest` 构建并运行内核官方 selftests/riscv(hwprobe/vector/sigreturn/mm/abi) | 9/10,详见 findings |
| 配置漂移 | `scripts/check-config-drift.sh`:必需合同 + 全量 diff 两层 | 实测 PASS(模拟攻击被捕获) |
| 闭环 | `scripts/run-closed-loop.sh`:漂移检查→启动→SSH→推送测试→guest 内跑→拉回报告 | 实测跑通 |

## 一键命令

`scripts/run-closed-loop.sh` 一条命令跑完整闭环,五步:`[0]` 配置漂移检查(FAIL 级直接中止)→ `[1]` 用新内核 `-snapshot` 启动测试镜像(独立 SSH 端口)→ `[2]` 轮询等待 guest SSH 上线(超时判 boot FAIL)→ `[3]` scp 推送测试套件(预编译静态二进制)→ `[4]` guest 内执行 cpuinfo/vector/kselftest → `[5]` 拉回结果输出 verdict。

可调参数用环境变量:`KERNEL`(内核 Image 路径)、`IMG`(测试镜像)、`PORT`(SSH 转发端口)、`GUEST_USER`、`BOOT_TIMEOUT`。

错误处理:镜像/内核缺失报错退出;SSH 超时判 boot FAIL 并贴串口尾部日志;结果在 `build/closed-loop/`(qemu.log / guest-run.log / guest-results/)。

## 验收流程(每步要有对照数据)

1. **boot 判定**:假判定(只 grep "Linux version")vs 真判定(login 提示)——本方案用真判定,已实测 PASS;
2. **漂移检测**:基线同步后 0 漂移;模拟关闭 `CONFIG_RISCV_ISA_V` + 改 `CONFIG_HZ`,两层同时命中、退出码 2(已实测);
3. **kselftest 双平台对照**:同一套件在 Ubuntu 6.14(pointer_masking 走 SKIP)与 7.2.0-rc7 guest(暴露失败)各跑一遍,差异即发现(已实测);
4. **待实测**:Hypervisor 真机、容器化整合、GitHub Actions、回归通过率历史趋势。

## 共同底线

1. 测试靶子启动必须 `-snapshot`;主力 ubuntu.img 永不参与测试;
2. selftests 必须显式 `ARCH=riscv`(`uname -m` 返回 riscv64 匹配不上);vector 测试须在其构建目录内运行;mm 测试须经 `run_mmap.sh`(ulimit 前提);
3. guest 内只跑预编译的静态二进制,不依赖 guest 工具链;
4. 速度/结果数字实测才报,未测的标「待实测」;
5. 必需选项合同是硬约束,改配置必须同步基线并重跑漂移检查。

## 关键参考资料

- SOW:github.com/riscv-admin/dev-partners/issues/49
- KernelCI 新架构:docs.kernelci.org(Monitor tests / kci-dev / Maestro)
- pointer-masking 根因:内核 commit `3033b2b1e3`("riscv: Reset pmm when PR_TAGGED_ADDR_ENABLE is not set");详见 docs/findings-pointer-masking.md
- selftests:tools/testing/selftests/riscv(hwprobe/vector/sigreturn/mm/abi)
- GCC RVV 内建函数带 `__riscv_` 前缀(与 Clang 裸名不同);`/proc/cpuinfo` isa 行为 `isa<TAB>: value` 格式
- 完整报告:docs/project-report.md
