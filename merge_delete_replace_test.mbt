///|
fn assert_delete_replacement_merge(
  base : Array[@model.IonValue],
  deletion : Array[@ion-patch.PatchOp],
  replacement : Array[@ion-patch.PatchOp],
  expected : Array[@model.IonValue],
) -> Unit raise Error {
  let snapshot = @ion-patch.apply(base[:], [])
  let combined = @ion-patch.merge(base[:], deletion[:], replacement[:])
  let swapped = @ion-patch.merge(base[:], replacement[:], deletion[:])
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
fn assert_delete_replacement_conflict(
  base : Array[@model.IonValue],
  deletion : Array[@ion-patch.PatchOp],
  replacement : Array[@ion-patch.PatchOp],
) -> Unit raise Error {
  let snapshot = @ion-patch.apply(base[:], [])
  let error = try @ion-patch.merge(base[:], deletion[:], replacement[:]) catch {
    error => error
  } noraise {
    _ => fail("expected merge conflict")
  }
  match error {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error")
  }
  let swapped = try
    @ion-patch.merge(base[:], replacement[:], deletion[:])
  catch {
    error => error
  } noraise {
    _ => fail("expected merge conflict after branch swap")
  }
  match swapped {
    @ion-patch.PatchError::Conflict(_) => ()
    _ => fail("expected conflict error after branch swap")
  }
  assert_eq(@ion-patch.equal_values(base[:], snapshot[:]), true)
}

///|
test "merge root deletion with independent replacement" {
  let base = @ion.parse_text("a b c d")
  let deletion = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(1)),
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(2)),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(2),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_delete_replacement_merge(
    base,
    deletion,
    replacement,
    @ion.parse_text("a z"),
  )
}

///|
test "merge deletion and replacement in list and s-expression" {
  let list = @ion.parse_text("[a, b, c]")
  let list_delete = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).element(1)),
  ]
  let list_replace = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0).element(2),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_delete_replacement_merge(
    list,
    list_delete,
    list_replace,
    @ion.parse_text("[a, z]"),
  )
  let sexp = @ion.parse_text("(a b c)")
  let sexp_delete = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).element(0)),
  ]
  let sexp_replace = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0).element(2),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_delete_replacement_merge(
    sexp,
    sexp_delete,
    sexp_replace,
    @ion.parse_text("(b z)"),
  )
}

///|
test "merge deletion and replacement below annotations" {
  let base = @ion.parse_text("tag::[a, b, c]")
  let container = @ion-patch.Path::root(0).annotated_value()
  let deletion = [@ion-patch.PatchOp::Remove(container.element(0))]
  let replacement = [
    @ion-patch.PatchOp::Replace(container.element(2), @ion.parse_one_text("z")),
  ]
  assert_delete_replacement_merge(
    base,
    deletion,
    replacement,
    @ion.parse_text("tag::[b, z]"),
  )
}

///|
test "merge deletion and replacement in duplicate SID fields" {
  let sid = @model.IonSymbol::from_sid(77)
  let x = @model.IonSymbol::from_text("x")
  let one = @ion.parse_one_text("1")
  let two = @ion.parse_one_text("2")
  let three = @ion.parse_one_text("3")
  let nine = @ion.parse_one_text("9")
  let base = [@model.IonValue::Struct([(sid, one), (x, two), (sid, three)])]
  let deletion = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).field(x, 0)),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(@ion-patch.Path::root(0).field(sid, 1), nine),
  ]
  let expected = [@model.IonValue::Struct([(sid, one), (sid, nine)])]
  assert_delete_replacement_merge(base, deletion, replacement, expected)
}

///|
test "merge deletion and replacement compares float bits" {
  let positive = @model.IonValue::Float(Float::reinterpret_from_int(0))
  let negative = @model.IonValue::Float(Float::reinterpret_from_int(0x80000000))
  let nan_one = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00001))
  let nan_two = @model.IonValue::Float(Float::reinterpret_from_int(0x7fc00002))
  let base = [@model.IonValue::List([positive, negative, nan_one])]
  let deletion = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(0).element(1)),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(@ion-patch.Path::root(0).element(2), nan_two),
  ]
  let expected = [@model.IonValue::List([positive, nan_two])]
  assert_delete_replacement_merge(base, deletion, replacement, expected)
}

///|
test "merge rejects replacement of deleted element" {
  let base = @ion.parse_text("a b c")
  let deletion = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(1))]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(1),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_delete_replacement_conflict(base, deletion, replacement)
}

///|
test "merge rejects ambiguous retained positions" {
  let base = @ion.parse_text("a a b")
  let deletion = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(0))]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(2),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_delete_replacement_conflict(base, deletion, replacement)
}

///|
test "merge rejects same-length delete-insert branch" {
  let base = @ion.parse_text("a b c")
  let deletion = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(0))]
  let other = [
    @ion-patch.PatchOp::Remove(@ion-patch.Path::root(1)),
    @ion-patch.PatchOp::InsertRoot(2, @ion.parse_one_text("z")),
  ]
  assert_delete_replacement_conflict(base, deletion, other)
}

///|
test "merge rejects replacement that changes struct field layout" {
  let base = @ion.parse_text("{a: 1, b: 2, c: 3}")
  let deletion = [
    @ion-patch.PatchOp::Remove(
      @ion-patch.Path::root(0).field(@model.IonSymbol::from_text("b"), 0),
    ),
  ]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("{a: 1, b: 2, d: 3}"),
    ),
  ]
  assert_delete_replacement_conflict(base, deletion, replacement)
}

///|
test "every deletion and independent replacement position merges" {
  let base = @ion.parse_text("a b c")
  let z = @ion.parse_one_text("z")
  for removed in 0..<base.length() {
    for replaced in 0..<base.length() {
      let deletion = [
        @ion-patch.PatchOp::Remove(@ion-patch.Path::root(removed)),
      ]
      let replacement = [
        @ion-patch.PatchOp::Replace(@ion-patch.Path::root(replaced), z),
      ]
      if removed == replaced {
        assert_delete_replacement_conflict(base, deletion, replacement)
      } else {
        let expected : Array[@model.IonValue] = []
        for index in 0..<base.length() {
          if index != removed {
            expected.push(if index == replaced { z } else { base[index] })
          }
        }
        assert_delete_replacement_merge(base, deletion, replacement, expected)
      }
    }
  }
}

///|
test "empty deletion result accepts only unchanged replacements" {
  let base = @ion.parse_text("a")
  let deletion = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(0))]
  let unchanged = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("a"),
    ),
  ]
  assert_delete_replacement_merge(base, deletion, unchanged, [])
  let changed = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(0),
      @ion.parse_one_text("z"),
    ),
  ]
  assert_delete_replacement_conflict(base, deletion, changed)
}

///|
test "merge deletion and replacement respects output limit" {
  let base = @ion.parse_text("a b c")
  let deletion = [@ion-patch.PatchOp::Remove(@ion-patch.Path::root(0))]
  let replacement = [
    @ion-patch.PatchOp::Replace(
      @ion-patch.Path::root(2),
      @ion.parse_one_text("z"),
    ),
  ]
  let limits = @ion-patch.PatchLimits::new(max_operations=1)
  let error = try
    @ion-patch.merge(base[:], deletion[:], replacement[:], limits~)
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
