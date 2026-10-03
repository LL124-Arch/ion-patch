///|
/// Produce a deterministic structural patch from `before` to `after`.
/// The patch is exact for the Ion value model, but is not guaranteed minimal.
pub fn diff(
  before : ArrayView[@model.IonValue],
  after : ArrayView[@model.IonValue],
  limits? : PatchLimits,
) -> Array[PatchOp] raise PatchError {
  let limits = limits.unwrap_or(PatchLimits::default())
  check_limits(limits)
  check_document(before, limits)
  check_document(after, limits)
  let candidate = try structural_diff(before, after, limits) catch {
    PatchError::Limit(_) => None
    error => raise error
  } noraise {
    operations => Some(operations)
  }
  let operations = match candidate {
    Some(operations) => operations
    None => return replacement_patch(before, after, limits)
  }
  let trial = try apply(before, operations[:], limits~) catch {
    PatchError::Limit(_) => None
    error => raise error
  } noraise {
    result => Some(result)
  }
  match trial {
    Some(result) => {
      if !equal_values(result[:], after) {
        raise PatchError::InvalidPath(
          "generated patch does not reproduce target",
        )
      }
      operations
    }
    None => replacement_patch(before, after, limits)
  }
}

///|
fn structural_diff(
  before : ArrayView[@model.IonValue],
  after : ArrayView[@model.IonValue],
  limits : PatchLimits,
) -> Array[PatchOp] raise PatchError {
  let operations : Array[PatchOp] = []
  let (prefix, suffix) = common_value_edges(before, after)
  let before_end = before.length() - suffix
  let after_end = after.length() - suffix
  let middle_end = if before_end < after_end { before_end } else { after_end }
  let mut i = before_end - 1
  while i >= middle_end {
    push_op(operations, Remove(Path::root(i)), limits)
    i -= 1
  }
  i = after_end - 1
  while i >= middle_end {
    push_op(operations, InsertRoot(middle_end, clone_value(after[i])), limits)
    i -= 1
  }
  i = middle_end - 1
  while i >= prefix {
    diff_value(before[i], after[i], Path::root(i), operations, limits)
    i -= 1
  }
  operations
}

///|
/// A valid but less granular fallback when an intermediate result would exceed
/// a value limit even though both endpoint documents satisfy that limit.
fn replacement_patch(
  before : ArrayView[@model.IonValue],
  after : ArrayView[@model.IonValue],
  limits : PatchLimits,
) -> Array[PatchOp] raise PatchError {
  let operations : Array[PatchOp] = []
  let mut i = before.length() - 1
  while i >= 0 {
    push_op(operations, Remove(Path::root(i)), limits)
    i -= 1
  }
  i = after.length() - 1
  while i >= 0 {
    push_op(operations, InsertRoot(0, clone_value(after[i])), limits)
    i -= 1
  }
  operations
}

///|
fn push_op(
  operations : Array[PatchOp],
  operation : PatchOp,
  limits : PatchLimits,
) -> Unit raise PatchError {
  if operations.length() >= limits.max_operations {
    raise PatchError::Limit("operation count exceeds max_operations")
  }
  operations.push(operation)
}

///|
fn diff_value(
  before : @model.IonValue,
  after : @model.IonValue,
  path : Path,
  operations : Array[PatchOp],
  limits : PatchLimits,
) -> Unit raise PatchError {
  if equal_value(before, after) {
    return
  }
  check_path(path, limits)
  if path.segments.length() == limits.max_path_depth {
    push_op(operations, Replace(path, clone_value(after)), limits)
    return
  }
  match (before, after) {
    (
      @model.IonValue::Annotated(left_symbols, left_value),
      @model.IonValue::Annotated(right_symbols, right_value),
    ) if left_symbols == right_symbols =>
      diff_value(
        left_value,
        right_value,
        path.annotated_value(),
        operations,
        limits,
      )
    (@model.IonValue::List(left), @model.IonValue::List(right)) =>
      diff_elements(left, right, path, operations, limits)
    (@model.IonValue::Sexp(left), @model.IonValue::Sexp(right)) =>
      diff_elements(left, right, path, operations, limits)
    (@model.IonValue::Struct(left), @model.IonValue::Struct(right)) =>
      diff_fields(left, right, path, operations, limits)
    _ => push_op(operations, Replace(path, clone_value(after)), limits)
  }
}

///|
fn diff_elements(
  before : Array[@model.IonValue],
  after : Array[@model.IonValue],
  parent : Path,
  operations : Array[PatchOp],
  limits : PatchLimits,
) -> Unit raise PatchError {
  let (prefix, suffix) = common_value_edges(before[:], after[:])
  let before_end = before.length() - suffix
  let after_end = after.length() - suffix
  let middle_end = if before_end < after_end { before_end } else { after_end }
  let mut i = before_end - 1
  while i >= middle_end {
    let path = parent.element(i)
    check_path(path, limits)
    push_op(operations, Remove(path), limits)
    i -= 1
  }
  i = after_end - 1
  while i >= middle_end {
    push_op(
      operations,
      InsertElement(parent, middle_end, clone_value(after[i])),
      limits,
    )
    i -= 1
  }
  i = middle_end - 1
  while i >= prefix {
    diff_value(before[i], after[i], parent.element(i), operations, limits)
    i -= 1
  }
}

///|
fn diff_fields(
  before : Array[(@model.IonSymbol, @model.IonValue)],
  after : Array[(@model.IonSymbol, @model.IonValue)],
  parent : Path,
  operations : Array[PatchOp],
  limits : PatchLimits,
) -> Unit raise PatchError {
  let (prefix, suffix) = common_field_edges(before[:], after[:])
  let before_end = before.length() - suffix
  let after_end = after.length() - suffix
  let middle_end = if before_end < after_end { before_end } else { after_end }
  let mut i = before_end - 1
  while i >= middle_end {
    let path = parent.field(before[i].0, occurrence_at(before, i))
    check_path(path, limits)
    push_op(operations, Remove(path), limits)
    i -= 1
  }
  i = after_end - 1
  while i >= middle_end {
    push_op(
      operations,
      InsertField(parent, middle_end, after[i].0, clone_value(after[i].1)),
      limits,
    )
    i -= 1
  }
  i = middle_end - 1
  while i >= prefix {
    let path = parent.field(before[i].0, occurrence_at(before, i))
    check_path(path, limits)
    if before[i].0 == after[i].0 {
      diff_value(before[i].1, after[i].1, path, operations, limits)
    } else {
      push_op(operations, Remove(path), limits)
      push_op(
        operations,
        InsertField(parent, i, after[i].0, clone_value(after[i].1)),
        limits,
      )
    }
    i -= 1
  }
}

///|
fn common_value_edges(
  before : ArrayView[@model.IonValue],
  after : ArrayView[@model.IonValue],
) -> (Int, Int) {
  let mut prefix = 0
  while prefix < before.length() &&
        prefix < after.length() &&
        equal_value(before[prefix], after[prefix]) {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < before.length() - prefix &&
        suffix < after.length() - prefix &&
        equal_value(
          before[before.length() - suffix - 1],
          after[after.length() - suffix - 1],
        ) {
    suffix += 1
  }
  (prefix, suffix)
}

///|
fn common_field_edges(
  before : ArrayView[(@model.IonSymbol, @model.IonValue)],
  after : ArrayView[(@model.IonSymbol, @model.IonValue)],
) -> (Int, Int) {
  let mut prefix = 0
  while prefix < before.length() &&
        prefix < after.length() &&
        before[prefix].0 == after[prefix].0 &&
        equal_value(before[prefix].1, after[prefix].1) {
    prefix += 1
  }
  let mut suffix = 0
  while suffix < before.length() - prefix &&
        suffix < after.length() - prefix &&
        before[before.length() - suffix - 1].0 ==
        after[after.length() - suffix - 1].0 &&
        equal_value(
          before[before.length() - suffix - 1].1,
          after[after.length() - suffix - 1].1,
        ) {
    suffix += 1
  }
  (prefix, suffix)
}
