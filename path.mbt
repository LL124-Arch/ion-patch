///|
/// A zero-based location inside one Ion document value.
///
/// Field occurrences count only fields with the same complete Ion symbol
/// (both text and SID), so duplicate fields remain individually addressable.
pub(all) enum PathSegment {
  Element(Int)
  Field(@model.IonSymbol, Int)
  AnnotatedValue
}

///|
/// A path starts at a zero-based top-level document value.
pub(all) struct Path {
  root : Int
  segments : Array[PathSegment]
}

///|
pub fn Path::root(index : Int) -> Path {
  { root: index, segments: [], }
}

///|
pub fn Path::element(self : Path, index : Int) -> Path {
  let segments = copy_segments(self.segments[:])
  segments.push(Element(index))
  { root: self.root, segments, }
}

///|
pub fn Path::field(
  self : Path,
  symbol : @model.IonSymbol,
  occurrence : Int,
) -> Path {
  let segments = copy_segments(self.segments[:])
  segments.push(Field(symbol, occurrence))
  { root: self.root, segments, }
}

///|
/// Select the wrapped value of one annotation layer.
pub fn Path::annotated_value(self : Path) -> Path {
  let segments = copy_segments(self.segments[:])
  segments.push(AnnotatedValue)
  { root: self.root, segments, }
}

///|
fn copy_segments(segments : ArrayView[PathSegment]) -> Array[PathSegment] {
  let copied : Array[PathSegment] = []
  for segment in segments {
    copied.push(segment)
  }
  copied
}

///|
fn field_position(
  fields : Array[(@model.IonSymbol, @model.IonValue)],
  symbol : @model.IonSymbol,
  occurrence : Int,
) -> Int raise PatchError {
  if occurrence < 0 {
    raise PatchError::InvalidPath("field occurrence must be non-negative")
  }
  let mut seen = 0
  for index in 0..<fields.length() {
    if fields[index].0 == symbol {
      if seen == occurrence {
        return index
      }
      seen += 1
    }
  }
  raise PatchError::InvalidPath("field occurrence does not exist")
}

///|
fn occurrence_at(
  fields : Array[(@model.IonSymbol, @model.IonValue)],
  index : Int,
) -> Int {
  let mut count = 0
  for earlier in 0..<index {
    if fields[earlier].0 == fields[index].0 {
      count += 1
    }
  }
  count
}
