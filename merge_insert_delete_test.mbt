///|
test "merge combines root insertion with independent deletion" {
  assert_merged(
    @ion.parse_text("a b c"),
    @ion.parse_text("x a b c"),
    @ion.parse_text("a c"),
    @ion.parse_text("x a c"),
  )
  assert_merged(
    @ion.parse_text("a b c"),
    @ion.parse_text("a x b c"),
    @ion.parse_text("b c"),
    @ion.parse_text("x b c"),
  )
}

///|
test "merge combines insertion and deletion inside lists and s-expressions" {
  assert_merged(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[a, x, b, c]"),
    @ion.parse_text("[a, c]"),
    @ion.parse_text("[a, x, c]"),
  )
  assert_merged(
    @ion.parse_text("(a b c)"),
    @ion.parse_text("(a b x c)"),
    @ion.parse_text("(b c)"),
    @ion.parse_text("(b x c)"),
  )
  assert_merged(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[x, a, y, b, z]"),
    @ion.parse_text("[]"),
    @ion.parse_text("[x, y, z]"),
  )
}

///|
test "merge combines insertion and deletion below annotations" {
  assert_merged(
    @ion.parse_text("tag::[a, b, c]"),
    @ion.parse_text("tag::[a, x, b, c]"),
    @ion.parse_text("tag::[a, c]"),
    @ion.parse_text("tag::[a, x, c]"),
  )
}

///|
test "merge preserves duplicate SID fields across insertion and deletion" {
  let sid = @model.IonSymbol::from_sid(77)
  let x = @model.IonSymbol::from_text("x")
  let y = @model.IonSymbol::from_text("y")
  let one = @ion.parse_one_text("1")
  let two = @ion.parse_one_text("2")
  let three = @ion.parse_one_text("3")
  let nine = @ion.parse_one_text("9")
  assert_merged(
    [@model.IonValue::Struct([(sid, one), (x, two), (sid, three)])],
    [@model.IonValue::Struct([(sid, one), (y, nine), (x, two), (sid, three)])],
    [@model.IonValue::Struct([(sid, one), (sid, three)])],
    [@model.IonValue::Struct([(sid, one), (y, nine), (sid, three)])],
  )
}

///|
test "merge insertion and deletion anchors compare float bits" {
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  assert_merged(
    [@model.IonValue::List([positive, negative, nan_one])],
    [@model.IonValue::List([positive, nan_two, negative, nan_one])],
    [@model.IonValue::List([positive, nan_one])],
    [@model.IonValue::List([positive, nan_two, nan_one])],
  )
}

///|
test "merge rejects ambiguous insertion or deletion mappings" {
  assert_merge_conflict(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[a, a, b]"),
    @ion.parse_text("[b]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, a, b]"),
    @ion.parse_text("[x, a, a, b]"),
    @ion.parse_text("[a, b]"),
  )
  assert_merge_conflict(
    @ion.parse_text("{a: 1, a: 1, b: 2}"),
    @ion.parse_text("{x: 0, a: 1, a: 1, b: 2}"),
    @ion.parse_text("{a: 1, b: 2}"),
  )
}

///|
test "merge rejects edits that are not pure insertion or deletion" {
  assert_merge_conflict(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[x, a, y, c]"),
    @ion.parse_text("[a, c]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[x, a, b, c]"),
    @ion.parse_text("[c, a]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[x, a, b, c]"),
    @ion.parse_text("[a, y]"),
  )
}

///|
test "every insertion gap and removal position merges symmetrically" {
  let base = @ion.parse_text("a b c")
  let x = @ion.parse_one_text("x")
  for gap in 0..<=base.length() {
    for removed in 0..<base.length() {
      let insert = [@ion-patch.PatchOp::InsertRoot(gap, x)]
      let delete = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(removed))]
      let expected : Array[@model.IonValue] = []
      for index in 0..<=base.length() {
        if index == gap {
          expected.push(x)
        }
        if index < base.length() && index != removed {
          expected.push(base[index])
        }
      }
      let left = @ion-patch.merge(base[:], insert[:], delete[:])
      let right = @ion-patch.merge(base[:], delete[:], insert[:])
      let first_result = @ion-patch.apply(base[:], left[:])
      let second_result = @ion-patch.apply(base[:], right[:])
      assert_eq(@ion-patch.equal_values(first_result[:], expected[:]), true)
      assert_eq(@ion-patch.equal_values(second_result[:], expected[:]), true)
    }
  }
}

///|
test "merge enforces limits after combining insertion and deletion" {
  let base = @ion.parse_text("a b c")
  let insert = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("x"))]
  let delete = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(2))]
  let limits = @ion-patch.PatchLimits::new(max_operations=1)
  let error = try
    @ion-patch.merge(base[:], insert[:], delete[:], limits~)
  catch {
    error => error
  } noraise {
    _ => fail("expected output operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  assert_eq(@ion-patch.equal_values(base[:], @ion.parse_text("a b c")[:]), true)
}
