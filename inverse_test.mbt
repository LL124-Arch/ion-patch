///|
test "inverse reverses a mixed operation chain exactly" {
  let original = @ion.parse_text("{x: 1, x: 2} [a, b] z")
  let x = @model.IonSymbol::from_text("x")
  let operations = [
    @ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("99")),
    @ion-patch.PatchOp::InsertField(
      @ion-patch.Path::root(0),
      1,
      x,
      @ion.parse_one_text("3"),
    ),
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(2).element(1),
      @ion.parse_one_text("c"),
    ),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).field(x, 2)),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(3)),
  ]
  let inverse = @ion-patch.invert(original[:], operations[:])
  let expected = [
    @ion-patch.PatchOp::InsertRoot(3, @ion.parse_one_text("z")),
    @ion-patch.PatchOp::InsertField(
      @ion-patch.Path::root(0),
      2,
      x,
      @ion.parse_one_text("2"),
    ),
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(2).element(1),
      @ion.parse_one_text("b"),
    ),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).field(x, 1)),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(1)),
  ]
  assert_eq(inverse.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(same_operation(inverse[i], expected[i]), true)
  }
  let changed = @ion-patch.apply(original[:], operations[:])
  let restored = @ion-patch.apply(changed[:], inverse[:])
  assert_eq(@ion-patch.equal_values(restored[:], original[:]), true)
}

///|
test "inverse restores an unknown SID field at its absolute position" {
  let sid = @model.IonSymbol::from_sid(77)
  let x = @model.IonSymbol::from_text("x")
  let original = [
    @model.IonValue::Struct([
      (sid, @ion.parse_one_text("1")),
      (x, @ion.parse_one_text("2")),
      (sid, @ion.parse_one_text("3")),
    ]),
  ]
  let operations = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).field(sid, 1)),
    @ion-patch.PatchOp::InsertField(
      @ion-patch.Path::root(0),
      1,
      sid,
      @ion.parse_one_text("4"),
    ),
  ]
  let inverse = @ion-patch.invert(original[:], operations[:])
  assert_eq(inverse.length(), 2)
  assert_eq(
    same_operation(
      inverse[0],
      @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).field(sid, 1)),
    ),
    true,
  )
  assert_eq(
    same_operation(
      inverse[1],
      @ion-patch.PatchOp::InsertField(
        @ion-patch.Path::root(0),
        2,
        sid,
        @ion.parse_one_text("3"),
      ),
    ),
    true,
  )
  let changed = @ion-patch.apply(original[:], operations[:])
  let restored = @ion-patch.apply(changed[:], inverse[:])
  assert_eq(@ion-patch.equal_values(restored[:], original[:]), true)
}

///|
test "inverse keeps annotation paths and float bit patterns" {
  let before = @ion.parse_text("tag::[0e0, (a b)]")
  let parent = @ion-patch.Path::root(0).annotated_value()
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let operations = [
    @ion-patch.PatchOp::Replace(parent.element(0), negative),
    @ion-patch.PatchOp::InsertElement(
      parent.element(1),
      1,
      @ion.parse_one_text("x"),
    ),
  ]
  let inverse = @ion-patch.invert(before[:], operations[:])
  assert_eq(inverse.length(), 2)
  assert_eq(
    same_operation(
      inverse[0],
      @ion-patch.PatchOp::Remove(parent.element(1).element(1)),
    ),
    true,
  )
  assert_eq(
    same_operation(
      inverse[1],
      @ion-patch.PatchOp::Replace(parent.element(0), @ion.parse_one_text("0e0")),
    ),
    true,
  )
  let changed = @ion-patch.apply(before[:], operations[:])
  let restored = @ion-patch.apply(changed[:], inverse[:])
  assert_eq(@ion-patch.equal_values(restored[:], before[:]), true)
}

///|
test "inverse uses parent replacement at the path depth limit" {
  let before = @ion.parse_text("[a, b] {x: 1}")
  let x = @model.IonSymbol::from_text("x")
  let operations = [
    @ion-patch.PatchOp::InsertElement(
      @ion-patch.Path::root(0),
      1,
      @ion.parse_one_text("c"),
    ),
    @ion-patch.PatchOp::InsertField(
      @ion-patch.Path::root(1),
      1,
      x,
      @ion.parse_one_text("2"),
    ),
  ]
  let limits = @ion-patch.PatchLimits::new(
    max_operations=2,
    max_path_depth=0,
    max_alignment_cells=0,
  )
  let inverse = @ion-patch.invert(before[:], operations[:], limits~)
  assert_eq(inverse.length(), 2)
  assert_eq(
    same_operation(
      inverse[0],
      @ion-patch.PatchOp::Replace(
        @ion-patch.Path::root(1),
        @ion.parse_one_text("{x: 1}"),
      ),
    ),
    true,
  )
  assert_eq(
    same_operation(
      inverse[1],
      @ion-patch.PatchOp::Replace(
        @ion-patch.Path::root(0),
        @ion.parse_one_text("[a, b]"),
      ),
    ),
    true,
  )
  let changed = @ion-patch.apply(before[:], operations[:], limits~)
  let restored = @ion-patch.apply(changed[:], inverse[:], limits~)
  assert_eq(@ion-patch.equal_values(restored[:], before[:]), true)
}

///|
test "inverse rejects later invalid edits without changing the original" {
  let original = @ion.parse_text("[1] 2")
  let operations = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0).element(0),
      @ion.parse_one_text("3"),
    ),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(9)),
  ]
  let error = try @ion-patch.invert(original[:], operations[:]) catch {
    error => error
  } noraise {
    _ => fail("expected invalid path")
  }
  match error {
    @ion-patch.PatchError::InvalidPath(_) => ()
    _ => fail("expected invalid path")
  }
  assert_eq(
    @ion-patch.equal_values(original[:], @ion.parse_text("[1] 2")[:]),
    true,
  )
  let zero = @ion-patch.PatchLimits::new(max_operations=0)
  let limit_error = try
    @ion-patch.invert(original[:], operations[:], limits=zero)
  catch {
    error => error
  } noraise {
    _ => fail("expected operation limit")
  }
  match limit_error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
}

///|
test "inverse owns removed values and permits an empty patch" {
  let original = @ion.parse_text("[1]")
  let empty_limits = @ion-patch.PatchLimits::new(max_operations=0)
  let no_inverse = @ion-patch.invert(original[:], [], limits=empty_limits)
  assert_eq(no_inverse.length(), 0)
  let remove = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(0))]
  let inverse = @ion-patch.invert(original[:], remove[:])
  match original[0] {
    @model.IonValue::List(items) => items.push(@ion.parse_one_text("2"))
    _ => fail("expected list")
  }
  let restored = @ion-patch.apply([], inverse[:])
  assert_eq(
    @ion-patch.equal_values(restored[:], @ion.parse_text("[1]")[:]),
    true,
  )
}

///|
test "inverse enforces intermediate Ion value limits" {
  let original = @ion.parse_text("1")
  let operations = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("2"))]
  let limits = @ion-patch.PatchLimits::new(
    value_limits=@model.Limits::new(max_values=1),
  )
  let error = try @ion-patch.invert(original[:], operations[:], limits~) catch {
    error => error
  } noraise {
    _ => fail("expected Ion value limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  assert_eq(@ion-patch.equal_values(original[:], @ion.parse_text("1")[:]), true)
}
