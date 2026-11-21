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

## 4. 崩溃隔离：让打崩自己的 target 变成一条 finding


`targets/boom.mbt` 遇到字节 `0xDE` 就 abort，用来验证隔离路径：

```
$ moon run cli --target native -- run --target boom --seed 1 --max-execs 3000 --isolate

execs    : 3000 in 11497 ms  (260 exec/s)
findings : 1
  [crash] boom  input=de63 (2B)
        worker exited with code -1073740791 on input 247 of 512
```

两个数字值得看：`input=de63` 是 2 字节的复现（隔离模式下也能缩，只是这两个字节缺一不可）；`input 247 of 512` 是子进程死在批次的第 247 条 —— 由"结果文件里已经有 247 行"直接得出，没有二分。

不开 `--isolate` 跑同一个 target，fuzzer 自己会被 abort 带走。这不是 bug，是它证明的那件事。

## 5. 反馈信号：插桩 vs 形状（20,000 次执行）


| target | 反馈 | 语料 | 独立签名 |
|---|---|---|---|
| `csv`（插桩 10 个状态位） | 路径指纹 | 94 | 92 |
| `json`（未插桩） | 输出形状 | 237 | 231 |
| `varint`（插桩，13 个 id） | 路径指纹 | 19 | 17 |

读法：`csv` 的 94 条语料存的是不同的扫描路径（引号状态、转义、丢字节的位置），`json` 的 237 条只是摘要字符串的不同变体。语料条数不是指标，**独立签名才是**——它近似"探索过多少条路径"。

`varint` 只有 19 条，因为它的路径空间本来就小（13 个 id、终止位置 0–9），很快就穷尽了。这不是缺陷，是覆盖率反馈在说真话。

## 6. 全部 17 个 target 的体检结果（各 50,000 次执行，seed 1）


| target | oracle | findings | 独立签名 | 备注 |
|---|---|---|---|---|
| `varint` | diff | 3 | 17 | 32 位截断（真 bug，见上） |
| `decimal` | roundtrip | 1 | 27 | 溢出导致 `-0.96` 被自己拒绝 |
| `json` | metamorphic | 0 | 231 | 空白不变性成立 |
| `csv` | smoke | 0 | 92 | 无崩溃 |
| `base64` | roundtrip | 0 | 4 | 接受面窄（64 字符字母表），路径空间本来就小 |
| `tlv` | roundtrip | 0 | 10 | 长度算术与终止符规则一致 |
| `utf8` | diff | 0 | 220 | **两个独立实现 5 万次输入零分歧** |
| `urlenc` | roundtrip | 0 | 20 | 严格拒绝非规范编码（`%41`、小写 hex、字面量 `/`） |
| `protobuf` | roundtrip | 0 | 163 | 非最小 varint、字段号 0、组类型、截断长度全部拒绝 |
| `rle` | roundtrip | 0 | 32 | 宽度纪律（5 bit 值、`groups*5` 字节）单独校验 |
| `csvstrict` | roundtrip | 0 | 51 | 严格：多余引号、CR、空尾行都拒绝 |
| `arff` | comment-invariant | 0 | 41 | 注释不改变摘要（含行首/行中/行尾） |
| `fixed` | roundtrip | 0 | 12 | 列宽几何、前导零、行长度 |
| `ini` | comment-invariant | 0 | 22 | 分区外的键值、未闭合分区 |
| `props` | roundtrip | 0 | 16 | 空格与等号必须转义 |
| `boom` | smoke + isolate | 1（crash） | — | 演示崩溃隔离 |

`utf8` 这一行值得单独说：状态机版（数还欠几个续字节、收紧第一个续字节的上下界）和码点版（显式检查 overlong / 代理区 / U+10FFFF）在 5 万条随机输入上给出**完全相同**的判定与字符数。这不能证明它们没有 bug，但能证明"两个结构不同的实现互为 oracle"这件事是可操作的——而且它不需要写规范、只需要写两遍。

`base64` 只有 4 个签名，是覆盖反馈在如实说"这个目标的可达路径很少"：随机字节几乎不可能落进 64 字符字母表。要真的探索它，需要结构化的变异器（按字母表生成），而不是更多次随机。

## 7. 性能


| target | 后端 | 执行数 | 耗时 | 吞吐 |
|---|---|---|---|---|
| `varint`（双实现差分） | wasm-gc | 100,000 | 497 ms | **201,207 exec/s** |
| `json`（单次解析 + oracle 再跑一次） | wasm-gc | 100,000 | 697 ms | 143,472 exec/s |
| `csv`（单次解析） | wasm-gc | 100,000 | 632 ms | 158,227 exec/s |
| `varint` | js (node) | 100,000 | 1,615 ms | 61,919 exec/s |
| `varint` | native (release) | 200,000 | 1,042 ms | 191,938 exec/s |
| `varint` | native (debug) | 50,000 | 1,243 ms | 40,225 exec/s |
| `varint`（--isolate, batch 512） | native (debug) | 20,000 | 8,035 ms | 2,489 exec/s |
| `boom`（--isolate，每批可能崩） | native (debug) | 3,000 | 11,497 ms | 260 exec/s |
| `varint`（--isolate --no-shrink） | native (debug) | 3,000 | 1,104 ms | 2,717 exec/s |
| `varint`（--isolate，默认带 shrink） | native (debug) | 3,000 | 30,352 ms | 98 exec/s |
| `varint`（--isolate --jobs 4，batch 512） | native (debug) | 20,000 | 5,143 ms | 3,888 exec/s |
| `varint`（--isolate --jobs 8，batch 2048） | native (debug) | 20,000 | 2,710 ms | 7,380 exec/s |
| `varint`（--isolate --jobs 8，batch 4096） | native (debug) | 20,000 | 2,399 ms | **8,336 exec/s** |
| `varint` | js (node) | 5,000 | 123 ms | 40,650 exec/s |

读法：

- 差分模式的成本是"两次实现 + oracle 里再跑一次"，所以它比 smoke 慢，但仍在 20 万次/秒量级；
- js 后端约慢 3.2 倍，属于预期（wasm-gc 有 AOT 与更紧凑的对象布局）；
- 这些数字里**没有**进程启动开销——v0.1 是进程内直调，进程池落地后吞吐会下降一档（预计 3–5 万 exec/s），这是拿崩溃隔离必须付的价钱。

## 8. 确定性：三个后端逐字节一致


同 seed、同执行数，`wasm-gc` / `js` / `native` 三个后端产出的 JSONL **逐字节相同**（包括 finding 的 exec 序号），语料规模也一致（52 entries / 51 buckets / 46 novel）：

```
$ moon run cli --target wasm-gc -- run --target varint --seed 1 --max-execs 50000 --json > a.jsonl
$ moon run cli --target js      -- run --target varint --seed 1 --max-execs 50000 --json > b.jsonl
$ moon run cli --target native  -- run --target varint --seed 1 --max-execs 50000 --json > c.jsonl
$ diff a.jsonl b.jsonl && diff a.jsonl c.jsonl    # 无输出
```

```json
{"kind":"mismatch","target":"varint","exec":12,"input":"92ffffff0f",...}
{"kind":"mismatch","target":"varint","exec":337,"input":"808080806e",...}
{"kind":"mismatch","target":"varint","exec":575,"input":"8c80ffff66",...}
```

为什么这很重要：跨后端差分的工作流要求"同一个 seed 在两个后端跑出同一批输入"，否则 diff 出来的全是噪声。v0.1 证明了这条前提成立——`moon run --json` + `diff` 就是可用的跨后端差分，不需要新代码。

## 9. 测试


```
$ moon test --target wasm-gc
Total tests: 48, passed: 48, failed: 0.
```

覆盖的是**契约**而不是覆盖率数字：RNG 同 seed 同流、`shape` 折叠数字、语料去重、ddmin 收敛到 1 字节、JSON/CSV 的接受/拒绝边界、差分对在 32 位内一致/32 位外分歧、engine 同 seed 复现同一 finding、每个 finding 能独立 replay、报告三种格式自洽。

---

## 10. 标准库体检：MoonBit `@json`


> 这是本项目唯一一个"被测对象不是我们自己写的东西"的 target。目的不是再找 bug，而是回答一个可以引用的问题：**MoonBit 标准库的 JSON 解析器扛不扛得住敌意输入。**

### 10.1 方法

`stdjson` target 把字节解成文本（非 UTF-8 直接判 `err:utf8`），然后用**标准库自洽性**当 oracle：

1. `@json.valid(s)` 说合法，`@json.parse(s)` 就必须成功；
2. `parse` 成功的东西，`stringify` 出来必须还能被 `parse` 接受。

任一条不成立，就报 `inconsistent:valid-but-parse-failed` 或 `inconsistent:restringify-invalid`。

种子里既有权角（`1e999`、`-0.0`、18 位整数）、也有结构（嵌套对象/数组）、还有转义（`\u0041`、surrogate pair、`\n\t\"`）。

### 10.2 结果

| 运行 | 执行数 | 语料 / 签名 | finding |
|---|---|---|---|
| 进程内（wasm-gc） | 50,000 | 70 / 68 | **0** |
| 隔离（native，`--jobs 2`） | 20,000 | 63 / 61 | **0**（无 panic） |

更长的跑（20 万 × 三后端 + 隔离，共 60 万次，含阳性对照）见 **5.6**。

也就是说：**5 万条敌意输入，标准库既没 panic，也没出现 `valid` 与 `parse` 的分歧，`stringify` 的输出也始终能再解析。**

### 10.3 复现

```bash
moon run cli --target wasm-gc -- run --target stdjson --max-execs 50000
moon run cli --target native -- run --target stdjson --max-execs 20000 --isolate --no-shrink --jobs 2
```

### 10.4 这条结论的边界（重要）

- 它证明的是**自洽性**，不是**规范符合性**。一个"总是接受一切"的解析器完全自洽，但不符合 JSON 规范——那个方向要靠外部参考实现做差分，本项目没有做。
- 它只覆盖 `parse` / `valid` / `stringify` 三个入口，没有测 `derive(FromJson)` 派生路径。
- 标准库不能插桩，所以这里的"覆盖率"只有 4 个我们自己的 id；语料靠输出形状（类型 + 尺寸档）区分，68 个签名不代表 68 条标准库内部路径。
- 一次不崩不等于永远不崩。这里给的是"5 万条 × 两个后端"的证据，不是证明。

### 10.5 为什么仍然值得放进验收材料

因为它是**可被引用的负面结论**：标准库在敌意输入下没露问题，这件事本身对生态有意义，而且它把一个"感觉应该没问题"的假设变成了一条能重跑的命令。如果以后有人在上游改了 `@json`，把 `--target stdjson` 挂进 CI 就能立刻发现回归。

### 10.6 长时跑记录（2026-11-20）

一次 60 万次执行的标准库体检，四种配置 + 两个阳性对照。机器：Windows 11 / Ryzen（与全文其它数据同一台）。

| # | 后端 | 模式 | 执行数 | 耗时 | exec/s | 语料 / 签名 | finding |
|---|---|---|---|---|---|---|---|
| A | wasm-gc | 进程内 | 200,000 | 1.52 s | 131,752 | 90 / 88 | **0** |
| B | native | 进程内 | 200,000 | 4.71 s | 42,507 | 90 / 88 | **0** |
| C | js | 进程内 | 200,000 | 4.87 s | 41,109 | 90 / 88 | **0** |
| D | native | 隔离，`--jobs 4 --batch-size 2048` | 200,000 | 28.5 s | 7,010 | 80 / 78 | **0** |

三件事值得单独说：

1. **三个后端的探索完全一致**：A、B、C 的语料都是 90 条 / 88 个签名 / 82 条新路径，逐项相同。跨后端确定性不只体现在 JSONL 上，也体现在"走到的路径集合"上。
2. **隔离模式少走了 10 条**：80 vs 90。原因是批次调度与逐条调度不同——一批里同一个输入被改两次，和逐条调度时的变异序列不是一回事。这不是 bug，但说明"隔离模式的覆盖 ≠ 进程内覆盖"，两者不能互相替代。
3. **零 finding 必须配阳性对照**，否则可能是工具坏了：

| 对照 | 配置 | 结果 |
|---|---|---|
| `varint`（已知 32 位截断） | wasm-gc 进程内，200,000 次 | **3 条 finding**（`ffffffff34`、`ff88ff8822`、`bbbdffbc5d`） |
| `boom`（必崩输入 `de`） | native 隔离，1,500 次 | **1 条 crash**（`de`，批次内第 9 个输入） |

同一套工具、同一轮跑，在标准库上给出 0，在已知有 bug 的 target 上照常给出 3 和 1。所以"0"是结论，不是故障。

复现：

```bash
moon run cli --target wasm-gc -- run --target stdjson --max-execs 200000
moon run cli --target js      -- run --target stdjson --max-execs 200000
moon run cli --target native  -- run --target stdjson --max-execs 200000 --isolate --no-shrink --jobs 4 --batch-size 2048
moon run cli --target wasm-gc -- run --target varint  --max-execs 200000
```

---

### 10.7 第二个标准库入口：@bigint（2026-11-22）

`stdjson` 之后又接了一个标准库 target：大整数解析（`@string.parse_bigint`，底层是 `moonbitlang/core/bigint`）。判据仍是自洽性——打印出来的必须能解析回同一个值，换个基数打印再解析也必须相等。

#### 观察一：旧的 `from_string` 对非法输入会 abort，新 API 会 raise

```moonbit
@bigint.BigInt::from_string("+5")     // abort: core/bigint/bigint_default.mbt:1289
@bigint.BigInt::from_string("0x1f")   // 同上
@string.parse_bigint("+5")            // raise, 可以被 catch
```

`BigInt::from_string` 在最新工具链上已经标记为 deprecated，替代品 `@string.parse_bigint` 带 `raise`，所以非法输入可以干净地报错。**这不是 bug，是标准库已经改对了**——target 因此改用新 API，`+5` / `0x1f` 这类输入从"杀掉进程"变成 `err:parse`，也就可以放进 fuzz 输入空间了。

#### 观察二：约 4,000 位十进制数上，print/parse 往返会不等

```
inconsistent:print-parse:4087:4095
```

一次 fuzz 运行抓到的输入：4,095 位、只含 `0` 和 `2` 的合法十进制串；打印出 4,087 位（长度正确，说明打印没截断），重新解析后与原值不相等——分歧在解析端。当前 target 把输入限制在 256 位，所以这个边界**只是记录、没有被继续追**。

#### 一处必须记下来的自我更正

这一节初稿写过"标准库在 1,024 位会 panic"。**那是错的**：panic 来自我自己测试里的 `.unwrap()`——测试用的 LCG 在 Int32 上溢出，产生了带负号的畸形字符串，`parse_bigint` 正确地 raise 成 `None`，`unwrap` 再把它变成 panic。把生成器改成不会溢出的写法后，1,024 位、4,095 位的合法字符串都能正常解析。

教训和 D13 那次一样：**测试脚手架崩了，最先怀疑的应该是脚手架**。标准库背了大约十分钟的黑锅。

#### 一处工程取舍：换基数往返没有做

原本还有一条"换基数打印再解析"的检查，但标准库把这个参数的标签从 `base~` 改成了 `radix=`（随工具链版本变化），同一份源码无法同时编译过新旧两版。与其把 CI 钉死在某个编译器版本上，不如去掉这一条，并在文档里说明原因。十进制往返仍然保留。

#### 结果（输入上限 256 位）

| 运行 | 执行数 | 语料 / 签名 | finding |
|---|---|---|---|
| wasm-gc 进程内 | 20,000 | 84 / 84 | **0** |
| wasm-gc 进程内 | 50,000 | 107 / 107 | **0** |

上限取 256 位的理由有两条，都是测出来的：十进制解析代价随位数超线性增长（4,000 位会把循环从 ~126k exec/s 压到 ~400），以及 256 位（约 850 bit）已经能覆盖多 limb 运算。

## 11. 长跑饱和实验（2026-11-22）


问题：跑得越久，是否会出现**新的 bug 类别**？三个有代表性的 target 各跑了百万到两百万次。

| target | oracle | 执行数 | 耗时 | exec/s | 签名 | finding | 新类别 |
|---|---|---|---|---|---|---|---|
| `varint` | diff | 2,000,000 | 6.9 s | 287,976 | 22 | **3** | 无 |
| `utf8` | diff | 2,000,000 | 9.6 s | 208,376 | 245 | **0** | — |
| `decimal` | roundtrip | 1,000,000 | 3.3 s | 305,436 | 28 | **1** | 无 |

### 11.1 结论：会饱和，而且很快

`varint` 的签名从 20,000 次时的 16 个只涨到 2,000,000 次时的 22 个（+37%），而 finding **仍然是那 3 条，全部是同一类**：5 字节输入、第 5 个字节把值推出 32 位。

```
[mismatch] varint  input=ffffffff34 (5B)   expected v:12348030975 got v:-536870913
[mismatch] varint  input=ff88ff8822 (5B)   expected v:9145664639  got v:555730047
[mismatch] varint  input=bbbdffbc5d (5B)   expected v:-4828151425395851346 got v:-2
```

三条的形状完全一样：`len == 5 && shift == 28`。**去重把"同一个 bug 的无数实例"折成了 3 条**，这正是它该做的事——如果报告 3,000 条同源 finding，人只会关掉它。

`utf8` 更彻底：两百万条输入，两个独立实现零分歧，245 个签名说明路径在扩，但没有一条分歧。这类"对称实现"的 bug 一旦存在，几万次就该出现；两百万次还是 0，基本可以判定这对实现在测试覆盖的输入空间上一致。

### 11.2 为什么这对验收有意义

- **"跑得更久"不是质量指标**：2,000,000 次换来的签名增量是 +37%，bug 类别增量是 0。真正值钱的是**换 oracle**（差分 → 往返 → 自洽性）和**换变异策略**（字节级 → 字段级），不是加执行数。
- **签名数与 bug 数无关**：`utf8` 有 245 个签名、0 个 bug；`varint` 只有 22 个签名、3 个 bug。语料规模说明"探索面"，不说明"问题密度"。
- **饱和点是可测的**：同一 seed 下签名数进入平台期，就是该换方向的信号。

复现：

```bash
moon run cli --target wasm-gc -- run --target varint  --max-execs 2000000 --max-findings 100
moon run cli --target wasm-gc -- run --target utf8    --max-execs 2000000 --max-findings 100
moon run cli --target wasm-gc -- run --target decimal --max-execs 1000000 --max-findings 100
```
