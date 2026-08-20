# KernelCI RISC-V 本地化测试流水线实践方案

v1 ｜ 2026-08-20

> 对应 SOW: [riscv-admin/dev-partners#49 — KernelCI: Statement of Work](https://github.com/riscv-admin/dev-partners/issues/49)
> 仓库: https://github.com/xjysiiau/kernelci-riscv

## 核心结论

RISC-V 架构规范和软件使能 profile(如 RVA23)在成熟,但 Linux 主线缺一套一致、持续、可复现的 RISC-V 内核测试;架构扩展(Vector/Hypervisor 等)与不同微架构的行为差异是主要测试缺口。本方案把 KernelCI 的模型搬到自己机器上:在 x86 宿主交叉编译 riscv64 内核,用 QEMU 模拟做测试目标,把「构建 → 配置漂移检查 → 启动 → 测试 → 报告」做成一条命令完成的闭环。测试靶子用闲置 openkylin 镜像的副本,每次启动加 `-snapshot`(写入即弃),测试内核的 bug 永远不会污染镜像,主力开发环境全程不参与。已实测:boot 通过、cpuinfo/Vector 通过、内核官方 selftests 10 项 9 过 1 挂 0 跳过。唯一失败(pointer_masking)经逐行比对确认是上游主线至今存在的测试↔内核语义矛盾,只在 QEMU 模拟的指针掩码(ZPM)平台上暴露——真实硬件大多无 ZPM,上游 CI 看不到,这是本方案最有价值的产出。Hypervisor 真机测试、容器化整合等未上板项一律标「待实测」。

## 关键事实

| 事实 | 数值(以仓库实测为准) |
|---|---|
| 测试内核 | torvalds/linux 7.2.0-rc7,riscv defconfig |
| 编译方式 | WSL x86 交叉编译,riscv64-linux-gnu-gcc 15.2(22 线程) |
| 虚拟化 | qemu-system-riscv64 10.2,TCG,`-cpu max`(含 V/H/ZPM 扩展,VLEN=128bit) |
| 开发机 | Ubuntu 25.04 riscv64 QEMU VM,8 核/12G,ISA `rv64imafdcvh` |
| 测试靶子 | openkylin-test.img(6GB 副本,已播种 SSH 公钥) |
| boot 判定依据 | 串口 `login:` 提示 / systemd `Login Prompts` 目标 |
| selftests 结果 | 10 项 9 过 1 挂 0 跳过(7.2.0-rc7 guest 内实测) |
| 必需配置合同 | 17 项(V/SUPM/ZICBOM/virtio/ext4/串口/KVM=m 等) |
| 待实测 | Hypervisor(KVM)真机、容器化整合、GitHub Actions、回归通过率历史 |

## 一、环境与架构

```
Windows 11
└── WSL2 Ubuntu (x86_64)                构建 + 测试宿主
      qemu-system-riscv64 10.2 ｜ riscv64-linux-gnu-gcc 15.2 ｜ docker 29
      ├── Ubuntu 25.04 riscv64 VM       功能测试原生环境(有 V/H 扩展)
      └── openkylin-test.img            测试靶子:每次 -snapshot 启动
             └─ 被「新编译的内核」直接启动(绕过 U-Boot)
```

设计决策(见「共同底线」):
- 采用 x86 交叉编译 + QEMU TCG 模拟的标准 KernelCI 模型;否决「RISC-V 内再嵌套 QEMU」(TCG 套 TCG 性能不可用,且非上游模型);
- 测试靶子与主力环境彻底分离:副本 + `-snapshot`,零污染;
- 结果判定以「真实到达登录提示符」为准,不用开机最早的 "Linux version"(会漏掉 init 之前的 panic)。

## 二、分层能力

### 2.1 boot 测试(scripts/boot-test.sh)

| 做法 | 说明 |
|---|---|
| 启动 | `-kernel <新内核>` + `-drive <测试镜像>` + `-snapshot` + `-no-reboot` |
| 判定 | 串口出现 `login:` 或 `Login Prompts` → PASS;panic/挂根/无 init → FAIL |
| 兜底 | `timeout` 自动结束 QEMU,无残留进程;产出 result.json(内核版本/判定依据/时间戳) |

实测:7.2.0-rc7 → `openKylin 2.0 SP2 openkylin ttyS0` + `openkylin login:`,PASS;openkylin.img mtime 纹丝未动(snapshot 生效)。

### 2.2 功能测试(tests/cpuinfo, tests/vector)

| 测试 | 做法 | 实测 |
|---|---|---|
| cpuinfo | 解析 `/proc/cpuinfo` 的 isa 行,断言 V/H 扩展存在 | PASS(双平台) |
| vector | RVV 向量加法:`__riscv_vsetvl/vle/vadd/vse` 内建函数,读 `vlenb` CSR | PASS,VLEN=128bit |

注意:`/proc/cpuinfo` 的 isa 行是 `isa<TAB>: value` 格式,按列取值会取到冒号;GCC 的 RVV 内建函数带 `__riscv_` 前缀(与 Clang 裸名不同)。

### 2.3 kselftest(tests/kselftest)

构建并运行内核官方 `tools/testing/selftests/riscv`(hwprobe/vector/sigreturn/mm/abi 五组)。三条官方运行前提已固化进脚本:
1. 显式 `ARCH=riscv`(`uname -m` 返回 riscv64 匹配不上,会静默不编);
2. vector 测试须在其构建目录内运行(它们 exec 同目录辅助程序);
3. mm 测试须经 `run_mmap.sh`(`ulimit -s unlimited` 才切 bottom-up 布局)。

guest 内跑预编译的**静态**二进制(避免 guest glibc 版本差异),支持 `KSELFTEST_BUILD=skip` 免编译模式。

### 2.4 配置漂移检测(scripts/check-config-drift.sh)

| 层级 | 机制 | 触发 |
|---|---|---|
| 必需选项合同 | `required-opts.txt` 17 项关键配置 | 缺失/变值 → FAIL |
| 全量 diff | 基准 defconfig vs 实际 .config 归一化比对 | 丢失/禁用 → FAIL;变值 → WARN;新增 → INFO |

退出码 0/1/2 分级,产出 config-drift.json。实测:首次运行即发现基准 defconfig 是 gcc 14.2 时代生成、与 gcc 15.2 交叉编译存在 4 项工具链漂移 + 9 项新选项——已同步基线归零;模拟关闭 `CONFIG_RISCV_ISA_V` 的漂移攻击被两层同时捕获(退出码 2)。

### 2.5 一键闭环(scripts/run-closed-loop.sh)

一条命令跑完整闭环,五步:
```
[0]  配置漂移检查(FAIL 级直接中止)
[1]  用新内核 + -snapshot 启动测试镜像(独立 SSH 端口)
[2]  轮询等待 guest SSH 上线(超时判 boot FAIL)
[3]  scp 推送测试套件(预编译静态二进制)
[4]  guest 内执行 cpuinfo / vector / kselftest
[5]  拉回结果 → 输出 verdict
```

可调参数用环境变量:`KERNEL`、`IMG`、`PORT`、`GUEST_USER`、`BOOT_TIMEOUT`。
错误处理:镜像/内核缺失报错退出;SSH 超时判 boot FAIL 并贴串口尾部日志;结果在 `build/closed-loop/`(qemu.log / guest-run.log / guest-results/)。
辅助脚本:`seed-test-image.sh`(一次性,把 SSH 公钥种进测试镜像,需 sudo)。

## 三、测试矩阵(实测结果)

| 测试 | 在 7.2.0-rc7 guest 内 | 对照:Ubuntu 6.14 开发机 |
|---|---|---|
| boot(到登录提示) | ✅ PASS | — |
| cpuinfo(v/h 断言) | ✅ PASS | ✅ PASS |
| vector(RVV 加法) | ✅ PASS | ✅ PASS |
| kselftest/hwprobe | ✅ PASS | ✅ PASS |
| kselftest/cbo, which-cpus | ✅ PASS | ⏭ 未构建(头文件宏) |
| kselftest/vstate_prctl(13 项) | ✅ PASS | ✅ PASS |
| kselftest/v_initval, vstate_ptrace, validate_v_ptrace | ✅ PASS | ✅(validate 未构建) |
| kselftest/sigreturn | ✅ PASS | ✅ PASS |
| kselftest/mm(双布局) | ✅ PASS | ✅ PASS |
| kselftest/abi/pointer_masking | ❌ FAIL(16 项 constraint) | ✅(相关项 SKIP) |

## 四、发现:abi/pointer_masking 在上游主线同样失败

**症状**:`test_pmlen()` 对 PMLEN=1..16 的每个 "constraint" 断言全挂("validity" 全过)——内核接受任意 PMLEN 请求,但 `PR_GET_TAGGED_ADDR_CTRL` 报告的生效值恒为 0。

**根因**(逐行比对,7.2-rc7 与 master 一致):
- 测试:只设 PMLEN 字段(不带 `PR_TAGGED_ADDR_ENABLE`),期望内核向上取整并记住(`pmlen >= request`);
- 内核:`set_tagged_addr_ctrl()` 在未设 ENABLE 时执行 `pmlen = PMLEN_0` 并返回成功(commit `3033b2b1e3`,2026-03-22,"riscv: Reset pmm when PR_TAGGED_ADDR_ENABLE is not set")。

**为什么上游 CI 看不到**:无 ZPM 扩展的平台上内核直接拒绝 prctl,测试走 SKIP 分支;QEMU `-cpu max` 恰好模拟了 Smnpm/Ssnpm,矛盾因此暴露。

**建议**:低实际影响,但测试与内核对「仅设 PMLEN」语义存在分歧,二者之一应修改;向 `kernelci@lists.linux.dev` / `linux-riscv@lists.infradead.org` 报告。完整底稿见 docs/findings-pointer-masking.md。

## 五、验收流程(每步要有对照数据)

1. **boot 判定**:假判定("Linux version")vs 真判定(login 提示)对照,本方案用真判定,已实测;
2. **漂移检测**:基线归零后注入漂移(关 V 扩 + 改 HZ),两层命中、退出码 2,已实测;
3. **kselftest 双平台对照**:Ubuntu 6.14(SKIP)vs 7.2.0-rc7 guest(FAIL)各跑一遍,差异即发现,已实测;
4. **待实测**:Hypervisor(KVM)真机(RISE/生态实验室硬件);容器化整合(podman 方案已验证未整合);GitHub Actions;回归通过率历史趋势(results.json 归档)。

## 六、共同底线

1. 测试靶子启动必须 `-snapshot`;主力 ubuntu.img 永不参与测试;
2. selftests 必须显式 `ARCH=riscv`;vector 测试须在其构建目录内运行;mm 测试须经 `run_mmap.sh`;
3. guest 内只跑预编译静态二进制,不依赖 guest 工具链;
4. 速度/结果数字实测才报,未测的标「待实测」;
5. 必需选项合同是硬约束,改配置必须同步基线并重跑漂移检查;
6. 交叉编译产物用静态链接;Windows 传脚本经 base64 过 stdin,规避 PowerShell CRLF。

## 七、待办(含待实测)

| 项 | 状态 |
|---|---|
| kernelci-project tracking issue 发布 | 草稿已备 |
| findings 发上游(KernelCI / linux-riscv) | 底稿已备 |
| Hypervisor(KVM)真机测试 | 待硬件 |
| 容器化整合 + GitHub Actions | 待实测 |
| 回归通过率历史统计 | 未开始 |
| Phase 3:Maestro/kci-dev 集成 PR | 未开始 |
| 博客 / demo / LF 徽章 | 未开始 |

## 八、关键参考资料

- SOW:github.com/riscv-admin/dev-partners/issues/49;DevPartners 看板:github.com/orgs/riscv-admin/projects/2
- KernelCI 新架构:docs.kernelci.org(Monitor tests / kci-dev / Maestro API);kci-dev 仓库:github.com/kernelci/kci-dev
- pointer-masking 根因:内核 commit `3033b2b1e3`("riscv: Reset pmm when PR_TAGGED_ADDR_ENABLE is not set",2026-03-22)
- selftests:tools/testing/selftests/riscv(hwprobe/vector/sigreturn/mm/abi)
- RVV:GCC 内建函数 `__riscv_` 前缀;PLCT 128 位向量扩展
- 工具链:riscv64-linux-gnu-gcc 15.2 / qemu-system-riscv64 10.2 / OpenSBI fw_dynamic

## 附录:复现指南

### A. 一次性准备(需要 sudo)
```bash
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

### C. 分层单独运行
```bash
scripts/check-config-drift.sh      # 配置漂移
scripts/boot-test.sh               # boot 测试
cd tests && ./run-tests.sh         # 功能测试(riscv64 上原生)
```
