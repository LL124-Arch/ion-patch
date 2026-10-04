///|
test "merge combines independent top-level deletions" {
  assert_merged(
    @ion.parse_text("a b c d"),
    @ion.parse_text("a c d"),
    @ion.parse_text("a b c"),
    @ion.parse_text("a c"),
  )
  assert_merged(
    @ion.parse_text("a b c d"),
    @ion.parse_text("a c d"),
    @ion.parse_text("a c"),
    @ion.parse_text("a c"),
  )
}

///|
test "merge combines deletions inside lists and s-expressions" {
  assert_merged(
    @ion.parse_text("[a, b, c, d]"),
    @ion.parse_text("[a, c, d]"),
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[a, c]"),
  )
  assert_merged(
    @ion.parse_text("(a b c d)"),
    @ion.parse_text("(b c d)"),
    @ion.parse_text("(a b d)"),
    @ion.parse_text("(b d)"),
  )
  assert_merged(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[a]"),
    @ion.parse_text("[b]"),
    @ion.parse_text("[]"),
  )
}

///|
test "merge combines deletions below unchanged annotations" {
  assert_merged(
    @ion.parse_text("tag::[a, b, c, d]"),
    @ion.parse_text("tag::[a, c, d]"),
    @ion.parse_text("tag::[a, b, c]"),
    @ion.parse_text("tag::[a, c]"),
  )
}

///|
test "merge preserves duplicate fields and unknown SIDs after deletions" {
  let sid = @model.IonSymbol::from_sid(77)
  let x = @model.IonSymbol::from_text("x")
  let y = @model.IonSymbol::from_text("y")
  let one = @ion.parse_one_text("1")
  let two = @ion.parse_one_text("2")
  let three = @ion.parse_one_text("3")
  let four = @ion.parse_one_text("4")
  assert_merged(
    [@model.IonValue::Struct([(sid, one), (x, two), (sid, three), (y, four)])],
    [@model.IonValue::Struct([(sid, one), (sid, three), (y, four)])],
    [@model.IonValue::Struct([(sid, one), (x, two), (sid, three)])],
    [@model.IonValue::Struct([(sid, one), (sid, three)])],
  )
}

///|
test "merge accepts equal deletions and rejects ambiguous survivors" {
  assert_merged(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[a, c]"),
    @ion.parse_text("[a, c]"),
    @ion.parse_text("[a, c]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, a, b]"),
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[a, a]"),
  )
  assert_merge_conflict(
    @ion.parse_text("{a: 1, a: 1, b: 2}"),
    @ion.parse_text("{a: 1, b: 2}"),
    @ion.parse_text("{a: 1, a: 1}"),
  )
}

///|
test "deletion anchors distinguish signed zero and NaN payloads" {
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  assert_merged(
    [@model.IonValue::List([positive, negative, nan_one, nan_two])],
    [@model.IonValue::List([negative, nan_one, nan_two])],
    [@model.IonValue::List([positive, negative, nan_one])],
    [@model.IonValue::List([negative, nan_one])],
  )
}

///|
test "merge rejects deletion mixed with replacement or reordering" {
  assert_merge_conflict(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[a, c]"),
    @ion.parse_text("[x, c]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[a, c]"),
    @ion.parse_text("[c, a]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[a, c]"),
    @ion.parse_text("[a, x]"),
  )
}

///|
test "every pair of deletion positions merges in either branch order" {
  let base = @ion.parse_text("a b c d")
  for left_removed in 0..<base.length() {
    for right_removed in 0..<base.length() {
      let left = [
        @ion-patch.PatchOp::Remove(@ion-patch.Path::root(left_removed)),
      ]
      let right = [
        @ion-patch.PatchOp::Remove(@ion-patch.Path::root(right_removed)),
      ]
      let expected : Array[@model.IonValue] = []
      for index in 0..<base.length() {
        if index != left_removed && index != right_removed {
          expected.push(base[index])
        }
      }
      let combined = @ion-patch.merge(base[:], left[:], right[:])
      let swapped = @ion-patch.merge(base[:], right[:], left[:])
      let actual = @ion-patch.apply(base[:], combined[:])
      let other = @ion-patch.apply(base[:], swapped[:])
      assert_eq(@ion-patch.equal_values(actual[:], expected[:]), true)
      assert_eq(@ion-patch.equal_values(other[:], expected[:]), true)
    }
  }
}

///|
test "merge enforces output operation limits for distinct deletions" {
  let base = @ion.parse_text("a b c")
  let left = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(0))]
  let right = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(2))]
  let limits = @ion-patch.PatchLimits::new(max_operations=1)
  let error = try @ion-patch.merge(base[:], left[:], right[:], limits~) catch {
    error => error
  } noraise {
    _ => fail("expected merged operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  assert_eq(@ion-patch.equal_values(base[:], @ion.parse_text("a b c")[:]), true)
}
