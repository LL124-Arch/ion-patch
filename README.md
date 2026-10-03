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

`Path::root(index)` 定位第 `index` 个顶层值。`.element(index)` 定位列表或 S 表达式元素；`.field(symbol, occurrence)` 定位结构体中完整符号相同的第 `occurrence` 个字段；`.annotated_value()` 进入一层注解包装下的值，可连续使用以进入嵌套注解。所有索引从零开始。字段符号同时包含文本和 SID，因此同名重复字段与未知 SID 可以准确定位。

`PatchOp` 提供 `InsertRoot`、`InsertElement`、`InsertField`、`Remove` 和 `Replace`。插入位置可以等于当前容器长度。操作按数组顺序执行，每个路径都针对前一项操作完成后的文档。注解包装下的结构可编辑，注解顺序保持不变；不能单独删除注解的负载值，但可替换该值或删除整个注解值。

差异比较保留类型、注解顺序、结构体字段顺序与重复字段，以及符号文本和 SID。注解序列相同时，`diff` 会继续比较包装下的值；注解序列改变时，替换整个注解值。浮点数按位比较，区分正负零和不同的 NaN 位模式。`diff` 会保留有序容器相同的前后段，并对其余片段做精确值对齐，因此多处独立插入或删除可以分别生成操作。结果确定，但不保证操作数最少。

`apply` 不修改输入文档，返回独立的值容器；任何操作失败都不会返回部分结果。`invert` 按顺序执行原补丁，从每一步执行前的文档读取旧值，再以相反顺序生成逆操作。逆补丁与原补丁操作数相同，不依赖 `diff` 的对齐预算。插入位置的子路径若超出路径深度限制，逆操作会替换原容器。`PatchLimits` 限制操作数、路径深度、Ion 值规模和差异对齐工作量。`max_alignment_cells` 默认为 1,000,000，计入一次 `diff` 中所有对齐矩阵的比较单元；预算不足时改用位置比较。其他值规模限制默认采用上游配置；不允许的路径、容器类型或规模分别返回明确的 `PatchError`。

首版只提供内存 API，不定义补丁文件或网络格式。

## 验证

```sh
moon fmt --check
moon check --deny-warn --target all
moon build --target all
moon test --deny-warn --target all
```
