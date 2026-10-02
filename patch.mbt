///|
/// Apply a sequence of operations atomically to a copy of an Ion document.
/// Paths in each operation refer to the state after preceding operations.
pub fn apply(
  document : ArrayView[@model.IonValue],
  operations : ArrayView[PatchOp],
  limits? : PatchLimits,
) -> Array[@model.IonValue] raise PatchError {
  let limits = limits.unwrap_or(PatchLimits::default())
  check_limits(limits)
  if operations.length() > limits.max_operations {
    raise PatchError::Limit("operation count exceeds max_operations")
  }
  check_document(document, limits)
  let mut current = clone_values(document)
  for operation in operations {
    current = apply_one(current, operation, limits)
    check_document(current[:], limits)
  }
  current
}

///|
/// Return a patch that restores the original document after `operations`.
/// The input patch is first validated and applied; the inverse is a
/// deterministic diff from its result back to the original document.
pub fn invert(
  original : ArrayView[@model.IonValue],
  operations : ArrayView[PatchOp],
  limits? : PatchLimits,
) -> Array[PatchOp] raise PatchError {
  let limits = limits.unwrap_or(PatchLimits::default())
  let result = apply(original, operations, limits~)
  diff(result[:], original, limits~)
}

///|
fn apply_one(
  document : Array[@model.IonValue],
  operation : PatchOp,
  limits : PatchLimits,
) -> Array[@model.IonValue] raise PatchError {
  match operation {
    InsertRoot(index, value) => {
      check_document([value][:], limits)
      insert_root(document, index, value)
    }
    InsertElement(parent, index, value) => {
      check_path(parent, limits)
      check_document([value][:], limits)
      insert_at_path(document, parent, index, None, value)
    }
    InsertField(parent, index, symbol, value) => {
      check_path(parent, limits)
      check_document([value][:], limits)
      insert_at_path(document, parent, index, Some(symbol), value)
    }
    Remove(path) => {
      check_path(path, limits)
      edit_document(document, path, None)
    }
    Replace(path, value) => {
      check_path(path, limits)
      check_document([value][:], limits)
      edit_document(document, path, Some(clone_value(value)))
    }
  }
}

///|
fn check_position(
  index : Int,
  length : Int,
  allow_end : Bool,
) -> Unit raise PatchError {
  if index < 0 || index > length || (!allow_end && index == length) {
    raise PatchError::InvalidPath("index is outside the container")
  }
}

///|
fn insert_root(
  document : Array[@model.IonValue],
  index : Int,
  value : @model.IonValue,
) -> Array[@model.IonValue] raise PatchError {
  check_position(index, document.length(), true)
  let result : Array[@model.IonValue] = []
  for i in 0..<=document.length() {
    if i == index {
      result.push(clone_value(value))
    }
    if i < document.length() {
      result.push(document[i])
    }
  }
  result
}

///|
fn edit_document(
  document : Array[@model.IonValue],
  path : Path,
  replacement : @model.IonValue?,
) -> Array[@model.IonValue] raise PatchError {
  check_position(path.root, document.length(), false)
  let result : Array[@model.IonValue] = []
  for i in 0..<document.length() {
    if i == path.root {
      match edit_value(document[i], path.segments[:], 0, replacement) {
        Some(value) => result.push(value)
        None => ()
      }
    } else {
      result.push(document[i])
    }
  }
  result
}

///|
fn edit_value(
  value : @model.IonValue,
  segments : ArrayView[PathSegment],
  depth : Int,
  replacement : @model.IonValue?,
) -> @model.IonValue? raise PatchError {
  if depth == segments.length() {
    return replacement
  }
  match (value, segments[depth]) {
    (@model.IonValue::List(elements), Element(index)) =>
      Some(
        @model.IonValue::List(
          edit_elements(elements, segments, depth, index, replacement),
        ),
      )
    (@model.IonValue::Sexp(elements), Element(index)) =>
      Some(
        @model.IonValue::Sexp(
          edit_elements(elements, segments, depth, index, replacement),
        ),
      )
    (@model.IonValue::Struct(fields), Field(symbol, occurrence)) => {
      let index = field_position(fields, symbol, occurrence)
      let result : Array[(@model.IonSymbol, @model.IonValue)] = []
      for i in 0..<fields.length() {
        if i == index {
          match edit_value(fields[i].1, segments, depth + 1, replacement) {
            Some(updated) => result.push((fields[i].0, updated))
            None => ()
          }
        } else {
          result.push(fields[i])
        }
      }
      Some(@model.IonValue::Struct(result))
    }
    _ =>
      raise PatchError::WrongContainer("path segment does not match container")
  }
}

///|
fn edit_elements(
  elements : Array[@model.IonValue],
  segments : ArrayView[PathSegment],
  depth : Int,
  index : Int,
  replacement : @model.IonValue?,
) -> Array[@model.IonValue] raise PatchError {
  check_position(index, elements.length(), false)
  let result : Array[@model.IonValue] = []
  for i in 0..<elements.length() {
    if i == index {
      match edit_value(elements[i], segments, depth + 1, replacement) {
        Some(updated) => result.push(updated)
        None => ()
      }
    } else {
      result.push(elements[i])
    }
  }
  result
}

///|
fn insert_at_path(
  document : Array[@model.IonValue],
  parent : Path,
  index : Int,
  field : @model.IonSymbol?,
  value : @model.IonValue,
) -> Array[@model.IonValue] raise PatchError {
  check_position(parent.root, document.length(), false)
  let result : Array[@model.IonValue] = []
  for i in 0..<document.length() {
    if i == parent.root {
      result.push(
        insert_in_value(document[i], parent.segments[:], 0, index, field, value),
      )
    } else {
      result.push(document[i])
    }
  }
  result
}

///|
fn insert_in_value(
  container : @model.IonValue,
  segments : ArrayView[PathSegment],
  depth : Int,
  index : Int,
  field : @model.IonSymbol?,
  value : @model.IonValue,
) -> @model.IonValue raise PatchError {
  if depth == segments.length() {
    match (container, field) {
      (@model.IonValue::List(elements), None) =>
        return @model.IonValue::List(insert_element(elements, index, value))
      (@model.IonValue::Sexp(elements), None) =>
        return @model.IonValue::Sexp(insert_element(elements, index, value))
      (@model.IonValue::Struct(fields), Some(symbol)) => {
        check_position(index, fields.length(), true)
        let result : Array[(@model.IonSymbol, @model.IonValue)] = []
        for i in 0..<=fields.length() {
          if i == index {
            result.push((symbol, clone_value(value)))
          }
          if i < fields.length() {
            result.push(fields[i])
          }
        }
        return @model.IonValue::Struct(result)
      }
      _ =>
        raise PatchError::WrongContainer(
          "insertion type does not match container",
        )
    }
  }
  match (container, segments[depth]) {
    (@model.IonValue::List(elements), Element(child)) =>
      @model.IonValue::List(
        insert_in_elements(
          elements, segments, depth, child, index, field, value,
        ),
      )
    (@model.IonValue::Sexp(elements), Element(child)) =>
      @model.IonValue::Sexp(
        insert_in_elements(
          elements, segments, depth, child, index, field, value,
        ),
      )
    (@model.IonValue::Struct(fields), Field(symbol, occurrence)) => {
      let child = field_position(fields, symbol, occurrence)
      let result : Array[(@model.IonSymbol, @model.IonValue)] = []
      for i in 0..<fields.length() {
        if i == child {
          result.push(
            (
              fields[i].0,
              insert_in_value(
                fields[i].1,
                segments,
                depth + 1,
                index,
                field,
                value,
              ),
            ),
          )
        } else {
          result.push(fields[i])
        }
      }
      @model.IonValue::Struct(result)
    }
    _ =>
      raise PatchError::WrongContainer("path segment does not match container")
  }
}

///|
fn insert_in_elements(
  elements : Array[@model.IonValue],
  segments : ArrayView[PathSegment],
  depth : Int,
  child : Int,
  index : Int,
  field : @model.IonSymbol?,
  value : @model.IonValue,
) -> Array[@model.IonValue] raise PatchError {
  check_position(child, elements.length(), false)
  let result : Array[@model.IonValue] = []
  for i in 0..<elements.length() {
    if i == child {
      result.push(
        insert_in_value(elements[i], segments, depth + 1, index, field, value),
      )
    } else {
      result.push(elements[i])
    }
  }
  result
}

///|
fn insert_element(
  elements : Array[@model.IonValue],
  index : Int,
  value : @model.IonValue,
) -> Array[@model.IonValue] raise PatchError {
  check_position(index, elements.length(), true)
  let result : Array[@model.IonValue] = []
  for i in 0..<=elements.length() {
    if i == index {
      result.push(clone_value(value))
    }
    if i < elements.length() {
      result.push(elements[i])
    }
  }
  result
}
