///|
/// Build one inverse against the state immediately before an applied edit.
fn inverse_one(
  before : Array[@model.IonValue],
  after : Array[@model.IonValue],
  operation : PatchOp,
  limits : PatchLimits,
) -> PatchOp raise PatchError {
  match operation {
    InsertRoot(index, _) => Remove(Path::root(index))
    InsertElement(parent, index, _) =>
      if parent.segments.length() < limits.max_path_depth {
        Remove(parent.element(index))
      } else {
        Replace(parent, clone_value(value_at_path(before, parent)))
      }
    InsertField(parent, index, symbol, _) =>
      if parent.segments.length() < limits.max_path_depth {
        match value_at_path(after, parent) {
          @model.IonValue::Struct(fields) =>
            Remove(parent.field(symbol, occurrence_at(fields, index)))
          _ =>
            raise PatchError::WrongContainer("expected struct after insertion")
        }
      } else {
        Replace(parent, clone_value(value_at_path(before, parent)))
      }
    Remove(path) => {
      let old = clone_value(value_at_path(before, path))
      if path.segments.length() == 0 {
        InsertRoot(path.root, old)
      } else {
        let parent = parent_path(path)
        match path.segments[path.segments.length() - 1] {
          Element(index) => InsertElement(parent, index, old)
          Field(symbol, occurrence) =>
            match value_at_path(before, parent) {
              @model.IonValue::Struct(fields) =>
                InsertField(
                  parent,
                  field_position(fields, symbol, occurrence),
                  symbol,
                  old,
                )
              _ => raise PatchError::WrongContainer("expected struct field")
            }
          AnnotatedValue =>
            raise PatchError::InvalidPath("annotated value cannot be removed")
        }
      }
    }
    Replace(path, _) => Replace(path, clone_value(value_at_path(before, path)))
  }
}

///|
fn parent_path(path : Path) -> Path {
  let segments : Array[PathSegment] = []
  for i in 0..<(path.segments.length() - 1) {
    segments.push(path.segments[i])
  }
  { root: path.root, segments, }
}

///|
fn value_at_path(
  document : Array[@model.IonValue],
  path : Path,
) -> @model.IonValue raise PatchError {
  check_position(path.root, document.length(), false)
  value_at_segments(document[path.root], path.segments[:], 0)
}

///|
fn value_at_segments(
  value : @model.IonValue,
  segments : ArrayView[PathSegment],
  depth : Int,
) -> @model.IonValue raise PatchError {
  if depth == segments.length() {
    return value
  }
  match (value, segments[depth]) {
    (@model.IonValue::Annotated(_, nested), AnnotatedValue) =>
      value_at_segments(nested, segments, depth + 1)
    (@model.IonValue::List(elements), Element(index))
    | (@model.IonValue::Sexp(elements), Element(index)) => {
      check_position(index, elements.length(), false)
      value_at_segments(elements[index], segments, depth + 1)
    }
    (@model.IonValue::Struct(fields), Field(symbol, occurrence)) => {
      let index = field_position(fields, symbol, occurrence)
      value_at_segments(fields[index].1, segments, depth + 1)
    }
    _ =>
      raise PatchError::WrongContainer("path segment does not match container")
  }
}
