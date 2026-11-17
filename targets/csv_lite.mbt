///|
/// CSV shape analysis: record count, column count and the longest field.
///
/// Instrumented with `@cov.hit`: every state transition of the scanner reports
/// an id, which is what lets the fuzzer tell "a quoted field ended here" apart
/// from "a comma appeared here" even when the summary output is identical.
/// Uninstrumented targets fall back to shape-based feedback, so this is an
/// optimization, not a requirement (`json.lite` and `decimal.money` deliberately
/// stay uninstrumented as the control group).
///
/// Coverage ids for this target live in 200..219.

///|
pub fn csv_stats(input : Bytes) -> String {
  let n = input.length()
  let mut i = 0
  let mut rows = 0
  let mut cols_here = 0
  let mut max_cols = 0
  let mut field = 0
  let mut max_field = 0
  let mut in_quotes = false
  let mut closed = false
  let mut any = false
  while i < n {
    let v = input[i].to_int()
    any = true
    if closed {
      if v != 44 && v != 10 && v != 13 {
        @cov.hit(207)
        return "err:trailing@" + i.to_string()
      }
      closed = false
    }
    if in_quotes {
      if v == 34 {
        if i + 1 < n && data_at(input, i + 1) == 34 {
          @cov.hit(205)
          field = field + 1
          i = i + 2
        } else {
          @cov.hit(206)
          in_quotes = false
          closed = true
          i = i + 1
        }
      } else {
        field = field + 1
        i = i + 1
      }
    } else if v == 34 {
      if field > 0 {
        @cov.hit(208)
        return "err:quote@" + i.to_string()
      }
      @cov.hit(200)
      in_quotes = true
      i = i + 1
    } else if v == 44 {
      @cov.hit(202)
      cols_here = cols_here + 1
      max_field = max_of(max_field, field)
      field = 0
      i = i + 1
    } else if v == 10 {
      @cov.hit(203)
      rows = rows + 1
      cols_here = cols_here + 1
      max_cols = max_of(max_cols, cols_here)
      max_field = max_of(max_field, field)
      cols_here = 0
      field = 0
      i = i + 1
    } else if v == 13 {
      @cov.hit(204)
      i = i + 1
    } else {
      field = field + 1
      i = i + 1
    }
  }
  if in_quotes {
    @cov.hit(209)
    return "err:unterminated@" + i.to_string()
  }
  if any {
    if cols_here > 0 || field > 0 {
      rows = rows + 1
      cols_here = cols_here + 1
      max_cols = max_of(max_cols, cols_here)
      max_field = max_of(max_field, field)
    }
  }
  @cov.hit(210)
  "rows=" +
  rows.to_string() +
  ";cols=" +
  max_cols.to_string() +
  ";max=" +
  max_field.to_string()
}

///|
fn data_at(data : Bytes, i : Int32) -> Int32 {
  data[i].to_int()
}

///|
fn max_of(a : Int32, b : Int32) -> Int32 {
  if a > b {
    a
  } else {
    b
  }
}
