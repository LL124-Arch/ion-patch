///|
/// Compare complete Ion model values. The derived equality on Float follows
/// numeric equality, which loses signed zero and NaN payload distinctions.
pub fn equal_value(left : @model.IonValue, right : @model.IonValue) -> Bool {
  match (left, right) {
    (@model.IonValue::Float(a), @model.IonValue::Float(b)) =>
      a.reinterpret_as_int() == b.reinterpret_as_int()
    (@model.IonValue::List(a), @model.IonValue::List(b)) =>
      equal_values(a[:], b[:])
    (@model.IonValue::Sexp(a), @model.IonValue::Sexp(b)) =>
      equal_values(a[:], b[:])
    (@model.IonValue::Struct(a), @model.IonValue::Struct(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if a[i].0 != b[i].0 || !equal_value(a[i].1, b[i].1) {
          return false
        }
      }
      true
    }
    (
      @model.IonValue::Annotated(a_symbols, a_value),
      @model.IonValue::Annotated(b_symbols, b_value),
    ) => {
      if a_symbols != b_symbols {
        return false
      }
      equal_value(a_value, b_value)
    }
    _ => left == right
  }
}

///|
pub fn equal_values(
  left : ArrayView[@model.IonValue],
  right : ArrayView[@model.IonValue],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i in 0..<left.length() {
    if !equal_value(left[i], right[i]) {
      return false
    }
  }
  true
}

///|
fn clone_values(values : ArrayView[@model.IonValue]) -> Array[@model.IonValue] {
  let copied : Array[@model.IonValue] = []
  for value in values {
    copied.push(clone_value(value))
  }
  copied
}

///|
fn clone_value(value : @model.IonValue) -> @model.IonValue {
  match value {
    @model.IonValue::List(elements) =>
      @model.IonValue::List(clone_values(elements[:]))
    @model.IonValue::Sexp(elements) =>
      @model.IonValue::Sexp(clone_values(elements[:]))
    @model.IonValue::Struct(fields) => {
      let copied : Array[(@model.IonSymbol, @model.IonValue)] = []
      for field in fields {
        copied.push((field.0, clone_value(field.1)))
      }
      @model.IonValue::Struct(copied)
    }
    @model.IonValue::Annotated(symbols, inner) => {
      let copied : Array[@model.IonSymbol] = []
      for symbol in symbols {
        copied.push(symbol)
      }
      @model.IonValue::Annotated(copied, clone_value(inner))
    }
    @model.IonValue::Blob(bytes) =>
      @model.IonValue::Blob(Bytes::from_array(bytes.to_array()[:]))
    @model.IonValue::Clob(bytes) =>
      @model.IonValue::Clob(Bytes::from_array(bytes.to_array()[:]))
    _ => value
  }
}
