# KernelCI RISC-V 本地化测试流水线实践方案

v1 ｜ 2026-08-21

## 核心结论

RISC-V 架构规范在成熟,但 Linux 主线缺一套持续、可复现的 RISC-V 内核测试。本方案用「x86 交叉编译 + QEMU 模拟」把测试做成一条命令完成的闭环:编译内核 → 检查配置漂移 → 启动测试镜像 → 在 guest 里跑扩展测试 → 拉回报告。测试靶子使用闲置镜像的副本,启动永远加 `-snapshot`(写入即弃,镜像本体不会被改动),因此被测内核即使有 bug 也不会损坏任何环境。已实测:boot 通过(新编译的内核成功启动到登录提示符)、cpuinfo/Vector 通过(CPU 信息检测通过;向量指令 RVV 实测算对,向量加法结果全部正确)、内核官方 selftests 10 项 9 过 1 挂——那 1 挂(pointer_masking)是上游主线至今存在的测试↔内核语义矛盾(测试期望掩码位数被向上取整并记住,内核却在未带启用标志时将其重置为 0 且返回成功),只在 QEMU 模拟的指针掩码(ZPM)平台上暴露,已写成 findings 底稿准备发上游。

## 关键事实

| 事实 | 说明 |
|---|---|
| 测试内核 | torvalds/linux v7.2.0-rc7,riscv defconfig |
| 编译方式 | x86 宿主交叉编译,riscv64-linux-gnu-gcc 15.2 |
| 虚拟化目标 | qemu-system-riscv64 10.2(TCG 软件模拟,`-cpu max`,含 Vector/Hypervisor/指针掩码 ZPM 扩展,VLEN=128bit) |
| 测试镜像 | openkylin-test.img(闲置镜像的副本,已预置 SSH 公钥;每次启动 `-snapshot` 零污染) |
| boot 判定 | 串口出现 `login:` 提示或 systemd `Login Prompts` 目标(不用开机最早的 "Linux version",以免漏掉 init 之前的 panic) |
| selftests 实测 | 内核官方 selftests/riscv 10 项:9 过 1 挂 0 跳过;唯一失败 pointer_masking 已登记 XFAIL(见 findings) |
| 配置合同 | 17 项必需选项(V/virtio/ext4/串口/KVM 等),任何缺失/变值即 FAIL |
| CI | GitHub Actions 双流水线:云端 light(漂移检查+交叉编译)+ 自托管 runner 执行完整闭环 |
| 回归历史 | `results/trend.md` 通过率趋势表,每次 CI 自动归档并由 ci-bot 提交回仓库 |
| 待实测 | Hypervisor(KVM)真机测试(需带 H 扩展的真实硬件) |

## 分层能力

| 层 | 内容 | 实测状态 |
|---|---|---|
| boot 测试 | `scripts/boot-test.sh`:`-snapshot` 启动新内核 → 超时自动判定是否到达登录提示 → result.json | PASS |
| 功能测试 | `tests/cpuinfo`(解析 ISA 并断言 v/h 扩展)、`tests/vector`(RVV 向量加法自测) | PASS |
| kselftest | `tests/kselftest`:构建并运行内核官方 selftests/riscv(hwprobe/vector/sigreturn/mm/abi 五组) | 9/10(1 XFAIL) |
| 配置漂移检测 | `scripts/check-config-drift.sh`:17 项必需合同 + 全量 config diff(丢失/禁用=FAIL,变值=WARN,新增=INFO) | PASS(模拟注入被捕获) |
| 闭环流水线 | `scripts/run-closed-loop.sh`:漂移检查→启动→SSH 接入→推送测试→guest 内执行→拉回报告 | 跑通 |
| 回归历史 | `scripts/record-result.sh` + `scripts/report-history.py`:按运行归档 + 通过率趋势表 | 已上线 |

## 目录结构

| 目录 | 作用 |
|---|---|
| `scripts/` | 全部自动化脚本:`run-closed-loop.sh` 总指挥(闭环)、`build-kernel.sh` 交叉编译、`boot-test.sh` boot 测试、`check-config-drift.sh` 漂移检测、`seed-test-image.sh` 镜像播种、`record-result.sh` + `report-history.py` 回归历史、`docker-run-pipeline.sh` 容器入口 |
| `tests/` | 测试本体:`run-tests.sh` 统一入口;`cpuinfo/` ISA 检测(v/h 断言);`vector/` RVV 向量加法自测;`kselftest/` 内核官方 selftests 构建+运行器 |
| `configs/` | 配置基线:`riscv-qemu/defconfig` 基准内核配置;`riscv-qemu/required-opts.txt` 17 项必需选项合同;`dsh-test.pub` 测试 guest SSH 公钥 |
| `results/` | 数据:`history/` 每次测试的归档快照(时间戳+内核版本命名);`trend.md` 通过率趋势表(CI 自动更新) |
| `docs/` | 文档:`project-report.md` 完整报告;`findings-pointer-masking.md` 上游 bug 技术底稿;`findings-email-draft.md` 上游邮件定稿;`tracking-issue-draft.md` KernelCI 社区 issue 定稿 |
| `.github/workflows/` | CI 定义:双流水线(云端 light + 自托管 runner heavy) |
| `Dockerfile` | 容器环境箱:交叉工具链 + QEMU,一次构建处处可用 |

记忆法:`scripts/` 管怎么跑,`tests/` 管跑什么,`configs/` 管按什么标准,`results/` + `docs/` 管留下什么证据,`.github/` + `Dockerfile` 管在哪都能自动跑。

## 一键命令

```bash
scripts/run-closed-loop.sh
```

在装有交叉工具链与 QEMU 的 x86 Linux 宿主上执行(或使用本仓库 `Dockerfile` 构建的环境箱),一条命令完成:

1. `[0]` 配置漂移检查(FAIL 级直接中止);
2. `[0c]` 预编译测试产物缺失时现场交叉编译(全新 checkout 也能跑);
3. `[1]` 用新内核 + `-snapshot` 启动测试镜像(独立 SSH 端口,互不干扰);
4. `[2]` 轮询等待 guest SSH 上线,超时判 boot FAIL 并贴串口日志;
5. `[3]` scp 推送测试套件;
6. `[4]` guest 内执行 cpuinfo / vector / kselftest;
7. `[5]` 拉回结果、输出 verdict,并归档进回归历史。

可调参数(环境变量):`KERNEL`、`IMG`、`PORT`、`GUEST_USER`、`BOOT_TIMEOUT`。
一次性准备:`scripts/seed-test-image.sh`(把 SSH 公钥种进测试镜像副本,需 sudo 一次)。
结果位置:`build/closed-loop/`(qemu.log 串口日志 / guest-run.log / guest-results/)。

## 快速开始(从零复现)

前置条件:x86_64 Linux(物理机/虚拟机/WSL 均可)+ Docker 或手动安装的工具链;一个闲置的 RISC-V 发行版 raw 镜像(约 6GB,根分区为 ext4 且位于第 2 分区,如 openKylin/Ubuntu RISC-V);磁盘空间约 30GB。

```bash
# 1. 获取代码与内核源码(与基线同版本)
git clone https://github.com/xjysiiau/kernelci-riscv.git
git clone --depth=1 --branch v7.2-rc7 https://github.com/torvalds/linux.git ~/linux

# 2. 准备环境(二选一)
cd kernelci-riscv && ./scripts/docker-run-pipeline.sh bash        # Docker 方式:自动构建环境箱
sudo apt install gcc-riscv64-linux-gnu libc6-dev-riscv64-cross make \
  qemu-system-misc openssh-client flex bison bc libssl-dev libelf-dev   # 原生方式

# 3. 播种测试镜像(一次性,需 sudo;SRC 指向闲置镜像)
SRC=/path/to/your-riscv.img ./scripts/seed-test-image.sh

# 4. 交叉编译内核(一次性,8 核约 2.5-3 小时)
cp configs/riscv-qemu/defconfig ~/linux/.config
make -C ~/linux ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- -j$(nproc) Image

# 5. 跑完整闭环(约 3-12 分钟)
KERNEL=~/linux/arch/riscv/boot/Image ./scripts/run-closed-loop.sh
```

只跑某一层(无需镜像、无需编译内核):

```bash
./scripts/check-config-drift.sh     # 配置漂移检查(需 ~/linux/.config 已生成)
make -C ~/linux/tools/testing/selftests/riscv ARCH=riscv \
  CROSS_COMPILE=riscv64-linux-gnu- OUTPUT=$PWD/build/kselftest -j$(nproc)  # 仅交叉编译 selftests
```

用 CI 跑:fork 本仓库后,云端 light 任务在每次 push 自动运行;完整闭环需在自有机器上注册自托管 runner(仓库 Settings → Actions → Runners → New self-hosted runner),并保证机器上内核源码与播种镜像路径匹配脚本默认值(`~/kernelci-work/linux`、`~/kernelci-test/openkylin-test.img`,或经环境变量覆盖)。

## 验收流程(每步需对照数据)

1. **boot 判定对照**:假判定(grep "Linux version",开机即打印)vs 真判定(登录提示符)——本方案采用真判定,已实测;
2. **漂移检测对照**:基线同步后 0 漂移;注入攻击(关闭 `CONFIG_RISCV_ISA_V` + 改 `CONFIG_HZ`)被两层同时命中,退出码 2;
3. **kselftest 双平台对照**:同一套件在 Ubuntu 6.14(pointer_masking 走 SKIP)与 7.2.0-rc7 guest(暴露 FAIL)各跑一遍,差异即发现;
4. **CI 环境对照**:云端 runner 与自托管 runner 各跑一遍,暴露并修复了工具链漂移、版本耦合、产物缺失、交叉 libc 四类"只在别的机器上出现"的问题。

## 共同底线

1. 测试镜像启动必须 `-snapshot`;主力/原始镜像永不参与测试;
2. selftests 必须显式 `ARCH=riscv`(Makefile 按 "riscv" 精确匹配,`uname -m` 返回的 riscv64 会漏);vector 测试须在其构建目录内运行;mm 测试须经 `run_mmap.sh`(`ulimit -s unlimited` 前提);
3. guest 内只运行预编译的静态二进制,不依赖 guest 自带工具链;
4. 数字实测才报,未实测一律标注「待实测」;
5. 必需选项合同是硬约束,修改配置必须同步基线并重跑漂移检查。

## 关键参考资料

- SOW:github.com/riscv-admin/dev-partners/issues/49(KernelCI: Statement of Work)
- KernelCI 新架构文档:docs.kernelci.org(Monitor tests / kci-dev / Maestro)
- findings:docs/findings-pointer-masking.md(pointer_masking 测试失败:症状/根因/复现);上游邮件底稿:docs/findings-email-draft.md
- 上游根因 commit:`3033b2b1e3`("riscv: Reset pmm when PR_TAGGED_ADDR_ENABLE is not set")
- selftests 源码:tools/testing/selftests/riscv
- 已知坑:GCC RVV 内建函数带 `__riscv_` 前缀(与 Clang 裸名不同);`/proc/cpuinfo` 的 isa 行为 `isa<TAB>: value` 格式
- 回归趋势:results/trend.md;tracking issue 文本:docs/tracking-issue-draft.md;完整报告:docs/project-report.md

## 社区链接

- KernelCI tracking issue:https://github.com/kernelci/kernelci-project/issues/579(2026-08-21 发布,open)
- findings 邮件:已发 linux-riscv@lists.infradead.org(2026-08-22)

## 许可

GPL-2.0(与内核生态一致;仓库内的内核 defconfig 派生自内核源码树,亦为 GPL-2.0)。详见 LICENSE。
