# ion-patch

`ion-patch` 是基于 [amazon-ion-moonbit-core](https://github.com/LL124-Arch/amazon-ion-moonbit-core) 值模型的 MoonBit 内存补丁库。它对整个 Ion 文档（有序的顶层值序列）生成结构差异、原子应用补丁，并生成恢复原文档的逆补丁。

## 使用

在 `moon.pkg` 中导入两个包：

```moonbit
import {
  "LL124-Arch/amazon-ion-moonbit-core" @ion,
  "LL124-Arch/ion-patch" @patch,
}
```

```moonbit
test "Ion patch round trip" {
  let before = @ion.parse_text("{a: 1, a: 2}")
  let after = @ion.parse_text("{a: 1, a: 3, b: true}")
  let operations = @patch.diff(before[:], after[:])
  let updated = @patch.apply(before[:], operations[:])
  let reverse = @patch.invert(before[:], operations[:])
  let restored = @patch.apply(updated[:], reverse[:])
  assert_eq(@patch.equal_values(updated[:], after[:]), true)
  assert_eq(@patch.equal_values(restored[:], before[:]), true)
}
```

补丁调用在会抛错的函数或测试中使用；失败时返回 `PatchError`。

## 路径与操作

`Path::root(index)` 定位第 `index` 个顶层值。`.element(index)` 定位列表或 S 表达式元素；`.field(symbol, occurrence)` 定位结构体中完整符号相同的第 `occurrence` 个字段。所有索引从零开始。字段符号同时包含文本和 SID，因此同名重复字段与未知 SID 可以准确定位。

`PatchOp` 提供 `InsertRoot`、`InsertElement`、`InsertField`、`Remove` 和 `Replace`。插入位置可以等于当前容器长度。操作按数组顺序执行，每个路径都针对前一项操作完成后的文档。路径不穿透注解包装；需要修改时可用 `Replace` 替换整个注解值。

差异比较保留类型、注解顺序、结构体字段顺序与重复字段，以及符号文本和 SID。浮点数按位比较，区分正负零和不同的 NaN 位模式。`diff` 的结果确定，但不保证操作数最少。

`apply` 不修改输入文档，返回独立的值容器；任何操作失败都不会返回部分结果。`invert` 先应用原补丁，再生成从结果回到原文档的差异。`PatchLimits` 限制操作数、路径深度和 Ion 值规模，默认采用上游值限制；不允许的路径、容器类型或规模分别返回明确的 `PatchError`。

首版只提供内存 API，不定义补丁文件或网络格式。

## 验证

```sh
moon fmt --check
moon check --deny-warn --target all
moon build --target all
moon test --deny-warn --target all
```
