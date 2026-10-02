///|
fn same_path(a : @ion-patch.Path, b : @ion-patch.Path) -> Bool {
  if a.root != b.root || a.segments.length() != b.segments.length() {
    return false
  }
  for i in 0..<a.segments.length() {
    match (a.segments[i], b.segments[i]) {
      (@ion-patch.PathSegment::Element(x), @ion-patch.PathSegment::Element(y)) =>
        if x != y {
          return false
        }
      (@ion-patch.PathSegment::Field(x, n), @ion-patch.PathSegment::Field(y, m)) =>
        if x != y || n != m {
          return false
        }
      _ => return false
    }
  }
  true
}

///|
fn same_operation(a : @ion-patch.PatchOp, b : @ion-patch.PatchOp) -> Bool {
  match (a, b) {
    (
      @ion-patch.PatchOp::InsertRoot(ai, av),
      @ion-patch.PatchOp::InsertRoot(bi, bv),
    ) => ai == bi && @ion-patch.equal_value(av, bv)
    (
      @ion-patch.PatchOp::InsertElement(ap, ai, av),
      @ion-patch.PatchOp::InsertElement(bp, bi, bv),
    ) => same_path(ap, bp) && ai == bi && @ion-patch.equal_value(av, bv)
    (
      @ion-patch.PatchOp::InsertField(ap, ai, an, av),
      @ion-patch.PatchOp::InsertField(bp, bi, bn, bv),
    ) =>
      same_path(ap, bp) &&
      ai == bi &&
      an == bn &&
      @ion-patch.equal_value(av, bv)
    (@ion-patch.PatchOp::Remove(ap), @ion-patch.PatchOp::Remove(bp)) =>
      same_path(ap, bp)
    (@ion-patch.PatchOp::Replace(ap, av), @ion-patch.PatchOp::Replace(bp, bv)) =>
      same_path(ap, bp) && @ion-patch.equal_value(av, bv)
    _ => false
  }
}

///|
fn assert_patch_roundtrip(
  before : Array[@model.IonValue],
  after : Array[@model.IonValue],
) -> Unit raise Error {
  let operations = @ion-patch.diff(before[:], after[:])
  let again = @ion-patch.diff(before[:], after[:])
  assert_eq(operations.length(), again.length())
  for i in 0..<operations.length() {
    assert_eq(same_operation(operations[i], again[i]), true)
  }
  let actual = @ion-patch.apply(before[:], operations[:])
  assert_eq(@ion-patch.equal_values(actual[:], after[:]), true)
  let reverse = @ion-patch.invert(before[:], operations[:])
  let restored = @ion-patch.apply(actual[:], reverse[:])
  assert_eq(@ion-patch.equal_values(restored[:], before[:]), true)
}

///|
test "ordered structs, duplicate fields, annotations and containers round trip" {
  let before = @ion.parse_text(
    "{a: 1, a: [2, (3 4)], b: note::null.int} [true, false]",
  )
  let after = @ion.parse_text(
    "{a: 1, a: [2, (3 5), 6], c: note::null.string} [false] new::7",
  )
  assert_patch_roundtrip(before, after)
}

///|
test "duplicate field paths count full symbols and preserve insertion order" {
  let text = @model.IonSymbol::from_text("name")
  let sid = @model.IonSymbol::from_sid(42)
  let one = @ion.parse_one_text("1")
  let two = @ion.parse_one_text("2")
  let three = @ion.parse_one_text("3")
  let before = [
    @model.IonValue::Struct([(text, one), (sid, two), (text, three)]),
  ]
  let operations = [
    @ion-patch.PatchOp::Replace(@ion-patch.Path::root(0).field(text, 1), two),
    @ion-patch.PatchOp::InsertField(@ion-patch.Path::root(0), 1, text, three),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).field(sid, 0)),
  ]
  let expected = [
    @model.IonValue::Struct([(text, one), (text, three), (text, two)]),
  ]
  let actual = @ion-patch.apply(before[:], operations[:])
  assert_eq(@ion-patch.equal_values(actual[:], expected[:]), true)
  assert_eq(@ion-patch.equal_values(before[:], expected[:]), false)
  assert_patch_roundtrip(before, actual)
}

///|
test "document, list and s-expression inserts are positional" {
  let before = @ion.parse_text("[1, 3] (a c)")
  let two = @ion.parse_one_text("2")
  let b = @ion.parse_one_text("b")
  let tail = @ion.parse_one_text("tail")
  let operations = [
    @ion-patch.PatchOp::InsertElement(@ion-patch.Path::root(0), 1, two),
    @ion-patch.PatchOp::InsertElement(@ion-patch.Path::root(1), 1, b),
    @ion-patch.PatchOp::InsertRoot(2, tail),
  ]
  let actual = @ion-patch.apply(before[:], operations[:])
  let expected = @ion.parse_text("[1, 2, 3] (a b c) tail")
  assert_eq(@ion-patch.equal_values(actual[:], expected[:]), true)
  assert_patch_roundtrip(before, expected)
}

///|
test "signed zero and NaN payloads are compared by bits" {
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  assert_eq(@ion-patch.equal_value(positive, negative), false)
  assert_eq(@ion-patch.equal_value(nan_one, nan_two), false)
  assert_patch_roundtrip([positive, nan_one], [negative, nan_two])
}

///|
test "unknown SID and annotation order are exact" {
  let unknown = @model.IonSymbol::from_sid(999)
  let named = @model.IonSymbol::from_text("tag")
  let value = @model.IonValue::Symbol(unknown)
  let before = [@model.IonValue::Annotated([unknown, named], value)]
  let after = [@model.IonValue::Annotated([named, unknown], value)]
  assert_patch_roundtrip(before, after)
  assert_eq(@ion-patch.equal_values(before[:], after[:]), false)
}

///|
test "scalar Ion kinds and binary payloads retain exact values" {
  let before = @ion.parse_text(
    "null.blob 1.20d0 2024-01-02T03:04:05Z {{AQID}} {{\"abc\"}}",
  )
  let after = @ion.parse_text(
    "null.clob 1.2d0 2024-01-02T03:04:06Z {{AQIE}} {{\"abd\"}}",
  )
  assert_patch_roundtrip(before, after)
}

///|
test "invalid paths and wrong containers fail without changing the input" {
  let before = @ion.parse_text("{a: [1, 2]}")
  let a = @model.IonSymbol::from_text("a")
  let missing = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).field(a, 1)),
  ]
  let error = try @ion-patch.apply(before[:], missing[:]) catch {
    error => error
  } noraise {
    _ => fail("expected missing field error")
  }
  match error {
    @ion-patch.PatchError::InvalidPath(_) => ()
    _ => fail("expected invalid path")
  }
  let wrong = [
    @ion-patch.PatchOp::InsertField(
      @ion-patch.Path::root(0).field(a, 0),
      0,
      a,
      @ion.parse_one_text("3"),
    ),
  ]
  let error = try @ion-patch.apply(before[:], wrong[:]) catch {
    error => error
  } noraise {
    _ => fail("expected wrong container error")
  }
  match error {
    @ion-patch.PatchError::WrongContainer(_) => ()
    _ => fail("expected wrong container")
  }
  let expected = @ion.parse_text("{a: [1, 2]}")
  assert_eq(@ion-patch.equal_values(before[:], expected[:]), true)
}

///|
test "operation, path and Ion value limits are enforced" {
  let before = @ion.parse_text("[1]")
  let after = @ion.parse_text("[2]")
  let zero_ops = @ion-patch.PatchLimits::new(max_operations=0)
  let diff_error = try
    @ion-patch.diff(before[:], after[:], limits=zero_ops)
  catch {
    error => error
  } noraise {
    _ => fail("expected operation limit")
  }
  match diff_error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let path_limits = @ion-patch.PatchLimits::new(max_path_depth=0)
  let edits = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).element(0))]
  let path_error = try
    @ion-patch.apply(before[:], edits[:], limits=path_limits)
  catch {
    error => error
  } noraise {
    _ => fail("expected path depth limit")
  }
  match path_error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
  let value_limits = @ion-patch.PatchLimits::new(
    value_limits=@model.Limits::new(max_values=1),
  )
  let value_error = try
    @ion-patch.apply(before[:], [], limits=value_limits)
  catch {
    error => error
  } noraise {
    _ => fail("expected Ion value limit")
  }
  match value_error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
}

///|
test "diff falls back when a valid intermediate document exceeds value limits" {
  let before = @ion.parse_text("[1, 2, 3] 0")
  let after = @ion.parse_text("0 [1, 2, 3]")
  let limits = @ion-patch.PatchLimits::new(
    value_limits=@model.Limits::new(max_values=5),
  )
  let operations = @ion-patch.diff(before[:], after[:], limits~)
  assert_eq(operations.length(), 4)
  let actual = @ion-patch.apply(before[:], operations[:], limits~)
  assert_eq(@ion-patch.equal_values(actual[:], after[:]), true)
}

///|
test "diff replaces a container at the configured path depth" {
  let before = @ion.parse_text("[1]")
  let after = @ion.parse_text("[2]")
  let limits = @ion-patch.PatchLimits::new(max_path_depth=0)
  let operations = @ion-patch.diff(before[:], after[:], limits~)
  assert_eq(operations.length(), 1)
  let actual = @ion-patch.apply(before[:], operations[:], limits~)
  assert_eq(@ion-patch.equal_values(actual[:], after[:]), true)
}

///|
test "diff can use a whole-document patch under a small operation budget" {
  let before = @ion.parse_text("[1, 2, 3]")
  let after = @ion.parse_text("[4, 5, 6]")
  let limits = @ion-patch.PatchLimits::new(max_operations=2)
  let operations = @ion-patch.diff(before[:], after[:], limits~)
  assert_eq(operations.length(), 2)
  let actual = @ion-patch.apply(before[:], operations[:], limits~)
  assert_eq(@ion-patch.equal_values(actual[:], after[:]), true)
}

///|
test "later operation failure leaves caller document intact" {
  let original = @ion.parse_text("1 2")
  let operations = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("3"),
    ),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(9)),
  ]
  let error = try @ion-patch.apply(original[:], operations[:]) catch {
    error => error
  } noraise {
    _ => fail("expected invalid path")
  }
  match error {
    @ion-patch.PatchError::InvalidPath(_) => ()
    _ => fail("expected invalid path")
  }
  let expected = @ion.parse_text("1 2")
  assert_eq(@ion-patch.equal_values(original[:], expected[:]), true)
}

///|
test "result containers do not share mutable arrays with inputs" {
  let source = @ion.parse_text("[1]")
  let inserted = @ion.parse_one_text("[2]")
  let operations = [
    @ion-patch.PatchOp::InsertElement(@ion-patch.Path::root(0), 1, inserted),
  ]
  let result = @ion-patch.apply(source[:], operations[:])
  match source[0] {
    @model.IonValue::List(items) => items.push(@ion.parse_one_text("3"))
    _ => fail("expected list")
  }
  match inserted {
    @model.IonValue::List(items) => items.push(@ion.parse_one_text("4"))
    _ => fail("expected list")
  }
  let expected = @ion.parse_text("[1, [2]]")
  assert_eq(@ion-patch.equal_values(result[:], expected[:]), true)
}

///|
test "deterministic diff covers empty and mixed documents" {
  let documents = [
    [],
    @ion.parse_text("1"),
    @ion.parse_text("1 2"),
    @ion.parse_text("[1, 2]"),
    @ion.parse_text("{a: 1, a: 2}"),
    @ion.parse_text("(a c)"),
  ]
  for before in documents {
    for after in documents {
      assert_patch_roundtrip(before, after)
    }
  }
}
