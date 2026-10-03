///|
/// Operations are applied in array order against the document produced by
/// preceding operations. Insert positions are zero-based and may equal the
/// current container length.
pub(all) enum PatchOp {
  InsertRoot(Int, @model.IonValue)
  InsertElement(Path, Int, @model.IonValue)
  InsertField(Path, Int, @model.IonSymbol, @model.IonValue)
  Remove(Path)
  Replace(Path, @model.IonValue)
}

///|
/// Structural limits used in addition to the Ion model's value limits.
pub(all) struct PatchLimits {
  max_operations : Int
  max_path_depth : Int
  max_alignment_cells : Int
  value_limits : @model.Limits
}

///|
pub fn PatchLimits::default() -> PatchLimits {
  {
    max_operations: 100000,
    max_path_depth: 64,
    max_alignment_cells: 1000000,
    value_limits: @model.Limits::default(),
  }
}

///|
pub fn PatchLimits::new(
  max_operations? : Int = 100000,
  max_path_depth? : Int = 64,
  max_alignment_cells? : Int = 1000000,
  value_limits? : @model.Limits = @model.Limits::default(),
) -> PatchLimits {
  { max_operations, max_path_depth, max_alignment_cells, value_limits, }
}

///|
pub(all) suberror PatchError {
  InvalidPath(String)
  WrongContainer(String)
  Limit(String)
}

///|
fn check_limits(limits : PatchLimits) -> Unit raise PatchError {
  if limits.max_operations < 0 ||
    limits.max_path_depth < 0 ||
    limits.max_alignment_cells < 0 {
    raise PatchError::Limit("patch limits must be non-negative")
  }
}

///|
fn check_path(path : Path, limits : PatchLimits) -> Unit raise PatchError {
  if path.root < 0 {
    raise PatchError::InvalidPath("root index must be non-negative")
  }
  if path.segments.length() > limits.max_path_depth {
    raise PatchError::Limit("path depth exceeds max_path_depth")
  }
}

///|
fn check_document(
  values : ArrayView[@model.IonValue],
  limits : PatchLimits,
) -> Unit raise PatchError {
  let _ = @ion.preflight_values(values, limits=limits.value_limits) catch {
    _ => raise PatchError::Limit("Ion value limits exceeded")
  }
}
