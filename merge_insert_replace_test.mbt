///|
fn assert_insert_replacement_merge(
  base : Array[@model.IonValue],
  insertion : Array[@ion-patch.PatchOp],
  replacement : Array[@ion-patch.PatchOp],
  expected : Array[@model.IonValue],
) -> Unit raise Error {
  let snapshot = @ion-patch.apply(base[:], [])
  let combined = @ion-patch.merge(base[:], insertion[:], replacement[:])
  let swapped = @ion-patch.merge(base[:], replacement[:], insertion[:])
  assert_eq(combined.length(), swapped.length())
  for i in 0..<combined.length() {
    assert_eq(same_operation(combined[i], swapped[i]), true)
  }
  let actual = @ion-patch.apply(base[:], combined[:])
  assert_eq(@ion-patch.equal_values(actual[:], expected[:]), true)
  let reverse = @ion-patch.invert(base[:], combined[:])
  let restored = @ion-patch.apply(actual[:], reverse[:])
  assert_eq(@ion-patch.equal_values(restored[:], base[:]), true)
  assert_eq(@ion-patch.equal_values(base[:], snapshot[:]), true)
}

///|
test "merge root insertion with independent replacement" {
  let base = @ion.parse_text("a b c")
  let insertion = [
    @ion-patch.PatchOp::InsertRoot(0, @ion.parse_one_text("x")),
    @ion-patch.PatchOp::InsertRoot(3, @ion.parse_one_text("y")),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(1),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_insert_replacement_merge(
    base,
    insertion,
    replacement,
    @ion.parse_text("x a z y c"),
  )
}

///|
test "merge list and s-expression insertion with replacements" {
  let list = @ion.parse_text("[a, b, c]")
  let list_insert = [
    @ion-patch.PatchOp::InsertElement(
      @ion-patch.Path::root(0),
      1,
      @ion.parse_one_text("x"),
    ),
  ]
  let list_replace = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0).element(2),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_insert_replacement_merge(
    list,
    list_insert,
    list_replace,
    @ion.parse_text("[a, x, b, z]"),
  )
  let sexp = @ion.parse_text("(a b c)")
  let sexp_insert = [
    @ion-patch.PatchOp::InsertElement(
      @ion-patch.Path::root(0),
      2,
      @ion.parse_one_text("x"),
    ),
  ]
  let sexp_replace = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0).element(0),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_insert_replacement_merge(
    sexp,
    sexp_insert,
    sexp_replace,
    @ion.parse_text("(z b x c)"),
  )
}

///|
test "merge insertion with replacement below annotations" {
  let base = @ion.parse_text("tag::[a, b]")
  let container = @ion-patch.Path::root(0).annotated_value()
  let insertion = [
    @ion-patch.PatchOp::InsertElement(container, 1, @ion.parse_one_text("x")),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(container.element(1), @ion.parse_one_text("z")),
  ]
  assert_insert_replacement_merge(
    base,
    insertion,
    replacement,
    @ion.parse_text("tag::[a, x, z]"),
  )
}

///|
test "merge insertion with replacement in duplicate SID fields" {
  let sid = @model.IonSymbol::from_sid(77)
  let x = @model.IonSymbol::from_text("x")
  let y = @model.IonSymbol::from_text("y")
  let one = @ion.parse_one_text("1")
  let two = @ion.parse_one_text("2")
  let three = @ion.parse_one_text("3")
  let nine = @ion.parse_one_text("9")
  let base = [@model.IonValue::Struct([(sid, one), (x, two), (sid, three)])]
  let insertion = [
    @ion-patch.PatchOp::InsertField(@ion-patch.Path::root(0), 1, y, nine),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(@ion-patch.Path::root(0).field(sid, 1), nine),
  ]
  let expected = [
    @model.IonValue::Struct([(sid, one), (y, nine), (x, two), (sid, nine)]),
  ]
  assert_insert_replacement_merge(base, insertion, replacement, expected)
}

///|
test "merge insertion anchors compare float bits" {
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  let base = [@model.IonValue::List([positive, negative, nan_one])]
  let insertion = [
    @ion-patch.PatchOp::InsertElement(@ion-patch.Path::root(0), 1, nan_two),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(@ion-patch.Path::root(0).element(1), positive),
  ]
  let expected = [@model.IonValue::List([positive, nan_two, positive, nan_one])]
  assert_insert_replacement_merge(base, insertion, replacement, expected)
}

///|
test "merge insertion and replacement rejects ambiguous anchors" {
  let base = @ion.parse_text("a b")
  let insertion = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("a"))]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(1),
      @ion.parse_one_text("z"),
    ),
  ]
  let error = try
    @ion-patch.merge(base[:], insertion[:], replacement[:])
  catch {
    error => error
  } noraise {
    _ => fail("expected ambiguous anchor conflict")
  }
  match error {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error")
  }
}

///|
test "merge insertion and same-length delete-insert stays conservative" {
  let base = @ion.parse_text("a b c")
  let insertion = [@ion-patch.PatchOp::InsertRoot(0, @ion.parse_one_text("x"))]
  let other = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(1)),
    @ion-patch.PatchOp::InsertRoot(2, @ion.parse_one_text("z")),
  ]
  let error = try @ion-patch.merge(base[:], insertion[:], other[:]) catch {
    error => error
  } noraise {
    _ => fail("expected mixed edit conflict")
  }
  match error {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error")
  }
}

///|
test "merge insertion and replacement respects output limit" {
  let base = @ion.parse_text("a b c")
  let insertion = [@ion-patch.PatchOp::InsertRoot(1, @ion.parse_one_text("x"))]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(2),
      @ion.parse_one_text("z"),
    ),
  ]
  let limits = @ion-patch.PatchLimits::new(max_operations=1)
  let error = try
    @ion-patch.merge(base[:], insertion[:], replacement[:], limits~)
  catch {
    error => error
  } noraise {
    _ => fail("expected output operation limit")
  }
  match error {
    @ion-patch.PatchError::Limit(_) => ()
    _ => fail("expected limit error")
  }
}

///|
test "every insertion gap and replacement position merges symmetrically" {
  let base = @ion.parse_text("a b c")
  let x = @ion.parse_one_text("x")
  let z = @ion.parse_one_text("z")
  for gap in 0..<=base.length() {
    for replaced in 0..<base.length() {
      let insertion = [@ion-patch.PatchOp::InsertRoot(gap, x)]
      let replacement = [
        @ion-patch.PatchOp::Replace(@ion-patch.Path::root(replaced), z),
      ]
      let expected : Array[@model.IonValue] = []
      for index in 0..<=base.length() {
        if index == gap {
          expected.push(x)
        }
        if index < base.length() {
          expected.push(if index == replaced { z } else { base[index] })
        }
      }
      assert_insert_replacement_merge(base, insertion, replacement, expected)
    }
  }
}

///|
test "merge rejects replacement that changes struct field layout" {
  let base = @ion.parse_text("{a: 1, b: 2}")
  let insertion = [
    @ion-patch.PatchOp::InsertField(
      @ion-patch.Path::root(0),
      1,
      @model.IonSymbol::from_text("x"),
      @ion.parse_one_text("0"),
    ),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("{a: 1, c: 2}"),
    ),
  ]
  let error = try
    @ion-patch.merge(base[:], insertion[:], replacement[:])
  catch {
    error => error
  } noraise {
    _ => fail("expected field layout conflict")
  }
  match error {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error")
  }
}

///|
test "merge rejects replacement that changes annotations" {
  let base = @ion.parse_text("tag::[a, b]")
  let insertion = [
    @ion-patch.PatchOp::InsertElement(
      @ion-patch.Path::root(0).annotated_value(),
      1,
      @ion.parse_one_text("x"),
    ),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("other::[a, z]"),
    ),
  ]
  let error = try
    @ion-patch.merge(base[:], insertion[:], replacement[:])
  catch {
    error => error
  } noraise {
    _ => fail("expected annotation conflict")
  }
  match error {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error")
  }
}
