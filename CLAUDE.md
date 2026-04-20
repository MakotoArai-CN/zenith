# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Zenith is a cross-platform system benchmark CLI tool written in Zig. It produces a single binary with zero runtime dependencies, targeting 14 OS/arch combinations from one build. Outputs trilingual (en/zh/ja) terminal UI with Miku-themed ANSI colors.

## Build Commands

```bash
zig build -Doptimize=ReleaseSmall   # Build all 14 cross-compilation targets
zig build run -Doptimize=ReleaseSmall  # Build and run native binary
zig build run -Doptimize=ReleaseSmall -- -l zh  # Run with specific language
zig build test                       # Run unit tests (native only)
```

Cross-compiled binaries go to `zig-out/bin/zenith-{os}-{arch}`. Requires Zig >= 0.15.1.

## Architecture

**Entry flow:** `main.zig` -> `cli.zig` (parse args into `Config`) -> `runner.zig` (orchestrate all modules)

**Core modules:**
- `cli.zig` — CLI parsing via `zig-clap`. Defines `Config`, `Language`, `CpuMethod`, `DiskMethod`. All user-facing flags live here.
- `runner.zig` — Orchestrator. Calls sysinfo/netinfo collectors, then runs enabled benchmarks in sequence. Contains the extension-point documentation for adding new benchmark modules.
- `output.zig` — Terminal rendering: box-drawing, progress bars, score formatting. Uses `TermCaps` to degrade gracefully (ANSI -> ASCII, auto-width).
- `terminal.zig` — Detects terminal capabilities (color, unicode, width) per-platform (Windows VT100 API vs POSIX ioctl).
- `sysinfo.zig` — OS/CPU/memory/disk info collection. Platform-specific implementations via `builtin.os.tag` switches (Linux reads `/proc`/`/sys`, Windows uses kernel32, macOS uses sysctl, FreeBSD similar).
- `netinfo.zig` — Public IP, ISP, geolocation via HTTP to `ip-api.com` (free tier, HTTP only).

**Benchmark modules** (in `src/bench/`):
- `cpu.zig` — Prime sieve + matrix multiply, single & multi-threaded
- `memory.zig` — Sequential read/write/copy, random read, pointer-chase latency
- `disk.zig` — Sequential + random I/O with configurable file size

**Shared utilities:**
- `sampler.zig` — Collects up to 1024 samples, returns median via insertion sort
- `timer.zig` — Wraps `std.time` for duration-based benchmark loops

## Build System Details

`build.zig` does two things:
1. **Cross-compilation loop** — iterates `cross_targets` array (14 entries), each producing a `zenith-{name}` binary. Linux targets use musl ABI with static linkage. FreeBSD/macOS/Windows use default (dynamic) linkage.
2. **Native target** — for `run` and `test` steps.

Version string comes from `build_options` module (`b.addOptions()`), defined as a const in `build.zig`. Must be kept in sync with `build.zig.zon` `.version` field.

## Adding a New Benchmark Module

Follow the pattern in `runner.zig` header comment:
1. Create `src/bench/xxx.zig` with `XxxResult` (must have `total_score: f64`), `run()`, and `printResults()`
2. Import in `runner.zig`
3. Add `run_xxx: bool = true` and `--no-xxx` flag in `cli.zig`
4. Add the benchmark block in `runner.zig`

## CI/CD

GitHub Actions (`.github/workflows/ci.yml`): tests on ubuntu/windows/macos, then builds all 14 targets and creates a GitHub Release with per-platform archives. Version is extracted from `build.zig.zon`.

## Key Constraints

- No libc dependency — pure Zig stdlib only. Do not add `@cImport` or `linkLibC`.
- FreeBSD cannot use static linkage (Zig limitation). Linux must use musl+static for portability.
- Network info uses HTTP (not HTTPS) — `ip-api.com` free tier limitation.
- All benchmarks use duration-based sampling with median aggregation (warmup -> timed loop -> median).
- Terminal output must degrade: ANSI color -> no color, Unicode box-drawing -> ASCII, auto-width -> 80 columns.
