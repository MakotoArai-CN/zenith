<div align="center">

<img src="https://raw.githubusercontent.com/MakotoArai-CN/zenith/main/icon.svg" width="200" height="200">
<h1>Zenith</h1>

[English](README.md) | [中文文档](README_ZH.md)
</div>

Zigで書かれた軽量クロスプラットフォームシステムベンチマークツール。シングルバイナリ、依存関係なし。

## 機能

- **システム情報** — ホスト名、OS、アーキテクチャ、カーネル、CPUモデル/コア/キャッシュ、メモリ/スワップ、ディスク容量、稼働時間、タイムゾーン、仮想化検出、システム負荷
- **ネットワーク情報** — パブリックIP、ローカルIP、NAT検出、ISP/ASN、地理位置情報
- **CPUベンチマーク** — 素数計算、行列乗算（シングル＆マルチスレッド）
- **メモリベンチマーク** — シーケンシャル読み/書き/コピー、ランダム読取、アクセス遅延
- **ディスクベンチマーク** — シーケンシャル読み/書き、ランダムIOPS
- **クロスプラットフォーム** — Linux、Windows、macOS、FreeBSD
- **マルチアーキテクチャ** — x86_64、aarch64、arm、riscv64、s390x、ppc64le、i386、loongarch64
- **三言語対応** — English、中文、日本語
- **自動言語検出** — システム言語を自動検出、`-l` で上書き可能
- **ターミナル適応** — カラー、Unicode、ターミナル幅を自動検出。レガシーターミナル（Windows cmd.exe等）ではASCIIフォールバック
- **持続時間ベーステスト** — ウォームアップ + 時限サンプリング + 中央値集計で安定した結果

## 言語サポート

| コード | 言語 | パラメータ |
|--------|------|------------|
| `en` | English | `-l en` |
| `zh` | 中文 | `-l zh` |
| `ja` | 日本語 | `-l ja` |

デフォルト：システム言語を自動検出。検出できない場合は `en`。`-l` / `--lang` で上書き。

## クイックスタート

```bash
# ビルドして実行（ネイティブ）
zig build run -Doptimize=ReleaseSmall

# 全14クロスコンパイルターゲットをビルド
zig build -Doptimize=ReleaseSmall

# 日本語で実行
zig build run -Doptimize=ReleaseSmall -- -l ja
```

## 使い方

```text
zenith [オプション]

オプション:
  -h, --help             ヘルプを表示
  -v, --version          バージョンを表示
  -l, --lang <LANG>      言語: en, zh, ja (デフォルト: 自動検出)
      --no-cpu           CPUベンチマークをスキップ
      --no-memory        メモリベンチマークをスキップ
      --no-disk          ディスクベンチマークをスキップ
      --no-sysinfo       システム情報をスキップ
      --no-network       ネットワーク情報をスキップ
      --cpu-method <M>   CPU方式: prime, matrix, all (デフォルト: all)
      --threads <N>      スレッド数, 0=自動 (デフォルト: 0)
      --cpu-threads <N>  --threads のエイリアス
      --disk-method <M>  ディスク方式: sequential, random, all (デフォルト: all)
      --disk-path <P>    ディスクテストパス (デフォルト: /tmp)
      --disk-size <N>    ディスクテストサイズ MB (デフォルト: 128, 最大: 4096)
      --iterations <N>   テスト毎の反復回数 (デフォルト: 3, 最大: 100)
  -t, --time <N>         テスト毎の実行時間秒 (デフォルト: 10, 範囲: 1-3600)
      --duration <N>     --time のエイリアス
  -o, --output <FILE>    結果をファイルに保存
      --json             JSON形式で出力
```

### 例

```bash
# CPUのみ、各テスト5秒
zenith --no-memory --no-disk --no-network -t 5

# ディスクのみ、256MBテストファイル
zenith --no-cpu --no-memory --no-network --disk-size 256

# システム情報のみ（ベンチマークなし）
zenith --no-cpu --no-memory --no-disk

# 4スレッド、日本語出力
zenith --threads 4 -l ja
```

## スコアリングアルゴリズム

### テスト方法

全てのベンチマークは**持続時間ベースのサンプリング + 中央値集計**を使用：

1. **ウォームアップ** — 最初の1回を破棄し、コールドスタート効果を排除
2. **時限ループ** — `duration_secs`に達するまで繰り返し実行（デフォルト10秒）、各回で1サンプル収集
3. **中央値** — 全サンプルをソートし中央値を最終結果として使用、外れ値を排除

### CPUスコア

| サブテスト | 計算式 |
|------------|--------|
| 素数シングル | `1秒あたりの操作数 × 1` |
| 素数マルチ | `1秒あたりの操作数 × 1` |
| 行列シングル | `GFLOPS × 100` |
| 行列マルチ | `GFLOPS × 100` |
| **CPU合計** | 4つのサブスコアの合計 |

- **素数テスト**：100,000以下の素数を試し割りで計算
- **行列テスト**：128×128倍精度行列乗算、GFLOPS = `2×N³ / 時間 / 10⁹`
- マルチスレッドテストは全ワーカースレッドを並列起動（デフォルト：CPUコア数を自動検出）

### メモリスコア

| サブテスト | 測定値 |
|------------|--------|
| シーケンシャル書込 | bytes/sec（64 MBバッファ、volatile書き込み）|
| シーケンシャル読取 | bytes/sec（64 MBバッファ、volatile読み取り）|
| シーケンシャルコピー | bytes/sec（64 MB `@memcpy`）|
| ランダム読取 | bytes/sec（100万エントリのポインタチェイス）|
| アクセス遅延 | ナノ秒（リンクリストポインタチェイス）|

```text
平均帯域幅 = (逐次書 + 逐次読 + 逐次コピー) / 3
帯域幅スコア = 平均帯域幅_MB毎秒 × 0.1
レイテンシスコア = 1000 / レイテンシ_ナノ秒 × 50
合計 = 帯域幅スコア + レイテンシスコア
```

帯域幅が高く、レイテンシが低いほどスコアが高くなります。

### ディスクスコア

| サブテスト | 測定値 |
|------------|--------|
| シーケンシャル書込 | bytes/sec（1 MBブロック、Linuxではfdatasync）|
| シーケンシャル読取 | bytes/sec（1 MBブロック）|
| ランダム書込 | IOPS（4 KBブロック、4096ランダムオフセット）|
| ランダム読取 | IOPS（4 KBブロック、4096ランダムオフセット）|

```text
逐次スコア = (逐次書 + 逐次読) MB/s × 0.5
IOPSスコア = (ランダム書IOPS + ランダム読IOPS) × 0.005
合計 = 逐次スコア + IOPSスコア
```

### 総合スコア

```text
総合スコア = CPU合計 + メモリ合計 + ディスク合計
```

コンシューマハードウェアの典型的なスコア範囲：**5,000 - 30,000**。

## クロスコンパイル

デフォルトの `zig build` は全14ターゲットをコンパイル：

```bash
zig build -Doptimize=ReleaseSmall
# 出力: zig-out/bin/zenith-{target}
```

### サポートターゲット

| OS | アーキテクチャ |
|----|----------------|
| Linux | x86_64, aarch64, arm, riscv64, s390x, ppc64le, i386, loongarch64 |
| Windows | x86_64, i386, aarch64 |
| macOS | x86_64, aarch64 (Apple Silicon) |
| FreeBSD | x86_64 |

合計 **14ターゲット**、1回の `zig build` で14バイナリを生成。

## セキュリティ注記

- **ネットワーク情報はHTTPを使用**（HTTPSではない）して `ip-api.com` にクエリ。無料版はHTTPのみ対応。機密環境では `--no-network` でスキップしてください。
- **入力バリデーション**：CLIパラメータは安全な範囲に制限 — `--disk-size` 最大4096 MB、`--threads` 最大1024、`--time` 範囲1-3600秒。
- **一時ファイル**：ディスクベンチマークは `--disk-path` ディレクトリに `zenith_bench.tmp` を作成。各テストラウンド後に自動クリーンアップ。

## ビルド要件

- [Zig](https://ziglang.org/download/) >= 0.15.0

## ライセンス

詳細は [LICENSE](LICENSE) を参照。
