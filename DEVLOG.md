# DEVLOG · moonsting

> 这份日志是**验收材料**,不是给自己看的草稿。官方 4×25% 里有 25% 是「可解释性:开发历程 + AI 工具使用方式 + 对开源工作的借鉴取舍」。
> 规则:每天一条,当天写完;AI 出的错必须留痕(错在哪、怎么发现、怎么改);不要事后补写——补写的痕迹很明显。

## 记录格式

```
### D<n> · <日期> · <一句话主题>

**今日目标**
**实际完成**
**AI 产出与错误**(表格:生成了什么 / 错在哪 / 怎么发现 / 怎么改)
**踩到的坑**(现象 → 根因 → 结论)
**关键决策**
**明天**
```

---

### D0 · 11/16 · 立项与申报

**今日目标**
- 提交申报;建仓库;把"批次 + 二分归因 + 跨后端差分"三个决策先写死

**实际完成**
- 申报书 v0.1;仓库骨架

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 初版架构图 | 把覆盖率当成"逐输入可得" | 读 `moon coverage` 文档发现产物是进程退出时落盘 | 改为批次粒度 + 二分归因 |

**关键决策**
- 不做 fork-per-input(Windows);不做编译器插桩(不稳);分发走 `moonx`(不改 moon)

---

### D1 · 11/17 · 十个包跑通，48 个测试全绿

**今日目标**
- 把"能跑的最小闭环"落地：变异 → 执行 → 判定 → 收语料 → 最小化 → 报告

**实际完成**
- 10 个包 / 2,632 行实现 + 464 行测试：`core` `mutate` `corpus` `cov` `shrink` `targets` `engine` `report` `api` `cli`
- 三个内置 target：`json.lite`（metamorphic）、`csv.lite`（smoke）、`varint`（差分对）
- 实测在 `wasm-gc` 200k exec/s、`js` 62k exec/s
- 同 seed 下两个后端的 JSONL **逐字节相同**（含 finding 的 exec 序号）
- `moon check --deny-warn` 干净、`moon test` 48/48

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 跨包构造枚举 `@core.Oracle::Same` | 报 "Cannot create values of the read-only type" | 编译器错误码 4036 | 查 core 源码的 `pub(all) enum` 用法；`pub enum` 默认只读，构造需显式开放 |
| `fn Session::loop(...)` | `loop` 是关键字，整段解析失败并连带十几个假错误 | 错误里出现 "unexpected token `loop`" | 改名 `drive`；同理 `let test = ...` 改 `generated` |
| `if x & 0x80 == 0` | `&` 与 `==` 优先级歧义，被当成 `x & (0x80 == 0)` | 错误提示 "ambiguous_precedence" | 加括号 |
| 用 PowerShell `Set-Content` 改源码 | 写入 UTF-8 BOM，`moon.pkg` 直接词法错误；`Get-Content/Set-Content` 往返把中文注释变成 `鈥?` | 报错位置在文件 0..3 字节；grep 非 ASCII 发现 4 行乱码 | 源码一律用编辑器/写入工具，绝不走 shell 文本管道；BOM 用 .NET 无 BOM 编码批量清掉 |
| JSON 的 metamorphic oracle | 比较完整输出字符串，错误信息里带位置（`@0`→`@1`），于是报出 9 条假阳性 | 读 finding 详情发现全是"位置变了" | 只比较"接受/拒绝"；假阳性归零，这个教训写进 `docs/findings.md` |
| CLI 参数解析 | 假定 `argv[1]` 是子命令 | `--target js` 下 node 把脚本路径放在 `argv[1]`，直接报 "unknown command: cli.js" | 改成按名字定位子命令（`is_command` 扫描），两个后端都正确 |

**踩到的坑**
- **本机没有 C 编译器**：`moon` 的 native target 要求 MSVC 或 clang-cl，`moon add` 也因沙箱无法写 `~/.moon/registry`。→ 结论：v0.1 只能在 wasm-gc / js 上验证；native 专属代码（进程池）不在本轮范围内，但**必须在文档里写清楚**，不能留假接口。
- **`_test.mbt` 放在可执行包里会被弃用**，而 `test-import` 语法在这个版本里没找到可用写法。→ 结论：加了一个 `api` 包（对外入口，本来也该有），把端到端测试放进去；`report` 因此不需要为了测试去依赖 `targets`。
- **桶反馈会饱和**：json 用例 10 万次执行只积累 254 个桶。→ 结论：这是形状反馈的固有上限，不是 bug；真解是把 `cov/EdgeSet` 接到引擎上。

**关键决策**
- 反馈信号选"输出形状"而不是等编译器插桩：零依赖、跨后端一致、立刻可用；代价写进文档。
- 执行器是进程内直调，不假装有隔离；panic 会终止整轮，这一点写进 README 的"状态"表。
- 差分 oracle 用"同后端双实现"而不是"跨后端"：一次进程只能一个后端；跨后端改由 `--json` + `diff` 承担，并已用逐字节一致验证前提成立。
- ddmin 探测次数上限 2000：宁可少缩一点，也不能让一个慢 oracle 把 fuzz 卡死。

**明天**
- 接覆盖率：在 `moon test --enable-coverage` 下驱动 fuzz，用 `EdgeSet` 增量替换形状反馈
- `--corpus-dir` 持久化（需要先确认 wasm-gc 下有没有可用的文件 API）
- 给 `varint` 的真实 bug 提一个 issue/PR 形态的说明，作为"工具 → 真实收益"的证据链

---

### D2 · 11/17 晚 · 定名 moonsting，补上"能续跑"

**今日目标**
- 项目改名 `moonsting` 并在新仓库里落地；补一个不用文件系统也能续跑语料的能力

**实际完成**
- 全量改名：`moonsting` 目录 + `moon.mod` + 10 个 `moon.pkg` 的导入前缀 + 全部文档/CLI 文案；48 个测试仍全绿
- `--dump-corpus`（把最终语料按 hex 行打到 stdout）与 `--seed-input HEX`（可重复，喂回上一轮的语料）
- `core.trim_end`：报告字符串自带换行，`println` 又加一个，输出里出现过空行
- `script/set-user.sh`：发布前把模块名一次性改成 `<用户名>/moonsting`
- `LICENSE` / `.gitignore` / git 初始化 + 首个提交

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 直接改 `engine/session.mbt` | `edit` 报 old_string 不存在 | `moon fmt` 已经改过格式（`Int`→`Int32`），而且上一轮把 `loop` 改名成了 `drive` | 先 `read` 当前文件再改；结论：**格式化之后的文件不能凭记忆编辑** |
| 改名后只改了代码 | help 文案里还写着 `fuzz run`，用户看到的命令和真实命令对不上 | 跑 `list` 看输出 | 改名必须同时扫文档和 CLI 字符串，不只是 import |
| `println(summary)` | 输出里多一个空行（报告字符串自己以 `\n` 结尾） | 肉眼看 dump 输出 | 加 `trim_end`，只在打印处裁剪 |
| 用 PowerShell 的相对路径调 `[IO.File]` | 报路径不存在 | 异常里显示的是 workspace 根而不是 `moonsting/` | .NET API 不认 PowerShell 的 location，必须用 `$PWD` 拼绝对路径（这个坑第二轮已经踩过一次） |

**关键决策**
- 模块名先写裸 `moonsting`：本地开发、导入、测试都够用；发布前用脚本改成 `<用户名>/moonsting`。理由是现在还不知道 mooncakes 用户名，猜一个会让 10 个文件再改一次。
- 语料持久化用"导出 hex 行 + 命令行喂回"，而不是等文件 API：`> corpus.txt` 与 `--seed-input` 现在就可用，等文件 API 到位后两者可以并存。

**明天**
- 覆盖率接线（`EdgeSet` 接进 engine，替换 `Buckets`）
- 进程池（需要 native 编译环境；或确认 `js` 的 `child_process` 路线）

