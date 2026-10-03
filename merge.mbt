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
