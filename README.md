# moonsting

[![ci](https://github.com/QYF795/moonsting/actions/workflows/ci.yml/badge.svg)](https://github.com/QYF795/moonsting/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-QYF795%2Fmoonsting-orange)](https://mooncakes.io/docs/QYF795/moonsting)
[![license](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

**给 MoonBit 补上缺失的那一层：喂进坏字节，拿回一个最小反例、一份报告和一条能粘贴进仓库的回归测试。**

零依赖，纯 MoonBit，同一个 seed 在 `wasm-gc` / `js` / `native` 三个后端产出逐字节相同的结果。验收清单与实测数据见 [docs/验收.md](docs/验收.md)；`script/demo.ps1`（或 `demo.sh`）是可跑的五幕演示。

```
$ moon run cli --target wasm-gc -- run --target varint --seed 1 --max-execs 50000

target   : varint  (oracle: diff(varint.fast,varint.ref))
execs    : 50000 in 260 ms  (192307 exec/s)
corpus   : 53 entries, 52 buckets, 47 novel inputs
findings : 3
  [mismatch] varint  input=92ffffff0f (5B)
        expected v:4294967186 got v:-110
  [mismatch] varint  input=808080806e (5B)
        expected v:-9223372036854775808 got v:-2147483648
  [mismatch] varint  input=8c80ffff66 (5B)
        expected v:27648835596 got v:1879031820
```

第一个反例在几百次执行内被发现（当前版本是第 382 次），最小化到 5 字节。完整分析见 [docs/case-varint.md](docs/case-varint.md)。

## 为什么需要它

- `moon check` / `moon test` 能证明"你想到的用例能过"，不能证明"想不到的输入不会算错"。
- 内置 `quickcheck` 只做随机属性测试，不保留"触发新路径"的输入，不会进化。
- 生态里大量手写/生成的解析器（JSON、CSV、varint、protobuf…），测试普遍薄；而**最贵的 bug 是不崩也不报错、只是结果错的那种**——它需要差分 oracle 才抓得到。

## 状态

| 能力 | 状态 |
|---|---|
| 变异引擎（havoc / 结构化 JSON / 结构化 CSV / 字典 / splice / boundary） | ✅ |
| 语料库（去重、锦标赛选择偏好短输入、trim） | ✅ |
| 三种 oracle：smoke / metamorphic / 差分双实现 | ✅ |
| ddmin 最小化（带探测次数上限） | ✅ |
| finding 按"形状"去重（避免同一 bug 报十六次） | ✅ |
| 报告：text / jsonl / 自包含 html / 回归测试生成 | ✅ |
| 语料导出（`--dump-corpus`）与续跑（`--seed-input`） | ✅ |
| CI 钩子 `--fail-on-finding`（有 finding 则非零退出） | ✅ |
| CLI：`run` / `list` / `replay` / `minimize` | ✅ |
| 同 seed 跨后端逐字节一致（wasm-gc / js / native） | ✅ 已验证 |
| 覆盖率反馈：手写插桩（`@cov.hit`）→ 路径指纹 | ✅（示例 target 已插桩） |
| 无插桩 target 自动回退到"输出形状"反馈 | ✅ |
| 插桩报告 `--cov-report`：命中的 id 段与从未命中的空洞（含隔离模式） | ✅ |
| 编译器覆盖率产物（`cov/EdgeSet`）接进引擎 | ❌ 见架构文档：普通二进制不落盘 |
| 进程隔离（`--isolate`，native）：批次 worker + 崩溃输入定位 | ✅ |
| 隔离模式下的批量最小化（一轮 ddmin = 一次 worker，`--no-shrink` 可关） | ✅ |
| 语料持久化（`--corpus-dir`，编号文件，无需 readdir） | ✅ |
| 并行 `--jobs N`（一次起 N 个 worker） | ✅ |

## 用法

```bash
# 跑内置用例
moon run cli --target wasm-gc -- run --target json   --seed 1 --max-execs 100000
moon run cli --target wasm-gc -- run --target csv    --seed 1 --max-execs 100000
moon run cli --target wasm-gc -- run --target varint --seed 1 --max-execs 100000 --emit-test

# 机器可读（可 diff、可进 CI）
moon run cli --target wasm-gc -- run --target varint --seed 1 --json > a.jsonl

# 复现与最小化
moon run cli --target wasm-gc -- replay   --target varint --hex 92ffffff0f
moon run cli --target wasm-gc -- minimize --target varint --hex 92ffffff0f00010203

# 语料导出 / 续跑（不需要文件系统 API）
moon run cli --target wasm-gc -- run --target json --max-execs 20000 --dump-corpus > corpus.txt
moon run cli --target wasm-gc -- run --target json --seed-input 612c620a --seed-input 7b7d

# 持久化语料：跑完写回，下次自动加载（native）
moon run cli --target native -- run --target csv --max-execs 200000 --corpus-dir .corpus
moon run cli --target native -- run --target csv --max-execs 200000 --corpus-dir .corpus   # 接着上次

# 列目标
moon run cli --target wasm-gc -- list
```

参数：`--target` `--seed` `--max-execs` `--time 5s` `--max-input` `--max-findings` `--seed-input`（可重复）`--json` `--html` `--emit-test` `--dump-corpus` `--cov-report` `--isolate` `--batch-size` `--no-shrink` `--fail-on-finding` `--quiet`。

> 小提醒：被 `Ctrl-C` 或强杀打断的运行，可能在当前目录留下 `.moonsting-*` 临时文件（批次、结果、启动脚本）。它们已在 `.gitignore` 里，手动删除即可——没有 `readdir` 就没法在启动时自动清理，这是 stdlib 的边界，不是懒得写。

## 反馈信号：插桩优先，形状兜底

引擎不需要知道 target 有没有插桩——它只看"这次执行报了没有"：

- **插桩过的 target**（`@cov.hit(id)`）→ 用本次执行的**路径指纹**（命中集合的哈希）做新颖性判断。同一批分支、不同顺序算同一条路径，这是有意的：顺序噪声会让语料爆掉。
- **没插桩的 target** → 回退到"输出形状"（数字折叠成 `#` 后的哈希）。

两条路径在同一份代码里，差别肉眼可见（20,000 次执行）：

| target | 反馈 | 语料 | 独立签名 |
|---|---|---|---|
| `csv`（已插桩，10 个状态位） | 路径指纹 | **94** | 92 |
| `json`（未插桩） | 输出形状 | 237 | 231 |

为什么不用编译器自带的覆盖率：`moon build --enable-coverage` 出来的二进制**跑完不落盘**（`moon test --enable-coverage` 才会写 `moonbit_coverage_*.txt`），fuzzer 没法逐次执行读取。所以选择手写插桩——AFL 管这叫 `__afl_manual`，libFuzzer 管这叫用户自定义计数器。粒度由插桩者决定，对解析器来说通常比编译器块覆盖更有意义：哪些分支值得区分，写 target 的人最清楚。

## 结构化变异

字节级 havoc 是无方向的：它找到一个 `{` 就把它改坏，之后测的全是语法错误。结构化变异按**输入的形状**分派（变异器不知道自己在喂哪个 target），让文档尽量保持合法，把战斗推进到语义层：

| 识别 | 依据 | 变异 |
|---|---|---|
| JSON | 首个非空白字节是 `{` `[` `"` 数字或 `-` | 数字换成边界值、字符串体重写（自动转义）、复制 token、删除 token 连分隔符 |
| base64 | 全部字符在字母表内（含 `=`） | 换字符、大小写翻转、增删 `=` |
| 百分号编码 | 含 `%` 且其余字符合法 | 小写 hex、把转义解回字面量、给未保留字符加 `%41` 式转义 |
| CSV | 含 `,` 或换行且无可打印之外的字节 | 沿用原来的引号/分隔符编辑 |
| 其它（二进制） | 兜底 | 能解析成 protobuf 就走字段级，能解析成 TLV 就走记录级（复制/删除/长度 ±1/截断/类型归零/类型互换/追加终止符），都不行才做长度字节 ±1 |

效果不能靠"语料条数"看。直接测：把一个 JSON 种子变异 300 次，**297 次（99%）仍然结构合法**——前提是复制以"成员"为单位、删除连 key 一起删。中间那版只删值不删 key，合法率 46%（用一个足够严的检查器量到的真实数字，见 DEVLOG 的两条度量教训）。

## 四种 oracle

| target | oracle | 判据 | 能发现什么 |
|---|---|---|---|
| `json` | `json.ws-invariance` | 前后空白不得改变"接受/拒绝" | 解析器的边界处理错误 |
| `csv` | `same` | 什么都不判 | 崩溃与 hang（smoke 阶段用） |
| `varint` | `diff(varint.fast, varint.ref)` | 两个实现必须给出同一个值 | **不崩、不报错、结果错** |
| `decimal` | `decimal.roundtrip` | target 自己给诊断，oracle 拒绝 `roundtrip:` | 解析/格式化互相矛盾、溢出 |
| `base64` | `base64.roundtrip` | 解码后再编码必须还原输入 | "能解但非规范"的编码（填充、尾位、字母表） |
| `tlv` | `tlv.roundtrip` | 序列化(解析(x)) 必须逐字节等于 x | 长度算术、截断、终止符位置 |
| `utf8` | `diff(utf8.a, utf8.b)` | 状态机版与码点解析版必须一致 | 两个独立实现的边界分歧（overlong / 代理区 / 上界） |
| `urlenc` | `urlenc.roundtrip` | 解码再编码必须还原输入 | 非规范编码（`%41`、小写 hex、字面量保留字符） |
| `protobuf` | `protobuf.roundtrip` | 序列化(解析(x)) 必须逐字节等于 x | 非最小 varint、字段号 0、组类型、截断的长度 |
| `rle` | `rle.roundtrip` | 同上，另加宽度纪律（5 bit 值、`groups*5` 字节） | 非最小头、计数 0、截断 payload、越界值 |
| `csvstrict` | `csv.strict.roundtrip` | 序列化(解析(x)) 必须逐字节等于 x | 多余引号、CR、空尾行、越界引号 |
| `arff` | `arff.comment-invariant` | 追加一行注释不得改变摘要 | 注释识别、行吞噬、属性数不匹配 |
| `fixed` | `fixed.roundtrip` | 序列化(解析(x)) 逐字节等于 x | 列宽合计不符、行长度不符、前导零 |
| `ini` | `ini.comment-invariant` | 追加注释不得改变摘要 | 分区外键值、未闭合分区、空键 |
| `props` | `props.roundtrip` | 同上（转义必须规范化） | 未转义空格/等号、未知转义、空行 |
| `stdjson` | `stdjson.consistency` | **标准库** `@json.valid` 与 `@json.parse` 必须一致；`stringify` 的输出必须能再解析 | 标准库自身的 valid/parse 分歧、panic |
| `bigint` | `stdbigint.consistency` | **标准库** 十进制解析 → 打印 → 再解析必须相等；换基数往返同样 | 长位数上的解析分歧、abort |
| `boom` | `same` | 什么都不判 | 演示崩溃隔离（遇 `0xDE` 自杀） |
| `decimal` | `decimal.roundtrip` | target 自己给出诊断，oracle 拒绝 `roundtrip:` 开头的结果 | 解析/格式化互相矛盾、溢出 |

自定义 target 只需要一个 `(Bytes) -> String`：

```moonbit
let target = @core.Target::new(
  "my.parser",
  [b"seed1", b"seed2"],
  fn(input) {
    // 不要 raise：失败也要变成字符串
    match try_parse(input) {
      Ok(_) => "ok"
      Err(e) => "err:" + e
    }
  },
)
```

## 设计要点

1. **反馈信号默认是"输出形状"而不是边覆盖**：`v:123` 与 `v:456` 同形状。零依赖、跨后端一致，任何 target 立刻可用；真实边覆盖的解析器（`cov/EdgeSet`）已实现，接线工作留作下一步。
2. **三种报告同源**：text / jsonl / html 都从同一个 `Session` 渲染，jsonl 逐字节可作为 diff 输入。
3. **finding 按形状去重**：数字折叠成 `#` 后再哈希，同一类 bug 只报一次。
4. **诚实的能力边界**：不开 `--isolate` 时 panic 会终止整轮 fuzz；开了才隔离，代价写在同一张表里。

## 崩溃隔离

panic 会带走整个进程——在没有隔离的时候，它带走的是 fuzzer 本身。`--isolate` 把"执行"挪进子进程：

```bash
moon run cli --target native -- run --target boom --seed 1 --max-execs 3000 --isolate

target   : boom  (oracle: same)
execs    : 3000 in 11497 ms  (260 exec/s)
corpus   : 15 entries, 14 buckets, 11 novel inputs
findings : 1
  [crash] boom  input=de63 (2B)
        worker exited with code -1073740791 on input 247 of 512
```

`boom` 是专门用来打崩自己的演示 target（遇到字节 `0xDE` 就 abort）。没有 `--isolate` 时它会直接杀掉 fuzzer——这正是它存在的意义。

工作方式：父进程保留语料与调度，把一个批次（默认 512 个输入）写成 hex 行交给子进程；子进程**每执行一条就写一行结果并 flush**。所以崩溃时"输出文件里有多少行"就是"第几个输入打死的"，不需要二分——二分是更慢地求同一个数字。

### 隔离模式怎么最小化

最小化要问几百次"这个更短的输入还坏吗"，而每次提问都要起进程。做法不是把提问变便宜，而是**把提问打包**：ddmin 的每一轮生成一整组候选，一个 worker 一次判完；中途崩了，父进程把尾巴重新提交。

代价可以开关，也能看见：

```bash
--isolate              # 3000 execs / 30.4s，finding 5 字节
--isolate --no-shrink  # 3000 execs / 1.1s，finding 956 字节
```

同一个种子、同一个 target，差 27 倍——差的是"每个 finding 二十轮 probe"。默认开，因为一条 5 字节的反例比一条 956 字节的反例有用得多；觉得慢就 `--no-shrink`。

### 并行：`--jobs N`

一轮 = N 个批次、N 个启动脚本、N 个 worker 同时跑，最后父进程统一收结果。没有共享内存协议：候选以文件出去，结果以文件回来；finding 去重仍在父进程按"形状"做。

启动成本是主要开销，所以 `--batch-size` 要跟着 `--jobs` 一起调大：

| 配置（20,000 次执行，`--no-shrink`） | 吞吐 |
|---|---|
| `--jobs 1`（串行） | 2,626 exec/s |
| `--jobs 4 --batch-size 512` | 3,888 exec/s |
| `--jobs 8 --batch-size 2048` | 7,380 exec/s |
| `--jobs 8 --batch-size 4096` | **8,336 exec/s** |

加速是亚线性的：每个 worker 启动约 60–200 ms，批次越小这笔固定成本占比越高。经验值 `--jobs 4 --batch-size 2048`。

## 性能（本机实测）

| target | 后端 | 吞吐 |
|---|---|---|
| varint（差分） | wasm-gc | 201,207 exec/s |
| varint（差分） | native (release) | 191,938 exec/s |
| varint（差分） | native (debug) | 40,225 exec/s |
| json | wasm-gc | 143,472 exec/s |
| csv | wasm-gc | 158,227 exec/s |
| varint | js (node) | 61,919 exec/s |

## 结构

```
core/      Rng / Bytes 工具 / Target / Oracle / Config / Stats / Finding
mutate/    havoc / 字典 / splice / 边界 / 按形状分派的结构化变异
corpus/    去重语料库 + 锦标赛选择
cov/       插桩记录器 + 形状反馈 + 覆盖率产物解析
shrink/    ddmin
targets/   18 个 target（17 个带 oracle，含标准库 @json / @bigint）
engine/    Session：循环、判定、语料、隔离、并行、cmin、cross
report/    text / jsonl / html / 回归测试 / 覆盖率报告
api/       对外入口（embedder 用）
cli/       参数解析
```

8,624 行实现 + 1,661 行测试，11 个包，145（native）/ 126（wasm-gc）/ 126（js）个测试全绿；`moon check --deny-warn` 三后端干净。

## 限制与下一步

1. **插桩是手动的**：没有自动插桩，写 target 的人要自己在分支上放 `@cov.hit(id)`。没放就静默回退到形状反馈——能跑，但弱。
2. **语料目录遇缺口截断**：`corpus-0007.hex` 缺失时只加载 1–6。好处是文件布局可以手工修（删尾巴、留前缀），代价是不能有洞。
3. **并行是亚线性的**：`--jobs` 要配 `--batch-size`，组合表见上；单 job 时仍是单核。
4. **隔离模式的崩溃用例不做 shrink**：缩它要对每个候选起进程；非崩溃用例可以。
5. **跨后端差分只比较目标输出**：不是内存布局或运行时行为的全面比对，且需要两侧都有构建。

## 文档

| 文档 | 内容 |
|---|---|
| [docs/使用指南.md](docs/使用指南.md) | 安装、五分钟上手、全部参数、接入自己的 target、FAQ |
| [CHANGELOG.md](CHANGELOG.md) | 每个发布版本改了什么、为什么 |
| [docs/upstream-issues.md](docs/upstream-issues.md) | 已提交给上游的 issue [moonbitlang/moon#2647](https://github.com/moonbitlang/moon/issues/2647)，以及一条"为什么没提"的记录 |
| [docs/验收.md](docs/验收.md) | 能力矩阵、实测数据、一键复现、已知限制 |
| [docs/开发历程.md](docs/开发历程.md) | 三条决策线、两次度量翻车、AI 使用方式、与开源工作的取舍 |
| [docs/case-varint.md](docs/case-varint.md) | 一个真 bug 的完整案例：现象 → 复现 → 根因 → 修复 → 回归 |
| [docs/架构.md](docs/架构.md) | 模块划分与每个关键决策的取舍 |
| [docs/findings.md](docs/findings.md) | 十个 target 的实测结果与性能表 |

## 跨后端差分（cross）

项目的第一条论点是"同一份代码在 wasm-gc / js / native 上行为应当一致，不一致就是 bug"。这条最该被自动检查，而 libFuzzer / AFL 天生做不到。

```bash
moon build --target wasm-gc                     # cross 需要另一后端的构建
moonsting cross --target utf8 --max-execs 120

target   : utf8
compared : 120 inputs against _build/wasm-gc/debug/build/cli/cli.wasm
mismatch : 0
```

做法：同一批输入（种子 + 变异），本进程跑一遍，另一后端用 `moonrun <wasm> exec --hex ...` 跑一遍，逐字节比输出。`exec` 子命令就是为它存在的。

实测（2026-11-24）：`utf8`、`protobuf`、`varint` 各 120 条输入，**0 处分歧**。灵敏度也验证过——第一次跑报的 3 处分歧来自一个**过期的 wasm 构建**（改了 `exec` 的空输入约定但没重编 wasm），修好构建后归零：说明它确实能抓到两个构建之间的行为差异。

## 语料最小化（cmin）

跑久了语料库只增不减：每个曾经触达新路径的输入都会留下，哪怕后来被别的输入覆盖。分享、review、入库都很痛苦。

`cmin` 做一次集合覆盖：保留**仍能覆盖全部 id 的最小子集**，同分时优先更短的输入。

```bash
moonsting run  --target protobuf --max-execs 20000 --corpus-dir .corpus
moonsting cmin --target protobuf --corpus-dir .corpus --out .corpus-min

corpus   : 148 inputs
coverage : 16 of 16 ids
kept     : 10 inputs (10 files written)
out      : .corpus-min
```

148 → 10，覆盖不变。没有插桩的 target 会退回"输出形状"，仍然保留每个不同形状的一个代表。文件读写需要 native 后端（wasm-gc 上会明确提示而不是静默失败）。

## 维护

一条命令回答"这个仓库现在还好吗"：

```bash
script/healthcheck.sh        # Linux / macOS / Git Bash
script/healthcheck.ps1       # Windows
```

它跑：三后端 `check --deny-warn` + 测试、六个"应当 0 finding"的 target 用 `--fail-on-finding` 跑一遍、两个标准库 target（`@json` 50k、`@bigint` 20k）——15 项，暖机后约 15 秒，任何一项失败就以非零码退出。

CI 里对应一个 `healthcheck` job，每周一 03:00 UTC 自动跑，也可以手动触发（`gh workflow run ci.yml`）。上游 `@json` / `@bigint` 一旦变化，这条流水线会先知道。

## 命名与发布

仓库名、模块名、CLI 名统一是 `moonsting`：

| 位置 | 值 |
|---|---|
| GitHub | `github.com/QYF795/moonsting` |
| `moon.mod` | `name = "QYF795/moonsting"`（已发布到 mooncakes） |
| CLI | `moonsting run ...` |

mooncakes 要求模块名形如 `<用户名>/<模块名>` 且与账号一致。发布前跑一次：

```bash
script/set-user.sh QYF795   # 已执行，改成别的账号时才需要再跑
```

它会把 `moon.mod` 改成 `<用户名>/moonsting`，并把全部 `moon.pkg` 里的导入前缀一起改掉（10 个文件，不要手改）。

## 与官方工具链的关系

不改 `moon`，不依赖任何未公开接口，零第三方依赖。目标是通过 `moonx` 分发，跑通后向 `moonbitlang/moon` 提 RFC，把本项目的协议与实现作为 `moon fuzz` 的参考实现。

## 许可证

Apache-2.0
