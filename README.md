<div align="center">

<img src="https://raw.githubusercontent.com/MakotoArai-CN/zenith/main/icon.svg" width="200" height="200">
<h1>Zenith</h1>

[中文文档](README_ZH.md) | [日本語ドキュメント](README_JA.md)
</div>

A lightweight, cross-platform system benchmark tool written in Zig. Single binary, zero dependencies.

> Benchmark results are for reference only. Due to differences in scheduling across operating systems, caching, and other factors, they may differ from actual performance!

## Features

- **System Information** — hostname, OS, architecture, kernel, CPU model/cores/cache, memory/swap, disk space, uptime, timezone, virtualization, system load
- **Network Information** — public IP, local IP, NAT detection, ISP/ASN, geolocation
- **CPU Benchmark** — prime number computation, matrix multiplication (single & multi-threaded)
- **Memory Benchmark** — sequential read/write/copy, random read, access latency
- **Disk Benchmark** — sequential read/write, random IOPS
- **Cross-platform** — Linux, Windows, macOS, FreeBSD
- **Multi-architecture** — x86_64, aarch64, arm, riscv64, s390x, ppc64le, i386, loongarch64
- **Trilingual output** — English, 中文, 日本語
- **Auto language detection** — detects system language automatically, override with `-l`

## Download

Pre-compiled binaries for all supported platforms are available on the [Releases page](https://github.com/MakotoArai-CN/zenith/releases).

## Language Support

| Code | Language | Flag |
|------|----------|------|
| `en` | English | `-l en` |
| `zh` | 中文 (Chinese) | `-l zh` |
| `ja` | 日本語 (Japanese) | `-l ja` |

Default: auto-detect from system locale. Fallback: `en`. Override via `-l` / `--lang`.

## Quick Start

```bash
# Build and run (native)
zig build run -Doptimize=ReleaseSmall

# Build all 14 cross-compilation targets
zig build -Doptimize=ReleaseSmall

# Run with specific language
zig build run -Doptimize=ReleaseSmall -- -l zh
```

## Usage

```text
zenith [options]

Options:
  -h, --help             Show help message
  -v, --version          Show version
  -l, --lang <LANG>      Language: en, zh, ja (default: auto-detect)
      --no-cpu           Skip CPU benchmark
      --no-memory        Skip memory benchmark
      --no-disk          Skip disk benchmark
      --no-sysinfo       Skip system information
      --no-network       Skip network information
      --cpu-method <M>   CPU method: prime, matrix, all (default: all)
      --threads <N>      Thread count, 0=auto (default: 0)
      --cpu-threads <N>  Alias for --threads
      --disk-method <M>  Disk method: sequential, random, all (default: all)
      --disk-path <P>    Disk test path (default: /tmp)
      --disk-size <N>    Disk test size in MB (default: 128, max: 4096)
      --iterations <N>   Iterations per test (default: 3, max: 100)
  -t, --time <N>         Duration per test in seconds (default: 10, range: 1-3600)
      --duration <N>     Alias for --time
  -o, --output <FILE>    Save results to file
      --json             Output in JSON format
```

### Examples

```bash
# CPU only, 5 seconds per test
zenith --no-memory --no-disk --no-network -t 5

# Disk benchmark only, 256MB test file
zenith --no-cpu --no-memory --no-network --disk-size 256

# System info only (no benchmarks)
zenith --no-cpu --no-memory --no-disk

# Full benchmark with 4 threads, Japanese output
zenith --threads 4 -l ja
```

## Scoring Algorithm

### Benchmark Methodology

All benchmarks use **duration-based sampling with median aggregation**:

1. **Warmup** — one iteration is discarded to eliminate cold-start effects
2. **Timed loop** — benchmarks repeat until `duration_secs` is reached (default: 10s), collecting one sample per iteration
3. **Median** — samples are sorted and the median value is used as the final result, eliminating outliers

### CPU Score

| Sub-test | Formula |
|----------|---------|
| Prime Single | `ops_per_sec × 1` |
| Prime Multi | `ops_per_sec × 1` |
| Matrix Single | `GFLOPS × 100` |
| Matrix Multi | `GFLOPS × 100` |
| **CPU Total** | Sum of all 4 sub-scores |

- **Prime**: counts primes up to 100,000 using trial division. `ops_per_sec` = full iterations completed per second.
- **Matrix**: 128×128 double-precision matrix multiplication. GFLOPS = `2×N³ / time / 10⁹`.
- Multi-threaded tests spawn `thread_count` workers in parallel (default: auto-detect CPU count).

### Memory Score

| Sub-test | Measurement |
|----------|-------------|
| Sequential Write | bytes/sec (64 MB buffer, volatile write) |
| Sequential Read | bytes/sec (64 MB buffer, volatile read) |
| Sequential Copy | bytes/sec (64 MB `@memcpy`) |
| Random Read | bytes/sec (1M-entry pointer chase) |
| Access Latency | nanoseconds (linked-list pointer chase) |

```text
avg_bandwidth = (seq_write + seq_read + seq_copy) / 3
bandwidth_score = avg_bandwidth_MB_per_sec × 0.1
latency_score = 1000 / latency_ns × 50
total = bandwidth_score + latency_score
```

Higher bandwidth and lower latency both increase the score.

### Disk Score

| Sub-test | Measurement |
|----------|-------------|
| Sequential Write | bytes/sec (1 MB blocks, fdatasync on Linux) |
| Sequential Read | bytes/sec (1 MB blocks) |
| Random Write | IOPS (4 KB blocks, 4096 random offsets) |
| Random Read | IOPS (4 KB blocks, 4096 random offsets) |

```text
seq_score = (seq_write + seq_read) MB/s × 0.5
iops_score = (rand_write_iops + rand_read_iops) × 0.005
total = seq_score + iops_score
```

### Overall Score

```text
overall = cpu_total + memory_total + disk_total
```

Typical score range: **5,000 - 30,000** for consumer hardware.

## Cross-Compilation

The default `zig build` compiles all 14 targets:

```bash
zig build -Doptimize=ReleaseSmall
# Output: zig-out/bin/zenith-{target}
```

### Supported Targets

| OS | Architectures |
|----|---------------|
| Linux | x86_64, aarch64, arm, riscv64, s390x, ppc64le, i386, loongarch64 |
| Windows | x86_64, i386, aarch64 |
| macOS | x86_64, aarch64 (Apple Silicon) |
| FreeBSD | x86_64 |

Total: **14 targets** producing 14 binaries from a single `zig build`.

## System Information

| Category | Details |
| --- | --- |
| OS | Full name (e.g. "Ubuntu 22.04 LTS"), kernel |
| CPU | Model, physical cores, logical threads, L1/L2/L3 cache |
| Memory | Total, used, available, swap |
| Disk | Per-drive space usage with mount points |
| Network | Public/local IP, NAT type, ISP, ASN, geolocation |
| Virtualization | Hypervisor detection (Hyper-V, KVM, VMware, Xen, VirtualBox, QEMU) |
| Other | Hostname, uptime, timezone, system load |

## Terminal Compatibility

| Feature | Modern terminal | Legacy (cmd.exe) | Pipe / redirect |
| --- | --- | --- | --- |
| Color | ANSI 24-bit (Miku theme) | Enabled via VT100 API | Disabled |
| Unicode | Box-drawing chars | ASCII fallback (`+=/\|-`) | ASCII fallback |
| Width | Auto-detect | Auto-detect | 80 columns |

## Security Notes

- **Network info uses HTTP** (not HTTPS) to query `ip-api.com`. The free tier only supports HTTP. Use `--no-network` to skip in sensitive environments.
- **Input validation**: CLI parameters are clamped to safe ranges — `--disk-size` max 4096 MB, `--threads` max 1024, `--time` range 1-3600s.
- **Temp files**: Disk benchmarks create `zenith_bench.tmp` in the `--disk-path` directory. Cleaned up automatically after each test round.

## Adding New Modules

See the extension-point documentation in `src/runner.zig`:

1. Create `src/bench/xxx.zig` with `XxxResult`, `run()`, and `printResults()`
2. Import in `runner.zig`
3. Add `run_xxx: bool = true` and `--no-xxx` flag in `cli.zig`
4. Add the benchmark block in `runner.zig` following the existing pattern

## Build Requirements

- [Zig](https://ziglang.org/download/) >= 0.15.0

## License

See [LICENSE](LICENSE) for details.
