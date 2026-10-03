///|
fn assert_checked_conflict(
  expected : Array[@model.IonValue],
  current : Array[@model.IonValue],
  operations : Array[@ion-patch.PatchOp],
) -> Unit raise Error {
  let snapshot = @ion-patch.apply(current[:], [])
  let error = try
    @ion-patch.apply_checked(expected[:], current[:], operations[:])
  catch {
    error => error
  } noraise {
    _ => fail("expected baseline conflict")
  }
  match error {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error")
  }
  assert_eq(@ion-patch.equal_values(current[:], snapshot[:]), true)
}

///|
test "checked apply rejects a stale value even when its path is valid" {
  let expected = @ion.parse_text("a b")
  let current = @ion.parse_text("a x")
  let operations = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(1),
      @ion.parse_one_text("c"),
    ),
  ]
  let unchecked = @ion-patch.apply(current[:], operations[:])
  assert_eq(
    @ion-patch.equal_values(unchecked[:], @ion.parse_text("a c")[:]),
    true,
  )
  assert_checked_conflict(expected, current, operations)
}

///|
test "checked apply validates the whole document even for an empty patch" {
  assert_checked_conflict(@ion.parse_text("1"), @ion.parse_text("1 2"), [])
  assert_checked_conflict(
    @ion.parse_text("{a: 1, b: 2}"),
    @ion.parse_text("{b: 2, a: 1}"),
    [],
  )
  assert_checked_conflict(
    @ion.parse_text("{a: 1, a: 2}"),
    @ion.parse_text("{a: 2, a: 1}"),
    [],
  )
  assert_checked_conflict(
    @ion.parse_text("a::b::1"),
    @ion.parse_text("b::a::1"),
    [],
  )
  let same = @ion.parse_text("{a: 1, a: 2}")
  let result = @ion-patch.apply_checked(same[:], same[:], [])
  assert_eq(@ion-patch.equal_values(result[:], same[:]), true)
}

///|
test "checked apply distinguishes symbol SIDs and float bit patterns" {
  let sid_77 = @model.IonSymbol::from_sid(77)
  let sid_78 = @model.IonSymbol::from_sid(78)
  let one = @ion.parse_one_text("1")
  assert_checked_conflict(
    [@model.IonValue::Struct([(sid_77, one)])],
    [@model.IonValue::Struct([(sid_78, one)])],
    [],
  )
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  assert_checked_conflict([positive], [negative], [])
  assert_checked_conflict([nan_one], [nan_two], [])
}

///|
test "checked apply accepts composed and inverse patches on matching stages" {
  let original = @ion.parse_text("{a: [1, 2], a: 3}")
  let intermediate = @ion.parse_text("{a: [1, 4, 2], a: 3}")
  let result = @ion.parse_text("{a: [1, 4, 2], a: 5}")
  let first = @ion-patch.diff(original[:], intermediate[:])
  let second = @ion-patch.diff(intermediate[:], result[:])
  let combined = @ion-patch.compose(original[:], first[:], second[:])
  let current = @ion.parse_text("{a: [1, 2], a: 3}")
  let applied = @ion-patch.apply_checked(original[:], current[:], combined[:])
  assert_eq(@ion-patch.equal_values(applied[:], result[:]), true)
  let reverse = @ion-patch.invert(original[:], combined[:])
  let restored = @ion-patch.apply_checked(result[:], applied[:], reverse[:])
  assert_eq(@ion-patch.equal_values(restored[:], original[:]), true)
  assert_checked_conflict(intermediate, applied, reverse)
}

///|
test "checked apply reports limits and operation errors separately" {
  let expected = @ion.parse_text("1")
  let stale = @ion.parse_text("2")
  let operations = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("3"),
    ),
  ]
  let zero = @ion-patch.PatchLimits::new(max_operations=0)
  let error = try
    @ion-patch.apply_checked(expected[:], stale[:], operations[:], limits=zero)
  catch {
    error => error
  } noraise {
    _ => fail("expected operation limit before conflict")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let small = @ion-patch.PatchLimits::new(
    value_limits=@model.Limits::new(max_values=1),
  )
  let oversized = @ion.parse_text("1 2")
  let error = try
    @ion-patch.apply_checked(oversized[:], expected[:], [], limits=small)
  catch {
    error => error
  } noraise {
    _ => fail("expected baseline value limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let error = try
    @ion-patch.apply_checked(expected[:], oversized[:], [], limits=small)
  catch {
    error => error
  } noraise {
    _ => fail("expected current value limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let invalid = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(9))]
  let error = try
    @ion-patch.apply_checked(expected[:], expected[:], invalid[:])
  catch {
    error => error
  } noraise {
    _ => fail("expected invalid path")
  }
  match error {
    @ion-patch.PatchError::InvalidPath(_) => ()
    _ => fail("expected invalid path error")
  }
  assert_eq(@ion-patch.equal_values(expected[:], @ion.parse_text("1")[:]), true)
}

///|
test "checked apply does not return a partial result after a later error" {
  let expected = @ion.parse_text("{a: 1}")
  let current = @ion.parse_text("{a: 1}")
  let operations = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("2"),
    ),
    @ion-patch.PatchOp::InsertElement(
      @ion-patch.Path::root(0),
      0,
      @ion.parse_one_text("3"),
    ),
  ]
  let error = try
    @ion-patch.apply_checked(expected[:], current[:], operations[:])
  catch {
    error => error
  } noraise {
    _ => fail("expected wrong container")
  }
  match error {
    @ion-patch.PatchError::WrongContainer(_) => ()
    _ => fail("expected wrong container error")
  }
  assert_eq(
    @ion-patch.equal_values(current[:], @ion.parse_text("{a: 1}")[:]),
    true,
  )
}
