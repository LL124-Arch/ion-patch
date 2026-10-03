///|
/// Build exact anchors in one pair of ordered slices. The matrix is created
/// only when its comparison cells fit the remaining alignment budget.
fn[T] align_exact(
  before : ArrayView[T],
  after : ArrayView[T],
  before_start : Int,
  before_end : Int,
  after_start : Int,
  after_end : Int,
  same : (T, T) -> Bool,
  budget : DiffBudget,
) -> Array[(Int, Int)]? {
  let n = before_end - before_start
  let m = after_end - after_start
  if n == 0 || m == 0 || budget.remaining == 0 {
    return None
  }
  if n > budget.remaining / m {
    return None
  }
  if n >= 2147483646 || m >= 2147483646 {
    return None
  }
  let stride = m + 1
  if n + 1 > 2147483647 / stride {
    return None
  }
  budget.remaining -= n * m
  let lengths = Array::make((n + 1) * stride, 0)
  let mut i = n - 1
  while i >= 0 {
    let mut j = m - 1
    while j >= 0 {
      let cell = i * stride + j
      if same(before[before_start + i], after[after_start + j]) {
        lengths[cell] = lengths[(i + 1) * stride + j + 1] + 1
      } else {
        let skip_before = lengths[(i + 1) * stride + j]
        let skip_after = lengths[cell + 1]
        lengths[cell] = if skip_before >= skip_after {
          skip_before
        } else {
          skip_after
        }
      }
      j -= 1
    }
    i -= 1
  }
  let anchors : Array[(Int, Int)] = []
  i = 0
  let mut j = 0
  while i < n && j < m {
    if same(before[before_start + i], after[after_start + j]) {
      anchors.push((before_start + i, after_start + j))
      i += 1
      j += 1
    } else if lengths[(i + 1) * stride + j] >= lengths[i * stride + j + 1] {
      i += 1
    } else {
      j += 1
    }
  }
  Some(anchors)
}

///|
fn equal_field(
  left : (@model.IonSymbol, @model.IonValue),
  right : (@model.IonSymbol, @model.IonValue),
) -> Bool {
  left.0 == right.0 && equal_value(left.1, right.1)
}
