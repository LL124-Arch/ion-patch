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
  let shared = if before.length() < after.length() {
    before.length()
  } else {
    after.length()
  }
  let mut i = before.length() - 1
  while i >= shared {
    push_op(operations, Remove(Path::root(i)), limits)
    i -= 1
  }
  i = after.length() - 1
  while i >= shared {
    push_op(operations, InsertRoot(shared, clone_value(after[i])), limits)
    i -= 1
  }
  i = shared - 1
  while i >= 0 {
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
  let shared = if before.length() < after.length() {
    before.length()
  } else {
    after.length()
  }
  let mut i = before.length() - 1
  while i >= shared {
    let path = parent.element(i)
    check_path(path, limits)
    push_op(operations, Remove(path), limits)
    i -= 1
  }
  i = after.length() - 1
  while i >= shared {
    push_op(
      operations,
      InsertElement(parent, shared, clone_value(after[i])),
      limits,
    )
    i -= 1
  }
  i = shared - 1
  while i >= 0 {
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
  let shared = if before.length() < after.length() {
    before.length()
  } else {
    after.length()
  }
  let mut i = before.length() - 1
  while i >= shared {
    let path = parent.field(before[i].0, occurrence_at(before, i))
    check_path(path, limits)
    push_op(operations, Remove(path), limits)
    i -= 1
  }
  i = after.length() - 1
  while i >= shared {
    push_op(
      operations,
      InsertField(parent, shared, after[i].0, clone_value(after[i].1)),
      limits,
    )
    i -= 1
  }
  i = shared - 1
  while i >= 0 {
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
