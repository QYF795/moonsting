# moonsting

**给 MoonBit 补上缺失的那一层：喂进坏字节，拿回一个最小反例、一份报告和一条能粘贴进仓库的回归测试。**

零依赖，纯 MoonBit，同时跑在 `wasm-gc` 和 `js` 上；native 因为本机没有 C 编译器尚未验证。

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
| 同 seed 跨后端逐字节一致（wasm-gc vs js） | ✅ 已验证 |
| 覆盖率产物解析（`cov/EdgeSet` + 测试） | ✅ 已实现，未接线到引擎 |
| 进程隔离 / 批次 worker / 崩溃二分定位 | ❌ 需要 native 或进程 API |
| 语料持久化（`--corpus-dir`） | ❌ 需要文件系统 API |
| 并行 `--jobs` | ❌ |

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

参数：`--target` `--seed` `--max-execs` `--time 5s` `--max-input` `--max-findings` `--seed-input`（可重复）`--json` `--html` `--emit-test` `--dump-corpus` `--quiet`。

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
4. **诚实的能力边界**：没有进程隔离就不假装有——panic 会终止整轮 fuzz，这一点写在 [docs/架构.md](docs/架构.md) 里，而不是留一个看起来能用的假接口。

## 性能（本机实测）

| target | 后端 | 吞吐 |
|---|---|---|
| varint（差分） | wasm-gc | 201,207 exec/s |
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

1. **进程隔离**（P0）：批次 worker + 崩溃后二分定位。需要 native 编译（装 MSVC Build Tools）或 `js` 的 `child_process`，二者都还没接。
2. **覆盖率接线**（P1）：在 `moon test --enable-coverage` 下驱动 fuzz，把 `EdgeSet` 的增量作为语料准入，替换形状反馈。
3. **语料持久化**（P1）：`--corpus-dir`，让长跑可以中断续跑。
4. **并行**（P2）：`--jobs N`，多进程各自跑不同 seed，finding 按形状合并。
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
