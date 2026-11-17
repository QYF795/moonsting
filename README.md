# moonsting

**给 MoonBit 补上缺失的那一层：喂进坏字节，拿回一个最小反例、一份报告和一条能粘贴进仓库的回归测试。**

零依赖，纯 MoonBit，同一个 seed 在 `wasm-gc` / `js` / `native` 三个后端产出逐字节相同的结果。

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

第一个反例在第 **12** 次执行被发现，最小化到 5 字节。详细分析见 [docs/findings.md](docs/findings.md)。

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
| 编译器覆盖率产物（`cov/EdgeSet`）接进引擎 | ❌ 见架构文档：普通二进制不落盘 |
| 进程隔离（`--isolate`，native）：批次 worker + 崩溃输入定位 | ✅ |
| 隔离模式下的批量最小化（一轮 ddmin = 一次 worker，`--no-shrink` 可关） | ✅ |
| 语料持久化（`--corpus-dir`） | ❌ 需要文件系统 API |
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

# 列目标
moon run cli --target wasm-gc -- list
```

参数：`--target` `--seed` `--max-execs` `--time 5s` `--max-input` `--max-findings` `--seed-input`（可重复）`--json` `--html` `--emit-test` `--dump-corpus` `--isolate` `--batch-size` `--no-shrink` `--fail-on-finding` `--quiet`。

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

## 四种 oracle

| target | oracle | 判据 | 能发现什么 |
|---|---|---|---|
| `json` | `json.ws-invariance` | 前后空白不得改变"接受/拒绝" | 解析器的边界处理错误 |
| `csv` | `same` | 什么都不判 | 崩溃与 hang（smoke 阶段用） |
| `varint` | `diff(varint.fast, varint.ref)` | 两个实现必须给出同一个值 | **不崩、不报错、结果错** |
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
mutate/    Dictionary + 变异算子
corpus/    去重语料库 + 锦标赛选择
cov/       Buckets（形状反馈）+ EdgeSet（覆盖率产物解析）
shrink/    ddmin
targets/   json.lite / csv.lite / varint 差分对
engine/    Session：循环、判定、语料、finding
report/    text / jsonl / html / 回归测试
api/       对外入口（embedder 用）
cli/       参数解析
```

2,632 行实现 + 464 行测试，10 个包，48 个测试全绿；`moon check --deny-warn` 干净。

## 限制与下一步

1. **并行 `--jobs`**：现在每批串行起一个子进程，单核；还没做同时起 N 个。
2. **覆盖率接线**（P1）：在 `moon test --enable-coverage` 下驱动 fuzz，把 `EdgeSet` 的增量作为语料准入，替换形状反馈。
3. **语料持久化**（P1）：`--corpus-dir`，让长跑可以中断续跑。
4. **覆盖率接线**（P1）：`cov/EdgeSet` 已实现，还没接进 engine 替换形状反馈。
5. **更多 target**（P2）：把生态里测试薄的解析器（ARFF / protobuf / parquet 编码）接成 case。

## 命名与发布

仓库名、模块名、CLI 名统一是 `moonsting`：

| 位置 | 值 |
|---|---|
| GitHub | `github.com/<你的用户名>/moonsting` |
| `moon.mod` | `name = "moonsting"`（本地开发够用） |
| CLI | `moonsting run ...` |

mooncakes 要求模块名形如 `<用户名>/<模块名>` 且与账号一致。发布前跑一次：

```bash
script/set-user.sh <你的 mooncakes 用户名>
```

它会把 `moon.mod` 改成 `<用户名>/moonsting`，并把全部 `moon.pkg` 里的导入前缀一起改掉（10 个文件，不要手改）。

## 与官方工具链的关系

不改 `moon`，不依赖任何未公开接口，零第三方依赖。目标是通过 `moonx` 分发，跑通后向 `moonbitlang/moon` 提 RFC，把本项目的协议与实现作为 `moon fuzz` 的参考实现。

## 许可证

Apache-2.0
