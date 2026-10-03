///|
fn assert_composed_result(
  original : Array[@model.IonValue],
  first : Array[@ion-patch.PatchOp],
  second : Array[@ion-patch.PatchOp],
  limits : @ion-patch.PatchLimits,
) -> Unit raise Error {
  let middle = @ion-patch.apply(original[:], first[:], limits~)
  let result = @ion-patch.apply(middle[:], second[:], limits~)
  let combined = @ion-patch.compose(original[:], first[:], second[:], limits~)
  let again = @ion-patch.compose(original[:], first[:], second[:], limits~)
  assert_eq(combined.length(), again.length())
  for i in 0..<combined.length() {
    assert_eq(same_operation(combined[i], again[i]), true)
  }
  let actual = @ion-patch.apply(original[:], combined[:], limits~)
  assert_eq(@ion-patch.equal_values(actual[:], result[:]), true)
  let reverse = @ion-patch.invert(original[:], combined[:], limits~)
  let restored = @ion-patch.apply(actual[:], reverse[:], limits~)
  assert_eq(@ion-patch.equal_values(restored[:], original[:]), true)
}

///|
test "composition removes an insertion that is later deleted" {
  let original = @ion.parse_text("a b")
  let first = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("x"))]
  let second = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(1))]
  let limits = @ion-patch.PatchLimits::new(max_operations=1)
  let combined = @ion-patch.compose(original[:], first[:], second[:], limits~)
  assert_eq(combined.length(), 0)
  assert_composed_result(original, first, second, limits)
}

///|
test "composition collapses consecutive replacements" {
  let original = @ion.parse_text("a b")
  let first = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("x"),
    ),
  ]
  let second = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("y"),
    ),
  ]
  let combined = @ion-patch.compose(original[:], first[:], second[:])
  assert_eq(combined.length(), 1)
  assert_eq(
    same_operation(
      combined[0],
      @ion-patch.PatchOp::Replace(
        @ion-patch.Path::root(0),
        @ion.parse_one_text("y"),
      ),
    ),
    true,
  )
  assert_composed_result(
    original,
    first,
    second,
    @ion-patch.PatchLimits::default(),
  )
}

///|
test "composition interprets second paths after a top-level insertion" {
  let original = @ion.parse_text("a b c")
  let first = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("x"))]
  let second = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(2),
      @ion.parse_one_text("d"),
    ),
  ]
  let combined = @ion-patch.compose(original[:], first[:], second[:])
  let actual = @ion-patch.apply(original[:], combined[:])
  assert_eq(
    @ion-patch.equal_values(actual[:], @ion.parse_text("a x d c")[:]),
    true,
  )
  assert_composed_result(
    original,
    first,
    second,
    @ion-patch.PatchLimits::default(),
  )
}

///|
test "composition keeps duplicate SID fields inside annotations" {
  let sid = @model.IonSymbol::from_sid(77)
  let tag = @model.IonSymbol::from_text("tag")
  let original = [
    @model.IonValue::Annotated(
      [tag],
      @model.IonValue::Struct([
        (sid, @ion.parse_one_text("1")),
        (sid, @ion.parse_one_text("2")),
      ]),
    ),
  ]
  let parent = @ion-patch.Path::root(0).annotated_value()
  let first = [
    @ion-patch.PatchOp::InsertField(parent, 1, sid, @ion.parse_one_text("3")),
  ]
  let second = [@ion-patch.PatchOp::Remove(parent.field(sid, 0))]
  let combined = @ion-patch.compose(original[:], first[:], second[:])
  let actual = @ion-patch.apply(original[:], combined[:])
  let expected = [
    @model.IonValue::Annotated(
      [tag],
      @model.IonValue::Struct([
        (sid, @ion.parse_one_text("3")),
        (sid, @ion.parse_one_text("2")),
      ]),
    ),
  ]
  assert_eq(@ion-patch.equal_values(actual[:], expected[:]), true)
  assert_composed_result(
    original,
    first,
    second,
    @ion-patch.PatchLimits::default(),
  )
}

///|
test "composition preserves signed zero and NaN payloads" {
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  let original = [positive, nan_one]
  let first = [@ion-patch.PatchOp::Replace(@ion-patch.Path::root(0), negative)]
  let second = [@ion-patch.PatchOp::Replace(@ion-patch.Path::root(1), nan_two)]
  let combined = @ion-patch.compose(original[:], first[:], second[:])
  let actual = @ion-patch.apply(original[:], combined[:])
  assert_eq(@ion-patch.equal_values(actual[:], [negative, nan_two][:]), true)
  assert_composed_result(
    original,
    first,
    second,
    @ion-patch.PatchLimits::default(),
  )
}

///|
test "composition validates the second patch and preserves the original" {
  let original = @ion.parse_text("a b")
  let first = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("x"))]
  let second = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(9))]
  let error = try @ion-patch.compose(original[:], first[:], second[:]) catch {
    error => error
  } noraise {
    _ => fail("expected invalid second patch")
  }
  match error {
    @ion-patch.PatchError::InvalidPath(_) => ()
    _ => fail("expected invalid path")
  }
  assert_eq(
    @ion-patch.equal_values(original[:], @ion.parse_text("a b")[:]),
    true,
  )
}

///|
test "composition respects output limits and alignment fallback" {
  let original = @ion.parse_text("1 2")
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
    @ion-patch.compose(original[:], first[:], second[:], limits=one)
  catch {
    error => error
  } noraise {
    _ => fail("expected output operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let source = @ion.parse_text("a b c d e")
  let insert_x = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("x"))]
  let insert_y = [@ion-patch.PatchOp::InsertRoot(4, @ion.parse_one_text("y"))]
  let no_alignment = @ion-patch.PatchLimits::new(max_alignment_cells=0)
  assert_composed_result(source, insert_x, insert_y, no_alignment)
}

///|
test "composition checks each input patch and intermediate value limits" {
  let original = @ion.parse_text("1")
  let first = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("2"),
    ),
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("3"),
    ),
  ]
  let one = @ion-patch.PatchLimits::new(max_operations=1)
  let error = try
    @ion-patch.compose(original[:], first[:], [], limits=one)
  catch {
    error => error
  } noraise {
    _ => fail("expected first patch operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let first_single = [first[0]]
  let error = try
    @ion-patch.compose(original[:], first_single[:], first[:], limits=one)
  catch {
    error => error
  } noraise {
    _ => fail("expected second patch operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let insert = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("4"))]
  let value_limits = @ion-patch.PatchLimits::new(
    value_limits=@model.Limits::new(max_values=1),
  )
  let error = try
    @ion-patch.compose(
      original[:],
      first_single[:],
      insert[:],
      limits=value_limits,
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected intermediate Ion value limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  assert_eq(@ion-patch.equal_values(original[:], @ion.parse_text("1")[:]), true)
}
