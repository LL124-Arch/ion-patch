///|
/// Merge two patches made against the same base document. Independent edits
/// to stable positions are combined; incompatible edits raise Conflict.
/// The returned patch transforms `base` into the merged document.
pub fn merge(
  base : ArrayView[@model.IonValue],
  left : ArrayView[PatchOp],
  right : ArrayView[PatchOp],
  limits? : PatchLimits,
) -> Array[PatchOp] raise PatchError {
  let limits = limits.unwrap_or(PatchLimits::default())
  let left_result = apply(base, left, limits~)
  let right_result = apply(base, right, limits~)
  let combined = merge_sequence(base, left_result[:], right_result[:])
  diff(base, combined[:], limits~)
}

///|
fn merge_sequence(
  base : ArrayView[@model.IonValue],
  left : ArrayView[@model.IonValue],
  right : ArrayView[@model.IonValue],
) -> Array[@model.IonValue] raise PatchError {
  if equal_values(left, right) {
    return clone_values(left)
  }
  if equal_values(base, left) {
    return clone_values(right)
  }
  if equal_values(base, right) {
    return clone_values(left)
  }
  if base.length() != left.length() || base.length() != right.length() {
    if left.length() > base.length() && right.length() > base.length() {
      return merge_insertions(base, left, right, equal_value, clone_value)
    }
    raise PatchError::Conflict("concurrent changes alter sequence length")
  }
  let combined : Array[@model.IonValue] = []
  for i in 0..<base.length() {
    combined.push(merge_value(base[i], left[i], right[i]))
  }
  combined
}

///|
fn merge_value(
  base : @model.IonValue,
  left : @model.IonValue,
  right : @model.IonValue,
) -> @model.IonValue raise PatchError {
  if equal_value(left, right) {
    return clone_value(left)
  }
  if equal_value(base, left) {
    return clone_value(right)
  }
  if equal_value(base, right) {
    return clone_value(left)
  }
  match (base, left, right) {
    (
      @model.IonValue::List(base_items),
      @model.IonValue::List(left_items),
      @model.IonValue::List(right_items),
    ) =>
      @model.IonValue::List(
        merge_sequence(base_items[:], left_items[:], right_items[:]),
      )
    (
      @model.IonValue::Sexp(base_items),
      @model.IonValue::Sexp(left_items),
      @model.IonValue::Sexp(right_items),
    ) =>
      @model.IonValue::Sexp(
        merge_sequence(base_items[:], left_items[:], right_items[:]),
      )
    (
      @model.IonValue::Struct(base_fields),
      @model.IonValue::Struct(left_fields),
      @model.IonValue::Struct(right_fields),
    ) =>
      @model.IonValue::Struct(
        merge_fields(base_fields, left_fields, right_fields),
      )
    (
      @model.IonValue::Annotated(base_symbols, base_value),
      @model.IonValue::Annotated(left_symbols, left_value),
      @model.IonValue::Annotated(right_symbols, right_value),
    ) => {
      if base_symbols != left_symbols || base_symbols != right_symbols {
        raise PatchError::Conflict("concurrent changes alter annotations")
      }
      @model.IonValue::Annotated(
        base_symbols,
        merge_value(base_value, left_value, right_value),
      )
    }
    _ => raise PatchError::Conflict("concurrent changes overlap")
  }
}

///|
fn merge_fields(
  base : Array[(@model.IonSymbol, @model.IonValue)],
  left : Array[(@model.IonSymbol, @model.IonValue)],
  right : Array[(@model.IonSymbol, @model.IonValue)],
) -> Array[(@model.IonSymbol, @model.IonValue)] raise PatchError {
  if base.length() != left.length() || base.length() != right.length() {
    if left.length() > base.length() && right.length() > base.length() {
      return merge_insertions(
        base[:],
        left[:],
        right[:],
        equal_field,
        clone_field,
      )
    }
    raise PatchError::Conflict("concurrent changes alter struct fields")
  }
  let combined : Array[(@model.IonSymbol, @model.IonValue)] = []
  for i in 0..<base.length() {
    if base[i].0 != left[i].0 || base[i].0 != right[i].0 {
      raise PatchError::Conflict("concurrent changes alter struct fields")
    }
    combined.push((base[i].0, merge_value(base[i].1, left[i].1, right[i].1)))
  }
  combined
}

///|
fn clone_field(
  field : (@model.IonSymbol, @model.IonValue),
) -> (@model.IonSymbol, @model.IonValue) {
  (field.0, clone_value(field.1))
}

///|
/// Merge insertion-only branches by their uniquely located base elements.
fn[T] merge_insertions(
  base : ArrayView[T],
  left : ArrayView[T],
  right : ArrayView[T],
  same : (T, T) -> Bool,
  copy : (T) -> T,
) -> Array[T] raise PatchError {
  let left_anchors = unique_embedding(base, left, same)
  let right_anchors = unique_embedding(base, right, same)
  let combined : Array[T] = []
  let mut left_start = 0
  let mut right_start = 0
  for gap in 0..<=base.length() {
    let left_end = if gap == base.length() {
      left.length()
    } else {
      left_anchors[gap]
    }
    let right_end = if gap == base.length() {
      right.length()
    } else {
      right_anchors[gap]
    }
    let left_count = left_end - left_start
    let right_count = right_end - right_start
    if left_count > 0 && right_count > 0 {
      if left_count != right_count {
        raise PatchError::Conflict("concurrent insertions share a position")
      }
      for offset in 0..<left_count {
        if !same(left[left_start + offset], right[right_start + offset]) {
          raise PatchError::Conflict("concurrent insertions share a position")
        }
      }
    }
    if left_count > 0 {
      for index in left_start..<left_end {
        combined.push(copy(left[index]))
      }
    } else {
      for index in right_start..<right_end {
        combined.push(copy(right[index]))
      }
    }
    if gap < base.length() {
      combined.push(copy(base[gap]))
      left_start = left_end + 1
      right_start = right_end + 1
    }
  }
  combined
}

///|
/// The earliest and latest subsequence matches must agree at every element.
fn[T] unique_embedding(
  base : ArrayView[T],
  branch : ArrayView[T],
  same : (T, T) -> Bool,
) -> Array[Int] raise PatchError {
  let earliest : Array[Int] = []
  let mut cursor = 0
  for item in base {
    while cursor < branch.length() && !same(item, branch[cursor]) {
      cursor += 1
    }
    if cursor == branch.length() {
      raise PatchError::Conflict("branch changes or removes a base element")
    }
    earliest.push(cursor)
    cursor += 1
  }
  let latest = Array::make(base.length(), 0)
  cursor = branch.length() - 1
  let mut i = base.length() - 1
  while i >= 0 {
    while cursor >= 0 && !same(base[i], branch[cursor]) {
      cursor -= 1
    }
    if cursor < 0 {
      raise PatchError::Conflict("branch changes or removes a base element")
    }
    latest[i] = cursor
    cursor -= 1
    i -= 1
  }
  for index in 0..<base.length() {
    if earliest[index] != latest[index] {
      raise PatchError::Conflict("base element position is ambiguous")
    }
  }
  earliest
}
