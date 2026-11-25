# 给上游的材料

**已提交（2026-11-25）**：[moonbitlang/moon#2647](https://github.com/moonbitlang/moon/issues/2647) — *Expose coverage output for instrumented binaries, not only under `moon test`*，OPEN。

第 2 条**没有提**，原因写在下面——留在这里是为了说明"为什么没提"，也免得以后有人重复劳动。

---

## 1. 已提交的 issue（#2647）

状态：OPEN，2026-11-25 由 QYF795 提交。提交时用的是上游仓库的 Feature Request 模板（Motivation / Detailed Description / Related Issues / Checklist）。

**标题**：Expose coverage output for instrumented binaries, not just `moon test`

**正文**：

````markdown
### Summary

`--enable-coverage` only produces `moonbit_coverage_*.txt` when the program is
started by `moon test`. A binary built with `--enable-coverage` and run directly
does not write anything, so a long-running program (a fuzzer, a server, a CLI)
cannot use the coverage data the compiler already instruments.

### Environment

- moon 0.1.20261012 (748b63c), moonc v0.10.15+943464bfa
- target: wasm-gc (native behaves the same)

### Steps to reproduce

```bash
moon new covprobe
cd covprobe

# 1. build with coverage and run the resulting program
moon build --target wasm-gc --enable-coverage
moon run cmd/main --target wasm-gc

# 2. look for the coverage file
find . -name 'moonbit_coverage*'      # nothing

# 3. now let moon test start it
cat > covprobe_test.mbt <<'EOF'
test "sample" {
  assert_eq(1 + 1, 2)
}
EOF
moon test --target wasm-gc --enable-coverage
find . -name 'moonbit_coverage*'
# ./_build/moonbit_coverage_1795533309525689_c36d0a2a.txt
```

### Expected

Either

- the instrumented binary flushes coverage on exit, or
- there is a documented way to ask it to (a function such as
  `@coverage.flush()`, or an environment variable such as
  `MOONBIT_COVERAGE_OUT=<path>`), or
- `--enable-coverage` refuses to build when nothing will consume the data,
  so the gap is visible at build time instead of silently doing nothing.

### Actual

The instrumented binary runs, and the data is discarded. The only way to see it
is to have `moon test` start the program, which a long-running consumer cannot do.

### Why it matters

Coverage-guided fuzzing is the obvious consumer: a loop that calls into the
program tens of thousands of times wants the cumulative block set to decide
which input is worth keeping. Today that means hand-written instrumentation
(a `@cov.hit(id)` call at every interesting branch) or re-implementing the
feedback from output shapes — both strictly worse than reusing what the compiler
already emits. The same applies to logging coverage from a server process or a
CLI run.

A per-run flush (append, or overwrite-per-PID) would be enough; the format does
not need to change.
````

**验证记录**：复现步骤在 `moon 0.1.20261012 (748b63c)` / `moonc v0.10.15+943464bfa` 上实测；`moon run` 与直接执行二进制都试过，两种方式都不产出文件，而 `moon test --enable-coverage` 会产出 `_build/moonbit_coverage_*.txt`。

---

## 2. 没提的：`@bigint` 大数往返

原本准备提的第二条是"约 4,000 位十进制数上 `parse → to_string → parse` 不相等"。**用当前 API 复验时无法复现**，所以不提：

- 300 / 600 / 1200 / 2000 / 3000 位的确定性串：全部往返正常（`targets/stdbigint_large_test.mbt`，每次 `moon test` 都会跑）。
- 60 组 3,000–4,000 位的随机串：全部往返正常（`targets/stdbigint_hunt_test.mbt`）。
- 最早那条 `inconsistent:print-parse:4087:4095` 是在**已弃用的** `BigInt::from_string` 上观察到的；切换到 `@string.parse_bigint` 之后没有再出现。

结论：**没有可复现的最小反例，就不能提交给上游。** 这条观察保留在 `docs/findings.md` §10.7 里，标注为"观察、未归因"。
