# 案例：32 位 varint 解码器的静默截断

> 这是 moonsting 抓到的第一个真 bug，也是 README 里唯一一条"不崩、不报错、只是算错"的证据。
> 整个案例可以用四条命令走完：发现 → 复现 → 最小化 → 固化成回归测试。

## 1. 现象

```
$ moonsting run --target varint --seed 1 --max-execs 50000

target   : varint  (oracle: diff(varint.fast,varint.ref))
execs    : 50000 in 1244 ms  (40192 exec/s)
findings : 3
  [mismatch] varint  input=ffff80ff0f (5B)
        expected v:4292886527 got v:-2080769
```

（这是当前版本的真实输出。更早的一版变异器先抓到的是 `92ffffff0f`——同一个 bug 的另一个实例。下面用它做手算，因为字节更整齐；两个输入都是 5 字节、都在第 5 个字节溢出。）

`varint` 这个 target 里有一对实现：`varint_ref` 解码到 `Int64`，`varint_fast` 解码到 32 位 `Int`。差分 oracle 要求两者给出**同一个字符串**，这条 finding 说的是：同一个 5 字节输入，一个算出 `4294967186`，另一个算出 `-110`。

两者都没崩、都没报错。这就是最贵的那类 bug。

## 2. 复现

```
$ moonsting replay --target varint --hex 92ffffff0f
bytes   : 5
output  : v:-110
verdict : expected v:4294967186 got v:-110
```

`replay` 不依赖 session 状态：它重新构造 target、跑这一条输入、再问一次 oracle。**能复现的 finding 才算 finding**，这是设计上刻意保留的入口。

## 3. 最小化

```
$ moonsting minimize --target varint --hex 92ffffff0f00010203
from : 9B 92ffffff0f00010203
to   : 5B 92ffffff0f
```

后面 4 个字节是变异时带进来的噪声。ddmin 把"仍然触发同一个差分"的最小前缀留了下来。

## 4. 根因

LEB128 的规则是每字节 7 位有效、最高位表示"还有后续"。`92 ff ff ff 0f` 手算：

| 字节 | 载荷 | 左移 | 贡献 |
|---|---|---|---|
| `0x92` | `0x12` = 18 | 0 | 18 |
| `0xff` | `0x7f` = 127 | 7 | 16,256 |
| `0xff` | 127 | 14 | 2,080,768 |
| `0xff` | 127 | 21 | 266,338,304 |
| `0x0f` | 15 | 28 | 4,026,531,840 |

合计 `4,294,967,186 = 2³² + 114`。这个值**放不进 32 位有符号整数**。

`varint_ref` 用 `Int64` 累加，得到正确值。`varint_fast` 的累加变量是 `Int`（32 位），最后一字节左移 28 位时结果已经越过 `2³¹`，溢出成负数；再和前面的项按位或，得到 `-110`。

**关键在于它不会报错**：MoonBit 的整数溢出是回绕，不是陷阱。所以一个解码器可以在所有手写用例上通过、在真实数据里悄悄算错。

## 5. 为什么手写用例发现不了

要触发它，需要**恰好 5 个字节且第 5 个字节的载荷非零**。正常写测试的人会写：

- `\x00`（0）
- `\x7f`（127）
- `\x80\x01`（128）
- `\xff\x01`（255）

这些都在 32 位内，两个实现一致。要想到"第 5 个字节"，得先想到"值可能超过 2³²"——而这正是 fuzzer 不需要想到的事：它只需要变异出那个输入。

工具侧还有两个细节让它更容易被看见：

1. **差分 oracle 只要求"两个实现一致"**，不需要先写规格。写第二遍实现，比写一遍规格便宜得多，也具体得多。
2. **finding 按"形状"去重**：`expected v:4294967186 got v:-110` 与 `expected v:12348032000 got v:-1879031820` 是同一个 bug（都是 32 位截断），折叠成一条。否则报告里会出现十几条同源噪声。

## 6. 修复与回归

修复有三种，选哪个是作者的决定，工具只负责给出反例：

```moonbit
// 方案 A：累加用 Int64（与 ref 一致）
let mut value : Int64 = 0

// 方案 B：保留 32 位，但拒绝超宽编码
if shift >= 32 && b != 0 { return "err:overflow" }

// 方案 C：两者都做——先按 64 位解，再检查是否落在目标类型范围内
```

`moonsting` 能自动把反例变成一条可以粘进仓库的测试：

```bash
$ moonsting run --target varint --seed 1 --max-execs 20000 --emit-test
```

（下面是这次运行的真实输出，抓到的是同类反例 `ffff80ff0f`，格式与前者完全相同）

```
///|
test "regress: varint #5" {
  // found by moonsting at exec 382
  // expected v:4292886527 got v:-2080769
  let input = @core.parse_hex("ffff80ff0f")
  // TODO: replace with the failing call
  let output = varint(input)
  assert_eq(output, "<expected>")
}
```

生成的测试是**脚手架**，不是成品：它不知道你的函数签名，所以留了 `TODO`。但它把三件最容易丢的东西固定下来了——输入字节、期望值、以及"这是哪次执行发现的"。把它改成

```moonbit
test "regress: varint 32-bit truncation" {
  let input = @core.parse_hex("92ffffff0f")
  assert_eq(varint_fast(input), varint_ref(input))
}
```

就得到了一个永远不会再退化的用例。

## 7. 放进 CI

```bash
moonsting run --target varint --max-execs 20000 --fail-on-finding
```

有 finding 就以非零码退出（会打印 MoonBit 运行时栈，正常）。把它挂在 PR 上，这条 bug 就再也不会回来——而且新增的同类 bug 会被同一条门禁拦住。

## 8. 这个案例说明了什么

- **差分 oracle 的价值**：不需要规格，只需要第二遍实现。代价是写两遍，收益是"结果错"这类 bug 从"几乎发现不了"变成"几分钟内发现"。
- **最小化不是锦上添花**：9 字节的反例没人愿意读，5 字节的反例一眼能看出是 LEB128 的最后一字节。
- **可复现是底线**：`replay` 独立重算，`--json` 输出逐字节可 diff，同 seed 三个后端结果一致——这些都只为了一件事：让"我们发现了一个 bug"这句话可被验证。
