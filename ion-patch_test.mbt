///|
test "Ion codec dependency parses a document" {
  let values = @ion.parse_text("{name: \"MoonBit\"}")
  assert_eq(values.length(), 1)
}
