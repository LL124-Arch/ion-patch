///|
fn assert_merged(
  base : Array[@model.IonValue],
  left_document : Array[@model.IonValue],
  right_document : Array[@model.IonValue],
  expected : Array[@model.IonValue],
) -> Unit raise Error {
  let base_snapshot = @ion-patch.apply(base[:], [])
  let left_snapshot = @ion-patch.apply(left_document[:], [])
  let right_snapshot = @ion-patch.apply(right_document[:], [])
  let left = @ion-patch.diff(base[:], left_document[:])
  let right = @ion-patch.diff(base[:], right_document[:])
  let combined = @ion-patch.merge(base[:], left[:], right[:])
  let swapped = @ion-patch.merge(base[:], right[:], left[:])
  assert_eq(combined.length(), swapped.length())
  for i in 0..<combined.length() {
    assert_eq(same_operation(combined[i], swapped[i]), true)
  }
  let current = @ion-patch.apply(base[:], [])
  let result = @ion-patch.apply_checked(base[:], current[:], combined[:])
  assert_eq(@ion-patch.equal_values(result[:], expected[:]), true)
  let reverse = @ion-patch.invert(base[:], combined[:])
  let restored = @ion-patch.apply(result[:], reverse[:])
  assert_eq(@ion-patch.equal_values(restored[:], base[:]), true)
  assert_eq(@ion-patch.equal_values(base[:], base_snapshot[:]), true)
  assert_eq(@ion-patch.equal_values(left_document[:], left_snapshot[:]), true)
  assert_eq(@ion-patch.equal_values(right_document[:], right_snapshot[:]), true)
}

///|
fn assert_merge_conflict(
  base : Array[@model.IonValue],
  left_document : Array[@model.IonValue],
  right_document : Array[@model.IonValue],
) -> Unit raise Error {
  let left = @ion-patch.diff(base[:], left_document[:])
  let right = @ion-patch.diff(base[:], right_document[:])
  let snapshot = @ion-patch.apply(base[:], [])
  let error = try @ion-patch.merge(base[:], left[:], right[:]) catch {
    error => error
  } noraise {
    _ => fail("expected merge conflict")
  }
  match error {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error")
  }
  assert_eq(@ion-patch.equal_values(base[:], snapshot[:]), true)
}

///|
test "merge combines independent top-level changes" {
  assert_merged(
    @ion.parse_text("1 2"),
    @ion.parse_text("3 2"),
    @ion.parse_text("1 4"),
    @ion.parse_text("3 4"),
  )
}

///|
test "merge combines independent nested list and s-expression edits" {
  assert_merged(
    @ion.parse_text("[1, (a b), 3]"),
    @ion.parse_text("[2, (a b), 3]"),
    @ion.parse_text("[1, (a c), 3]"),
    @ion.parse_text("[2, (a c), 3]"),
  )
  assert_merged(
    @ion.parse_text("[1] [2]"),
    @ion.parse_text("[1, 3] [2]"),
    @ion.parse_text("[1] [2, 4]"),
    @ion.parse_text("[1, 3] [2, 4]"),
  )
}

///|
test "merge preserves duplicate fields and unknown SIDs" {
  let sid = @model.IonSymbol::from_sid(77)
  let x = @model.IonSymbol::from_text("x")
  let base = [
    @model.IonValue::Struct([
      (sid, @ion.parse_one_text("1")),
      (x, @ion.parse_one_text("2")),
      (sid, @ion.parse_one_text("3")),
    ]),
  ]
  let left = [
    @model.IonValue::Struct([
      (sid, @ion.parse_one_text("4")),
      (x, @ion.parse_one_text("2")),
      (sid, @ion.parse_one_text("3")),
    ]),
  ]
  let right = [
    @model.IonValue::Struct([
      (sid, @ion.parse_one_text("1")),
      (x, @ion.parse_one_text("2")),
      (sid, @ion.parse_one_text("5")),
    ]),
  ]
  let expected = [
    @model.IonValue::Struct([
      (sid, @ion.parse_one_text("4")),
      (x, @ion.parse_one_text("2")),
      (sid, @ion.parse_one_text("5")),
    ]),
  ]
  assert_merged(base, left, right, expected)
}

///|
test "merge recurses below unchanged annotations" {
  assert_merged(
    @ion.parse_text("a::b::{x: 1, y: 2}"),
    @ion.parse_text("a::b::{x: 3, y: 2}"),
    @ion.parse_text("a::b::{x: 1, y: 4}"),
    @ion.parse_text("a::b::{x: 3, y: 4}"),
  )
}

///|
test "merge accepts equal parallel edits and exact float changes" {
  assert_merged(
    @ion.parse_text("1"),
    @ion.parse_text("2"),
    @ion.parse_text("2"),
    @ion.parse_text("2"),
  )
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  assert_merged([positive, nan_one], [negative, nan_one], [positive, nan_two], [
    negative, nan_two,
  ])
  assert_merge_conflict([positive], [negative], [nan_two])
}

///|
test "merge rejects divergent edits to the same value" {
  assert_merge_conflict(
    @ion.parse_text("1"),
    @ion.parse_text("2"),
    @ion.parse_text("3"),
  )
  assert_merge_conflict(
    @ion.parse_text("a::1"),
    @ion.parse_text("b::2"),
    @ion.parse_text("a::3"),
  )
}

///|
test "merge accepts distinct insertion gaps and rejects field layout conflicts" {
  assert_merged(
    @ion.parse_text("[1, 2]"),
    @ion.parse_text("[0, 1, 2]"),
    @ion.parse_text("[1, 2, 3]"),
    @ion.parse_text("[0, 1, 2, 3]"),
  )
  assert_merge_conflict(
    @ion.parse_text("{a: 1}"),
    @ion.parse_text("{a: 1, b: 2}"),
    @ion.parse_text("{a: 1, c: 3}"),
  )
  assert_merge_conflict(
    @ion.parse_text("{a: 1, b: 2}"),
    @ion.parse_text("{b: 2, a: 1}"),
    @ion.parse_text("{a: 3, b: 2}"),
  )
  assert_merged(
    @ion.parse_text("1 2"),
    @ion.parse_text("0 1 2"),
    @ion.parse_text("1 2 3"),
    @ion.parse_text("0 1 2 3"),
  )
}

///|
test "merge validates both patches and the output operation limit" {
  let base = @ion.parse_text("1 2")
  let first = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("3"),
    ),
  ]
  let second = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(1),
      @ion.parse_one_text("4"),
    ),
  ]
  let one = @ion-patch.PatchLimits::new(max_operations=1)
  let error = try
    @ion-patch.merge(base[:], first[:], second[:], limits=one)
  catch {
    error => error
  } noraise {
    _ => fail("expected output operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let two = [first[0], second[0]]
  let error = try @ion-patch.merge(base[:], two[:], [], limits=one) catch {
    error => error
  } noraise {
    _ => fail("expected input operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let invalid = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(9))]
  let error = try @ion-patch.merge(base[:], first[:], invalid[:]) catch {
    error => error
  } noraise {
    _ => fail("expected invalid right patch")
  }
  match error {
    @ion-patch.PatchError::InvalidPath(_) => ()
    _ => fail("expected invalid path")
  }
  assert_eq(@ion-patch.equal_values(base[:], @ion.parse_text("1 2")[:]), true)
}

///|
test "merge checks the combined Ion value size" {
  let base = @ion.parse_text("[1] [2]")
  let left = [
    @ion-patch.PatchOp::InsertElement(
      @ion-patch.Path::root(0),
      1,
      @ion.parse_one_text("3"),
    ),
  ]
  let right = [
    @ion-patch.PatchOp::InsertElement(
      @ion-patch.Path::root(1),
      1,
      @ion.parse_one_text("4"),
    ),
  ]
  let limits = @ion-patch.PatchLimits::new(
    value_limits=@model.Limits::new(max_values=5),
  )
  let _ = @ion-patch.apply(base[:], left[:], limits~)
  let _ = @ion-patch.apply(base[:], right[:], limits~)
  let error = try @ion-patch.merge(base[:], left[:], right[:], limits~) catch {
    error => error
  } noraise {
    _ => fail("expected merged Ion value limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  assert_eq(
    @ion-patch.equal_values(base[:], @ion.parse_text("[1] [2]")[:]),
    true,
  )
}
