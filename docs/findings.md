# 跑出来的结果（可复现）

所有数字都来自同一台机器（Windows 11 / Ryzen，wasm-gc 与 js 后端），命令都写在下面，任何人可以重跑。

## 1. 演示用例：varint 解码器的 32 位截断

`targets/varint.mbt` 里有一对实现：

- `varint_ref`：LEB128 解码到 `Int64`，正确；
- `varint_fast`：解码到 32 位 `Int`，`b << shift` 没有检查 `shift` 宽度。

差分 oracle 在**第 12 次执行**就抓到了第一个反例：

```json
{"kind":"mismatch","target":"varint","exec":12,"input":"92ffffff0f","ascii":".....","detail":"expected v:4294967186 got v:-110"}
```

根因：`0x92 0xff 0xff 0xff 0x0f` 是一个 5 字节 varint，真值 `4294967186 = 2^32 + 114`，超过 32 位；`value | (b << shift)` 在 `shift >= 32` 时被静默截断成 `-110`。**它不崩、不报错，只是算错**——这正是只有差分 oracle 才能发现的一类 bug，也是"经得起检验"最需要的那类。

最小化后是 **5 字节**（ddmin 从变异体的几十字节缩到这个长度），25 轮内收敛。

复现：

```bash
moon run cli --target wasm-gc -- run --target varint --seed 1 --max-execs 50000
moon run cli --target wasm-gc -- replay --target varint --hex 92ffffff0f
moon run cli --target wasm-gc -- minimize --target varint --hex 92ffffff0f00010203
```

`replay` 会独立复算一次（不依赖 session 状态），`minimize` 会把任意一个反例缩到最小。

## 2. 第二个演示用例：自检 target 抓到的溢出

`targets/decimal.mbt` 走"自检 target"路线：body 自己算 `parse → format → parse`，把不一致写成 `roundtrip:` 开头的诊断，oracle 只有一行——拒绝这种诊断。

```
$ moon run cli --target wasm-gc -- run --target decimal --seed 1 --max-execs 20000

target   : decimal  (oracle: decimal.roundtrip)
execs    : 20000 in 107 ms  (186915 exec/s)
findings : 1
  [violation] decimal  input=3432393439363732 (8B)
        roundtrip:rejected:-0.96
```

`3432393439363732` 就是 ASCII `42949672`：解析后 `units * 100 = 4294967200`，在 32 位 `Int` 上溢出成 `-96`；格式化得到 `-0.96`；而解析器有一条"负数整数部分不能为 0"的规则，于是拒绝。**两条各自看起来都合理的规则，在溢出这条路径上互相矛盾** —— 这正是 round-trip 这类性质能自动发现、而手写用例几乎想不到的东西。

## 3. 没有被"发现"的，同样重要

| target | oracle | 执行数 | finding | 结论 |
|---|---|---|---|---|
| `json` | 空白不变性（ metamorphic ） | 100,000 | **0** | 手写 JSON 校验器在"前后空白不改变接受/拒绝"这条性质上成立 |
| `csv` | smoke | 100,000 | **0** | 语料涨到 54 条，无异常；说明 smoke 模式只保证"不崩"，不保证"对" |

这一栏是刻意的：一个 fuzzer 只在"确实有 bug"时才报警，比一个天天报警的 fuzzer 有用得多。早期版本曾在这里报出 9 条"violation"，全部是**我自己 oracle 的假阳性**——我最初比较的是完整输出字符串，而错误信息里带位置（`@0` → `@1`），追加空格当然会变。修正为只比较"接受/拒绝"后归零。这个教训写进了 `DEVLOG.md`。

## 4. 性能

| target | 后端 | 执行数 | 耗时 | 吞吐 |
|---|---|---|---|---|
| `varint`（双实现差分） | wasm-gc | 100,000 | 497 ms | **201,207 exec/s** |
| `json`（单次解析 + oracle 再跑一次） | wasm-gc | 100,000 | 697 ms | 143,472 exec/s |
| `csv`（单次解析） | wasm-gc | 100,000 | 632 ms | 158,227 exec/s |
| `varint` | js (node) | 100,000 | 1,615 ms | 61,919 exec/s |
| `varint` | js (node) | 5,000 | 123 ms | 40,650 exec/s |

读法：

- 差分模式的成本是"两次实现 + oracle 里再跑一次"，所以它比 smoke 慢，但仍在 20 万次/秒量级；
- js 后端约慢 3.2 倍，属于预期（wasm-gc 有 AOT 与更紧凑的对象布局）；
- 这些数字里**没有**进程启动开销——v0.1 是进程内直调，进程池落地后吞吐会下降一档（预计 3–5 万 exec/s），这是拿崩溃隔离必须付的价钱。

## 5. 确定性：跨后端逐字节一致

同 seed、同执行数，两个后端产出的 JSONL **逐字节相同**（包括 finding 的 exec 序号）：

```
$ moon run cli --target wasm-gc -- run --target varint --seed 1 --max-execs 50000 --json > a.jsonl
$ moon run cli --target js      -- run --target varint --seed 1 --max-execs 50000 --json > b.jsonl
$ diff a.jsonl b.jsonl     # 无输出
```

```json
{"kind":"mismatch","target":"varint","exec":12,"input":"92ffffff0f",...}
{"kind":"mismatch","target":"varint","exec":337,"input":"808080806e",...}
{"kind":"mismatch","target":"varint","exec":575,"input":"8c80ffff66",...}
```

为什么这很重要：跨后端差分的工作流要求"同一个 seed 在两个后端跑出同一批输入"，否则 diff 出来的全是噪声。v0.1 证明了这条前提成立——`moon run --json` + `diff` 就是可用的跨后端差分，不需要新代码。

## 6. 测试

```
$ moon test --target wasm-gc
Total tests: 48, passed: 48, failed: 0.
```

覆盖的是**契约**而不是覆盖率数字：RNG 同 seed 同流、`shape` 折叠数字、语料去重、ddmin 收敛到 1 字节、JSON/CSV 的接受/拒绝边界、差分对在 32 位内一致/32 位外分歧、engine 同 seed 复现同一 finding、每个 finding 能独立 replay、报告三种格式自洽。
