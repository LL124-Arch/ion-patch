///|
test "merge aligns disjoint insertions inside a list and s-expression" {
  assert_merged(
    @ion.parse_text("[a, (b c), d]"),
    @ion.parse_text("[x, a, (b c), d]"),
    @ion.parse_text("[a, (b c), y, d]"),
    @ion.parse_text("[x, a, (b c), y, d]"),
  )
  assert_merged(
    @ion.parse_text("(a b c)"),
    @ion.parse_text("(a x b c)"),
    @ion.parse_text("(a b c y)"),
    @ion.parse_text("(a x b c y)"),
  )
}

///|
test "merge aligns insertions through annotations" {
  assert_merged(
    @ion.parse_text("tag::[a, b, c]"),
    @ion.parse_text("tag::[x, a, b, c]"),
    @ion.parse_text("tag::[a, b, y, c]"),
    @ion.parse_text("tag::[x, a, b, y, c]"),
  )
}

///|
test "merge preserves duplicate fields and unknown SIDs across insertion gaps" {
  let sid = @model.IonSymbol::from_sid(77)
  let x = @model.IonSymbol::from_text("x")
  let y = @model.IonSymbol::from_text("y")
  let z = @model.IonSymbol::from_text("z")
  let one = @ion.parse_one_text("1")
  let two = @ion.parse_one_text("2")
  let three = @ion.parse_one_text("3")
  let eight = @ion.parse_one_text("8")
  let nine = @ion.parse_one_text("9")
  assert_merged(
    [@model.IonValue::Struct([(sid, one), (x, two), (sid, three)])],
    [@model.IonValue::Struct([(sid, one), (y, nine), (x, two), (sid, three)])],
    [@model.IonValue::Struct([(sid, one), (x, two), (sid, three), (z, eight)])],
    [
      @model.IonValue::Struct([
        (sid, one),
        (y, nine),
        (x, two),
        (sid, three),
        (z, eight),
      ]),
    ],
  )
}

///|
test "merge accepts identical insertions and rejects different same-gap edits" {
  assert_merged(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[a, x, b]"),
    @ion.parse_text("[a, x, b]"),
    @ion.parse_text("[a, x, b]"),
  )
  assert_merged(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[w, a, x, b]"),
    @ion.parse_text("[a, x, b, y]"),
    @ion.parse_text("[w, a, x, b, y]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[a, x, b]"),
    @ion.parse_text("[a, y, b]"),
  )
  assert_merged(
    @ion.parse_text("[]"),
    @ion.parse_text("[x]"),
    @ion.parse_text("[x]"),
    @ion.parse_text("[x]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[]"),
    @ion.parse_text("[x]"),
    @ion.parse_text("[y]"),
  )
}

///|
test "merge handles repeated base values only with unique positions" {
  assert_merged(
    @ion.parse_text("[a, a]"),
    @ion.parse_text("[x, a, a]"),
    @ion.parse_text("[a, a, y]"),
    @ion.parse_text("[x, a, a, y]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[a, a, b]"),
    @ion.parse_text("[a, b, x]"),
  )
  assert_merge_conflict(
    @ion.parse_text("{a: 1, b: 2}"),
    @ion.parse_text("{a: 1, a: 1, b: 2}"),
    @ion.parse_text("{a: 1, b: 2, c: 3}"),
  )
}

///|
test "merge keeps mixed edits to the same resized container conservative" {
  assert_merge_conflict(
    @ion.parse_text("[a, b]"),
    @ion.parse_text("[x, a, b]"),
    @ion.parse_text("[a, c, x]"),
  )
  assert_merge_conflict(
    @ion.parse_text("[a, b, c]"),
    @ion.parse_text("[x, a, b, c]"),
    @ion.parse_text("[a, c, d]"),
  )
}

///|
test "merge insertion alignment works with a zero diff alignment budget" {
  let base = @ion.parse_text("a b c d e")
  let left = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("x"))]
  let right = [@ion-patch.PatchOp::InsertRoot(4, @ion.parse_one_text("y"))]
  let limits = @ion-patch.PatchLimits::new(max_alignment_cells=0)
  let combined = @ion-patch.merge(base[:], left[:], right[:], limits~)
  let result = @ion-patch.apply(base[:], combined[:], limits~)
  assert_eq(
    @ion-patch.equal_values(result[:], @ion.parse_text("a x b c d y e")[:]),
    true,
  )
  let reverse = @ion-patch.invert(base[:], combined[:], limits~)
  let restored = @ion-patch.apply(result[:], reverse[:], limits~)
  assert_eq(@ion-patch.equal_values(restored[:], base[:]), true)
}

///|
test "all distinct insertion gaps merge in either branch order" {
  let base = @ion.parse_text("a b c")
  let x = @ion.parse_one_text("x")
  let y = @ion.parse_one_text("y")
  for left_gap in 0..<=base.length() {
    for right_gap in 0..<=base.length() {
      let left = [@ion-patch.PatchOp::InsertRoot(left_gap, x)]
      let right = [@ion-patch.PatchOp::InsertRoot(right_gap, y)]
      if left_gap == right_gap {
        let error = try @ion-patch.merge(base[:], left[:], right[:]) catch {
          error => error
        } noraise {
          _ => fail("expected same-gap conflict")
        }
        match error {
          @ion-patch.PatchError::Conflict(_) => ()
          _ => fail("expected conflict error")
        }
      } else {
        let expected : Array[@model.IonValue] = []
        for gap in 0..<=base.length() {
          if gap == left_gap {
            expected.push(x)
          }
          if gap == right_gap {
            expected.push(y)
          }
          if gap < base.length() {
            expected.push(base[gap])
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
}
