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
- 追加：`decimal` 自检 target（第四种 oracle 风格：body 自己给诊断，oracle 只拒绝 `roundtrip:`）、`--fail-on-finding`（有 finding 就非零退出，给 CI 用）；测试 48 → 53

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

---

### D3 · 11/17 下午 · 装上 MSVC，三个后端跑出同一份结果

**今日目标**
- 装 MSVC Build Tools，解锁 `--target native`；验证后把文档里的"未验证"改写

**实际完成**
- `winget install Microsoft.VisualStudio.2022.BuildTools --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"`，后台跑约 27 分钟、3.6 GB，落地 `cl.exe 14.44.35207`
- `moon build --target native` 通过；`moon test --target native` 53/53 通过
- 三后端（wasm-gc / js / native）同 seed、同执行数：JSONL 逐字节相同，语料 52 entries / 51 buckets / 46 novel 完全一致
- 性能：native release 191,938 exec/s、native debug 40,225、wasm-gc 201,207、js 61,919
- `script/install-msvc.ps1` 固化了安装命令（可重跑、可交给别人）

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 用 `Invoke-WebRequest` 探 `aka.ms` 判断能否下载 | 连接被重置，于是先得出"机器没有外网"的结论 | 之后 winget 能正常 search/install，说明只是 PowerShell 的 .NET 栈被拦 | 区分"shell 没有出口"与"机器没有网络"：换一个客户端（winget/WinINet）再测一次 |
| 直接跑 `winget install` | 退出码 -1978335231，看起来像 winget 坏了 | 放宽文件沙箱后 `winget --version` 立刻正常 | 先单测工具本身可用性，再判断是环境问题还是工具问题 |
| 装完后没验证就说"应该可以了" | 「应该」不是证据 | `moon build --target native` 一次通过才写进文档 | 文档里的每个 ✅ 后面都要有一条能重跑的命令 |

**关键决策**
- 用 winget + VCTools 工作负载，而不是单独装 clang-cl：moon 在 Windows 上要的是 MSVC 工具链 + Windows SDK，缺一个都链接不了。
- 装完先跑三后端一致性，再更新文档：native 只是"能编译"不算数，跑出同样的 3 条 finding 才算。

**明天**
- 进程池：native 已就绪，`--jobs N` + 崩溃后二分定位可以动工了

---

### D4 · 11/17 晚 · 进程隔离落地，二分被证明是多余的

**今日目标**
- 让 panic 不再带走整轮 fuzz，并且能指出"是第几个输入打死的"

**实际完成**
- 新包 `proc`（native 专用，其他后端 stub）：`fopen/fwrite/fgetc/fflush/system` 的 libc 绑定 + 流式写句柄
- `engine/isolated.mbt`：父进程保留语料与调度，子进程执行批次（默认 512）
- `worker` 子命令：读 hex 批次，**每执行一条写一行并 flush**
- `--isolate` / `--batch-size`；`targets/boom.mbt`（遇 `0xDE` 就 abort）专门验证崩溃路径
- 实测：`boom` 在 3000 次执行里报出 `[crash] de63 (2B)`，`input 247 of 512`，fuzz 继续跑完
- 测试 53 → 61（native）/ 53（wasm-gc），`--deny-warn` 干净

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 直接 `system("exe 参数...")` | 子进程根本没起来（退出码 1），父进程把每个批次都当成"第 0 条崩溃"，20k 次执行跑了 3 分钟 | 加 `MOONSTING_DEBUG` 打印命令，手工复现 | 先定位是"命令没执行"而不是"target 崩了"：空结果 ≠ 崩溃，必须先确认 spawn 成功 |
| 用 argv[0] 当可执行文件路径 | `self_exe(args)` 收到的是子命令之后的参数，永远返回空 → 悄悄退回进程内执行，隔离形同虚设 | 3000 次执行只用了 90ms，快得不像起了进程 | 把 exe 从 `main` 一路传给 `cmd_run`；教训：**降级路径必须留痕**，否则功能没生效也看不出来 |
| 用绝对路径传 exe 和临时文件 | 路径里有 `文档`（中文），`system()` 经 `cmd.exe` 的 ANSI 代码页解码后找不到文件 | 单独测试 ASCII 路径 vs Unicode 路径，退出码 0 vs 1 | 传相对 cwd 的路径（`_build/...` 全是 ASCII）；临时文件也改到 cwd 下 |
| 给每个参数都加引号 | `cmd.exe` 的 `/C` 引号剥离规则把参数切错，命令依然失败 | 四种引号组合逐一试 | 只在含空格时加引号（`@proc.arg`） |
| 批次里有空输入 | 空行在 hex 批次格式里消失，回读少一行 → 父进程判定"第 N 条崩溃"，其实是格式问题 | finding 说 `input 480 of 512`，但退出码是 0 | 组批次时跳过空输入；**退出码 0 + 行数不足**这个组合本身就是可疑信号 |

**踩到的坑**
- `LNK1104: 无法打开 cli.exe`：上一轮挂起的 cli 进程还占着文件。结论：跑 native 迭代前先确认没有残留进程。
- `moon check` 不重建 exe；改完代码直接跑旧 exe 会得到旧行为。结论：调试打印前先 `moon build`。

**关键决策**
- **不做二分**：逐行 flush 之后，"结果文件有几行"就是崩溃索引。二分是更慢地求同一个数字，省掉它同时省掉一整块代码。
- 临时文件放 cwd 而不是 `%TEMP%`：沙箱/受限令牌下绝对路径写入可能失败，而父进程与子进程唯一 guaranteed 共享的就是 cwd。
- 隔离模式不做 shrink：最小化要对每个候选只跑一条输入，那就必须每次都起进程，成本压不住。先诚实标注，不假装有。

**明天**
- `--jobs N`（Windows `start /b`、POSIX `&`），finding 跨进程按形状合并
- 隔离模式的最小化：把 ddmin 的每一批候选塞进一个 worker，而不是一次一条

---

### D5 · 11/17 深夜 · 隔离模式的最小化：把"提问"打包

**今日目标**
- 补上隔离模式唯一的功能缺口：finding 能缩到最小

**实际完成**
- `shrink/ddmin_batched`：谓词接受"一整轮候选"，返回每个候选的布尔值（一轮 = 一次 spawn）
- `engine/isolated_shrink`：`probe` 把一轮候选分类成 0/1/2（接受/违例/崩溃），崩溃后从 k+1 重提交；`shrunk` 用它做 ddmin，`--no-shrink` 可关
- 效果：同样 3000 次执行，finding 从 **956 字节**变成 **5 字节**；耗时从 1.1s 变成 30.4s
- 测试 61 → 65（native）/ 53 → 57（wasm-gc）

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 直接用现有的 `ddmin` + 每条候选起一个进程 | 估算一下就知道没戏：几百次 probe × 200ms | 先算账再动手 | 改成"一轮一次 spawn"的 `ddmin_batched` |
| 第一版 `probe` 把候选原样塞进批次 | 空候选在 hex 格式里变成空行，回读少一行 → 被当成"崩在第 k 条" → 每次重提交，一轮 32 次无效 spawn，整体卡死两分钟 | 跑 3000 execs 超过 120s，且 `--no-shrink` 只要 1.1s | 空候选不进批次，直接记 0（不 interesting）；spawn 次数上限兜底 |
| 用"是不是坏"当最小化谓词 | 会把一条 mismatch 缩到某个不相干的 crash 上——更小，但是另一个 bug | 写 probe 时意识到状态需要分类 | 状态分 0/1/2，只认与原始 finding 同类的状态 |
| `guard` 当变量名 | `guard` 是关键字，整段解析失败 | 编译错误 | 改名 `spawns` |

**关键决策**
- 默认开 shrink：一条 5 字节的反例比一条 956 字节的有用得多；慢 27 倍是显式的、可以关的代价（`--no-shrink`）。
- 只对前 8 条 finding 做最小化：后面的收益递减，不如把时间花在探索上。
- 隔离模式的最小化只认"同类状态"：这是正确性问题，不是性能问题。

**明天**
- `--jobs N`：同时起 N 个 worker（Windows `start /b`、POSIX `&`），结果按形状合并
- `cov/EdgeSet` 接进 engine，替换形状反馈

---

### D6 · 11/17 深夜 · `--jobs N`：并行不共享内存，只共享文件

**今日目标**
- 一次跑 N 个 worker，把隔离模式的吞吐拉回来

**实际完成**
- `proc/script.mbt`：为每个 job 生成启动脚本（跑 worker、无条件写 done 文件、把退出码写进去），`launch_many` 用**一条** shell 命令把 N 个脚本一起 start
- `engine/parallel.mbt`：一轮 = N 个批次 + N 个脚本 + 轮询 done 文件 + 统一 absorb；轮内共享一个 exec 预算，避免 4 个 worker 各跑满一批把 `--max-execs` 冲爆
- CLI `--jobs N`；推荐值写进 README（`--jobs 4 --batch-size 2048`）
- 实测（20k 次执行、--no-shrink）：串行 2,626 / jobs4 3,888 / jobs8+batch2048 7,380 / jobs8+batch4096 **8,336 exec/s**
- 测试 65 → 67（native）

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 启动脚本里写 `echo %ERRORLEVEL%> done` | cmd.exe 把 `0>` 解析成"重定向 handle 0"，**什么都不写**，于是每个 job 永远不"完成" | `--jobs 4` 卡满 120 秒；用一个只会写 done 的脚本单独测，三种启动形式全部"成功但没文件" | `>` 前加空格：`echo %ERRORLEVEL% > done`。这是 cmd 的重定向语法，不是我们的 bug |
| 每个 job 单独 `system("start /b ...")` | 每次 ~57ms，4 个 job 光启动就 228ms，把并行收益吃光 | 测了 `start /b` 的返回耗时（57ms vs 脚本 1s，确实是后台），再对比 jobs=1/4 的吞吐 | 拼成一条 `start /b ... & start /b ...`，只付一次 cmd 启动 |
| 对 `spawn_path` 的结果又调了一次 `shell_path` | 路径变成 `.\ .\_build\...`，子进程找不到 | 起不来且没有任何输出 | 只在一处做路径规范化 |
| 每批都用 `max_execs - execs` 算预算 | 4 个 job 各自看到同样的剩余额度，20k 跑成 41k | 输出里 execs 超过上限 | 轮内用一个共享 budget 递减 |

**关键决策**
- 不共享内存：语料与调度留在父进程，候选/结果走文件。代价是 IO，收益是没有锁、没有跨进程内存布局约定（MoonBit 表达不了后者）。
- done 文件而非等待进程：`start /b` 没有句柄，`system()` 阻塞。启动脚本无条件写 done（含崩溃），父进程只认文件出现。
- 批次大小必须跟着 jobs 走：固定成本不变，批越大占比越低。所以 README 给的是"jobs + batch"的组合，而不是单个 jobs 数字。

**明天**
- `cov/EdgeSet` 接进 engine，替换形状反馈（README 里最后一个功能 ❌）
- `--corpus-dir` 持久化：现在只能靠 `--dump-corpus` + `--seed-input` 手工续跑

---

### D7 · 11/17 深夜 · 覆盖率反馈：编译器产物用不了，那就手写插桩

**今日目标**
- 把 `cov/EdgeSet` 接进引擎，让反馈从"输出形状"变成"真的走没走过这条路"

**实际完成**
- 先验证前提：`moon build --target native --enable-coverage` 跑一次，仓库里**没有任何** `moonbit_coverage*` 文件——编译器的覆盖率是测试驱动的，普通二进制不落盘。这条把原计划（读产物）直接否掉
- 改成手写插桩：`cov/recorder.mbt`（全局 hits/seen + `hit`/`reset`/`commit`/`fingerprint`），示例 target `varint`（13 个 id）、`csv`（10 个状态位）已插桩；`json`、`decimal` 故意不插桩，作为回退对照组
- 引擎判据只有一句 `@cov.observed() > 0`：插桩过就用路径指纹，没插桩就回退形状。没有开关、没有配置项
- worker 用指纹当结果签名，所以隔离模式也自动吃到插桩收益（协议没改）
- 效果：`csv` 语料 53 → 94（独立签名 51 → 92），`json` 保持 237 / 231；测试 67 → 72

**AI 产出与错误**
| AI 生成了什么 | 错在哪 | 怎么发现的 | 最终怎么改 |
|---|---|---|---|
| 计划"读 `moon test --enable-coverage` 的产物" | 前提就不成立：普通二进制不留产物；而且不跑 `moon test` 我们也拿不到那批文件 | 实测：带 `--enable-coverage` 构建、跑一次、全仓搜 `moonbit_coverage*`，零命中 | 换成手写插桩；文档里把"编译器产物"从能力表里降级为"服务于 moon test 场景" |
| 新颖性用 `commit()`（"出现过新 id"） | 13 个 id 很快全被覆盖，语料停在 8 条、novelty 2 | 跑 varint 一眼看到语料不再增长 | 改用**路径指纹**（命中集合的哈希），novelty 本质上是"新路径" |
| 指纹实现成滚动混合（`acc ^= h; acc ^= acc>>13`） | 顺序敏感：`{1,2}` 与 `{2,1}` 指纹不同 | 单元测试直接撞出来（两个值不等） | 逐 id 哈希做 XOR（可交换），末尾再做一次雪崩 |
| 全局插桩状态让测试互相污染 | 一个 test 的 hits 漏到下一个 | 第一次跑 recorder 测试就出现期望外计数 | 每个测试开头 `@cov.reset()` / `clear_seen()`，并在注释里写明这是全局状态 |

**关键决策**
- **顺序无关**的指纹：路径是有序的，但顺序噪声（同一个分支集的不同遍历次序）会产生几乎无限的"新路径"，语料会被撑爆。牺牲一点精度换可用的信号，这是 fuzzer 里常见的取舍。
- **不强制用户插桩**：没有 `@cov.hit` 的 target 照常工作，只是反馈弱一些。工具的门槛必须是"能跑"，不是"先改你的代码"。
- 只插桩两个 target、留两个不插桩：两种模式都得在演示集里跑一遍，否则回退路径迟早烂掉。

**明天**
- `--corpus-dir` 持久化（现在只能 `--dump-corpus` 手工续跑）
- 插桩覆盖率报告：把"哪些 id 一次都没命中"打出来，反过来指导 target 的插桩点





