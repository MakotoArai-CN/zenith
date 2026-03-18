<div align="center">

<img src="https://raw.githubusercontent.com/MakotoArai-CN/zenith/main/icon.svg" width="200" height="200">
<h1>Zenith</h1>

[English](README.md) | [日本語ドキュメント](README_JA.md)
</div>

轻量级跨平台系统基准测试工具，使用 Zig 编写。单一二进制文件，零依赖。

> 跑分结果仅供参考，由于不同操作系统的调度差异、缓存和其他因素，可能与实际性能有所不同！

## 功能

- **系统信息** — 主机名、操作系统、架构、内核、CPU 型号/核心/缓存、内存/交换分区、磁盘空间、运行时间、时区、虚拟化检测、系统负载
- **网络信息** — 公网 IP、本地 IP、NAT 检测、ISP/ASN、地理位置
- **CPU 测试** — 质数计算、矩阵乘法（单核 & 多核）
- **内存测试** — 顺序读/写/拷贝、随机读取、访问延迟
- **磁盘测试** — 顺序读/写、随机 IOPS
- **跨平台** — Linux、Windows、macOS、FreeBSD
- **多架构** — x86_64、aarch64、arm、riscv64、s390x、ppc64le、i386、loongarch64
- **三语输出** — English、中文、日本語
- **自动语言检测** — 自动检测系统语言，可通过 `-l` 覆盖
- **终端自适应** — 自动检测颜色、Unicode、终端宽度；传统终端（如 Windows cmd.exe）自动降级为 ASCII
- **持续时间测试** — 预热 + 定时采样 + 中位数聚合，结果更稳定

## 语言支持

| 代码 | 语言 | 参数 |
|------|------|------|
| `en` | English | `-l en` |
| `zh` | 中文 | `-l zh` |
| `ja` | 日本語 | `-l ja` |

默认：自动检测系统语言。检测不到时默认 `en`。通过 `-l` / `--lang` 覆盖。

## 快速开始

```bash
# 构建并运行（本机）
zig build run -Doptimize=ReleaseSmall

# 构建全部 14 个交叉编译目标
zig build -Doptimize=ReleaseSmall

# 指定中文运行
zig build run -Doptimize=ReleaseSmall -- -l zh
```

## 用法

```text
zenith [选项]

选项:
  -h, --help             显示帮助信息
  -v, --version          显示版本号
  -l, --lang <LANG>      语言: en, zh, ja (默认: 自动检测)
      --no-cpu           跳过 CPU 测试
      --no-memory        跳过内存测试
      --no-disk          跳过磁盘测试
      --no-sysinfo       跳过系统信息
      --no-network       跳过网络信息
      --cpu-method <M>   CPU 测试方式: prime, matrix, all (默认: all)
      --threads <N>      线程数, 0=自动 (默认: 0)
      --cpu-threads <N>  同 --threads
      --disk-method <M>  磁盘测试: sequential, random, all (默认: all)
      --disk-path <P>    磁盘测试路径 (默认: /tmp)
      --disk-size <N>    磁盘测试大小 MB (默认: 128, 最大: 4096)
      --iterations <N>   每项测试迭代次数 (默认: 3, 最大: 100)
  -t, --time <N>         每项测试持续时间秒 (默认: 10, 范围: 1-3600)
      --duration <N>     同 --time
  -o, --output <FILE>    保存结果到文件
      --json             JSON 格式输出
```

### 示例

```bash
# 仅 CPU 测试，每项 5 秒
zenith --no-memory --no-disk --no-network -t 5

# 仅磁盘测试，256MB 测试文件
zenith --no-cpu --no-memory --no-network --disk-size 256

# 仅系统信息（不跑分）
zenith --no-cpu --no-memory --no-disk

# 4 线程，日语输出
zenith --threads 4 -l ja
```

## 评分算法

### 测试方法

所有基准测试使用**持续时间采样 + 中位数聚合**：

1. **预热** — 丢弃第一轮迭代，消除冷启动效应
2. **定时循环** — 持续运行至 `duration_secs` 时间耗尽（默认 10 秒），每轮采集一个样本
3. **中位数** — 对所有样本排序取中位数，消除系统噪音和异常值

### CPU 评分

| 子测试 | 公式 |
|--------|------|
| 质数单核 | `每秒操作数 × 1` |
| 质数多核 | `每秒操作数 × 1` |
| 矩阵单核 | `GFLOPS × 100` |
| 矩阵多核 | `GFLOPS × 100` |
| **CPU 总分** | 四项子分之和 |

- **质数测试**：统计 100,000 以内的质数个数，使用试除法
- **矩阵测试**：128×128 双精度矩阵乘法，GFLOPS = `2×N³ / 时间 / 10⁹`
- 多线程测试并行启动所有工作线程（默认自动检测 CPU 核心数）

### 内存评分

| 子测试 | 测量指标 |
|--------|----------|
| 顺序写入 | bytes/sec（64 MB 缓冲区，volatile 写入）|
| 顺序读取 | bytes/sec（64 MB 缓冲区，volatile 读取）|
| 顺序拷贝 | bytes/sec（64 MB `@memcpy`）|
| 随机读取 | bytes/sec（100 万条目指针追踪）|
| 访问延迟 | 纳秒（链表指针追踪）|

```text
平均带宽 = (顺序写 + 顺序读 + 顺序拷贝) / 3
带宽分数 = 平均带宽_MB每秒 × 0.1
延迟分数 = 1000 / 延迟_纳秒 × 50
总分 = 带宽分数 + 延迟分数
```

带宽越高、延迟越低，分数越高。

### 磁盘评分

| 子测试 | 测量指标 |
|--------|----------|
| 顺序写入 | bytes/sec（1 MB 块，Linux 下 fdatasync）|
| 顺序读取 | bytes/sec（1 MB 块）|
| 随机写入 | IOPS（4 KB 块，4096 个随机偏移）|
| 随机读取 | IOPS（4 KB 块，4096 个随机偏移）|

```text
顺序分数 = (顺序写 + 顺序读) MB/s × 0.5
IOPS 分数 = (随机写 IOPS + 随机读 IOPS) × 0.005
总分 = 顺序分数 + IOPS 分数
```

### 综合评分

```text
综合分 = CPU 总分 + 内存总分 + 磁盘总分
```

消费级硬件典型分数范围：**5,000 - 30,000**。

## 交叉编译

默认 `zig build` 编译全部 14 个目标：

```bash
zig build -Doptimize=ReleaseSmall
# 输出: zig-out/bin/zenith-{target}
```

### 支持的目标

| 操作系统 | 架构 |
|----------|------|
| Linux | x86_64, aarch64, arm, riscv64, s390x, ppc64le, i386, loongarch64 |
| Windows | x86_64, i386, aarch64 |
| macOS | x86_64, aarch64 (Apple Silicon) |
| FreeBSD | x86_64 |

共 **14 个目标**，一次 `zig build` 生成 14 个二进制文件。

## 安全说明

- **网络信息使用 HTTP**（非 HTTPS）查询 `ip-api.com`。免费版仅支持 HTTP。敏感环境中请使用 `--no-network` 跳过。
- **输入校验**：CLI 参数限制在安全范围 — `--disk-size` 最大 4096 MB，`--threads` 最大 1024，`--time` 范围 1-3600 秒。
- **临时文件**：磁盘测试在 `--disk-path` 目录创建 `zenith_bench.tmp`，每轮测试后自动清理。

## 下载

所有支持平台的预编译二进制文件可在 [Releases 页面](https://github.com/MakotoArai-CN/zenith/releases) 获取。

## 构建要求

- [Zig](https://ziglang.org/download/) >= 0.15.0

## 许可证

详见 [LICENSE](LICENSE)。
