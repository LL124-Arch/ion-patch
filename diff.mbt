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
  let budget = { remaining: limits.max_alignment_cells, }
  let candidate = try structural_diff(before, after, limits, budget) catch {
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
priv struct DiffBudget {
  mut remaining : Int
}

///|
fn structural_diff(
  before : ArrayView[@model.IonValue],
  after : ArrayView[@model.IonValue],
  limits : PatchLimits,
  budget : DiffBudget,
) -> Array[PatchOp] raise PatchError {
  let operations : Array[PatchOp] = []
  let (prefix, suffix) = common_value_edges(before, after)
  let before_end = before.length() - suffix
  let after_end = after.length() - suffix
  let anchors = align_exact(
    before, after, prefix, before_end, prefix, after_end, equal_value, budget,
  )
  let mut before_right = before_end
  let mut after_right = after_end
  match anchors {
    Some(matches) => {
      let mut i = matches.length() - 1
      while i >= 0 {
        let (before_anchor, after_anchor) = matches[i]
        diff_root_gap(
          before,
          after,
          before_anchor + 1,
          before_right,
          after_anchor + 1,
          after_right,
          operations,
          limits,
          budget,
        )
        before_right = before_anchor
        after_right = after_anchor
        i -= 1
      }
    }
    None => ()
  }
  diff_root_gap(
    before, after, prefix, before_right, prefix, after_right, operations, limits,
    budget,
  )
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
  budget : DiffBudget,
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
        budget,
      )
    (@model.IonValue::List(left), @model.IonValue::List(right)) =>
      diff_elements(left, right, path, operations, limits, budget)
    (@model.IonValue::Sexp(left), @model.IonValue::Sexp(right)) =>
      diff_elements(left, right, path, operations, limits, budget)
    (@model.IonValue::Struct(left), @model.IonValue::Struct(right)) =>
      diff_fields(left, right, path, operations, limits, budget)
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
  budget : DiffBudget,
) -> Unit raise PatchError {
  let (prefix, suffix) = common_value_edges(before[:], after[:])
  let before_end = before.length() - suffix
  let after_end = after.length() - suffix
  let anchors = align_exact(
    before[:],
    after[:],
    prefix,
    before_end,
    prefix,
    after_end,
    equal_value,
    budget,
  )
  let mut before_right = before_end
  let mut after_right = after_end
  match anchors {
    Some(matches) => {
      let mut i = matches.length() - 1
      while i >= 0 {
        let (before_anchor, after_anchor) = matches[i]
        diff_element_gap(
          before,
          after,
          before_anchor + 1,
          before_right,
          after_anchor + 1,
          after_right,
          parent,
          operations,
          limits,
          budget,
        )
        before_right = before_anchor
        after_right = after_anchor
        i -= 1
      }
    }
    None => ()
  }
  diff_element_gap(
    before, after, prefix, before_right, prefix, after_right, parent, operations,
    limits, budget,
  )
}

///|
fn diff_fields(
  before : Array[(@model.IonSymbol, @model.IonValue)],
  after : Array[(@model.IonSymbol, @model.IonValue)],
  parent : Path,
  operations : Array[PatchOp],
  limits : PatchLimits,
  budget : DiffBudget,
) -> Unit raise PatchError {
  let (prefix, suffix) = common_field_edges(before[:], after[:])
  let before_end = before.length() - suffix
  let after_end = after.length() - suffix
  let anchors = align_exact(
    before[:],
    after[:],
    prefix,
    before_end,
    prefix,
    after_end,
    equal_field,
    budget,
  )
  let mut before_right = before_end
  let mut after_right = after_end
  match anchors {
    Some(matches) => {
      let mut i = matches.length() - 1
      while i >= 0 {
        let (before_anchor, after_anchor) = matches[i]
        diff_field_gap(
          before,
          after,
          before_anchor + 1,
          before_right,
          after_anchor + 1,
          after_right,
          parent,
          operations,
          limits,
          budget,
        )
        before_right = before_anchor
        after_right = after_anchor
        i -= 1
      }
    }
    None => ()
  }
  diff_field_gap(
    before, after, prefix, before_right, prefix, after_right, parent, operations,
    limits, budget,
  )
}

///|
fn diff_root_gap(
  before : ArrayView[@model.IonValue],
  after : ArrayView[@model.IonValue],
  before_start : Int,
  before_end : Int,
  after_start : Int,
  after_end : Int,
  operations : Array[PatchOp],
  limits : PatchLimits,
  budget : DiffBudget,
) -> Unit raise PatchError {
  let before_count = before_end - before_start
  let after_count = after_end - after_start
  let shared = if before_count < after_count {
    before_count
  } else {
    after_count
  }
  let insertion_index = before_start + shared
  let mut i = before_end - 1
  while i >= insertion_index {
    push_op(operations, Remove(Path::root(i)), limits)
    i -= 1
  }
  i = after_end - 1
  while i >= after_start + shared {
    push_op(
      operations,
      InsertRoot(insertion_index, clone_value(after[i])),
      limits,
    )
    i -= 1
  }
  i = shared - 1
  while i >= 0 {
    diff_value(
      before[before_start + i],
      after[after_start + i],
      Path::root(before_start + i),
      operations,
      limits,
      budget,
    )
    i -= 1
  }
}

///|
fn diff_element_gap(
  before : Array[@model.IonValue],
  after : Array[@model.IonValue],
  before_start : Int,
  before_end : Int,
  after_start : Int,
  after_end : Int,
  parent : Path,
  operations : Array[PatchOp],
  limits : PatchLimits,
  budget : DiffBudget,
) -> Unit raise PatchError {
  let before_count = before_end - before_start
  let after_count = after_end - after_start
  let shared = if before_count < after_count {
    before_count
  } else {
    after_count
  }
  let insertion_index = before_start + shared
  let mut i = before_end - 1
  while i >= insertion_index {
    let path = parent.element(i)
    check_path(path, limits)
    push_op(operations, Remove(path), limits)
    i -= 1
  }
  i = after_end - 1
  while i >= after_start + shared {
    push_op(
      operations,
      InsertElement(parent, insertion_index, clone_value(after[i])),
      limits,
    )
    i -= 1
  }
  i = shared - 1
  while i >= 0 {
    diff_value(
      before[before_start + i],
      after[after_start + i],
      parent.element(before_start + i),
      operations,
      limits,
      budget,
    )
    i -= 1
  }
}

///|
fn diff_field_gap(
  before : Array[(@model.IonSymbol, @model.IonValue)],
  after : Array[(@model.IonSymbol, @model.IonValue)],
  before_start : Int,
  before_end : Int,
  after_start : Int,
  after_end : Int,
  parent : Path,
  operations : Array[PatchOp],
  limits : PatchLimits,
  budget : DiffBudget,
) -> Unit raise PatchError {
  let before_count = before_end - before_start
  let after_count = after_end - after_start
  let shared = if before_count < after_count {
    before_count
  } else {
    after_count
  }
  let insertion_index = before_start + shared
  let mut i = before_end - 1
  while i >= insertion_index {
    let path = parent.field(before[i].0, occurrence_at(before, i))
    check_path(path, limits)
    push_op(operations, Remove(path), limits)
    i -= 1
  }
  i = after_end - 1
  while i >= after_start + shared {
    push_op(
      operations,
      InsertField(parent, insertion_index, after[i].0, clone_value(after[i].1)),
      limits,
    )
    i -= 1
  }
  i = shared - 1
  while i >= 0 {
    let index = before_start + i
    let target = after_start + i
    let path = parent.field(before[index].0, occurrence_at(before, index))
    check_path(path, limits)
    if before[index].0 == after[target].0 {
      diff_value(
        before[index].1,
        after[target].1,
        path,
        operations,
        limits,
        budget,
      )
    } else {
      push_op(operations, Remove(path), limits)
      push_op(
        operations,
        InsertField(
          parent,
          index,
          after[target].0,
          clone_value(after[target].1),
        ),
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
