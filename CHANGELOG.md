# 变更日志

按发布的版本倒序。每条都对应 `git log` 里的提交，写的是"为什么"，细节在 [DEVLOG.md](DEVLOG.md)。

## 0.6.0 — 2026-11-24

- **`cmin` 子命令**：语料最小化。按"覆盖的 id 集合"做贪心集合覆盖，保留仍能触达全部 id 的最小子集，同分优先短输入。实测 148 条 → 10 条，覆盖 16/16 不变。无插桩的 target 退回输出形状。
- **`--corpus-dir` 在非 native 后端会明确提示**：文件读写依赖 `proc`，此前在 wasm-gc 上静默什么都不写。
- 新增 `@cov.current_ids`：`seen_ids` 是累积集合，集合覆盖需要的是"本次执行"的 id，两者混用会导致 cmin 读到上一次的残留。
- `docs/upstream-issues.md`：给上游的 issue 草稿（覆盖率产物只由 `moon test` 产出），以及"bigint 那条为什么没提"的记录。

## 0.5.2 — 2026-11-22

- **去掉换基数往返检查**：标准库把 `parse_bigint` 的标签从 `base~` 改成 `radix=`，同一份源码无法同时编译过新旧两版。取舍是不钉死编译器版本，代价是少一条检查（十进制往返仍在）。

## 0.5.1 — 2026-11-22

- **`bigint` target 改用 `@string.parse_bigint`**：旧的 `BigInt::from_string` 已弃用，且对非法输入直接 abort；新 API 带 `raise`，`+5`、`0x1f` 这类输入从"杀掉进程"变成 `err:parse`。
- **更正一个错误结论**：此前记录"标准库在 ~1,024 位会 panic"。实际是测试脚手架的问题——LCG 在 Int32 上溢出，产生带负号的畸形字符串，`parse_bigint` 正确地 raise，`.unwrap()` 把它变成了 panic。生成器已修，结论已改。
- `findings.md` 重排：多次追加后出现了重复的 `## 5`、`## 6`，现在是连续的 1–11，两个标准库 target 合并为 §10。

## 0.5.0 — 2026-11-22

- **新增 `bigint` target**：标准库大整数解析的自洽性检查（parse → print → parse），输入上限 256 位。
- 记录两条关于标准库的观察，见 `docs/findings.md` §10.7。

## 0.4.0 — 2026-11-20

- **TLV 记录级变异**：解析 `[type][len][payload]` 记录，做复制/删除/长度 ±1/截断/类型归零/类型互换/追加终止符；二进制分派改成 protobuf → TLV → 长度 poke 的链式回退。
- **修 protobuf target 的 tag 截断**：六字节 tag 在范围检查之前被窄化成 Int32，截断后通过校验并重新序列化成不同字节（`9080a4da80253d`）。新变异器上线即抓到。
- `docs/演示脚本.md`：90 秒五幕演示稿。

## 0.3.0 — 2026-11-20

- **第一个标准库 target `stdjson`**：`@json.valid` 与 `@json.parse` 必须一致，`stringify` 的输出必须能再解析。故意不插桩，靠输出形状判新颖性。
- **完整 Apache-2.0 许可证**：此前是 15 行占位文件，版权人还是 `<your name>`。
- **`docs/使用指南.md`**：安装、五分钟上手、21 个参数、接入自己的 target、FAQ。
- **CI 自吃狗粮**：五个"应当 0 finding"的 target 用 `--fail-on-finding` 跑。

## 0.2.0 — 2026-11-19

- **protobuf 字段级变异**：复制/删除字段、非最小 varint、损坏 payload、翻转 wire type、改字段号。
- **插桩报告语义**：`@cov.declare_ids` 声明每个 target 真正用到的 id，报告从"空洞"变成"N of M declared branches never taken"。
- **三个新 target**：`fixed`（定宽表格）、`ini`（注释不变性）、`props`（properties 转义往返）。

## 0.1.0 — 2026-11-18

首个发布版本，包含：

- 引擎：变异（havoc / 结构化 / 字典 / splice / 边界）、语料库、四种 oracle、ddmin 最小化、finding 去重、text/jsonl/html 报告、回归测试生成。
- 执行：进程内、进程隔离（崩溃定位）、`--jobs` 并行、语料持久化（编号文件）。
- 反馈：手写插桩 + 输出形状回退、`--cov-report`。
- 12 个 target：`json` `csv` `varint` `decimal` `base64` `tlv` `utf8` `urlenc` `protobuf` `rle` `csvstrict` `arff`，外加崩溃演示 `boom`。
- 真实 finding：`varint` 的 32 位截断（3 条）、`decimal` 的溢出（1 条）。
