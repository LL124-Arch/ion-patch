///|
/// Combine two sequential patches into a deterministic patch for their net
/// effect. `second` is applied to the result of `first`; each patch is
/// validated against the state where it runs.
pub fn compose(
  original : ArrayView[@model.IonValue],
  first : ArrayView[PatchOp],
  second : ArrayView[PatchOp],
  limits? : PatchLimits,
) -> Array[PatchOp] raise PatchError {
  let limits = limits.unwrap_or(PatchLimits::default())
  let middle = apply(original, first, limits~)
  let result = apply(middle[:], second, limits~)
  diff(original, result[:], limits~)
}
