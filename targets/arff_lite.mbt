///|
/// ARFF (Weka) with a metamorphic property instead of a round trip.
///
/// ARFF has no canonical form worth reproducing byte for byte (comments,
/// whitespace, attribute ordering are all free), so byte round-tripping is the
/// wrong property here. What *must* hold is that a comment changes nothing:
///
///   summary(x) == summary(x + "\n% anything\n")
///
/// That is cheap, needs no emitter, and catches the classic comment bugs —
/// comment detection that only works at the start of a line, or data rows that
/// swallow a trailing comment.
///
/// Coverage ids for this target live in 530..559.

///|
struct ArffShape {
  relation : Bytes
  attributes : Int32
  rows : Int32
}

///|
fn arff_trim(data : Bytes, start : Int32, end : Int32) -> Bytes {
  let mut lo = start
  let mut hi = end
  while lo < hi {
    let v = data[lo].to_int()
    if v == 32 || v == 9 {
      lo = lo + 1
    } else {
      break
    }
  }
  while hi > lo {
    let v = data[hi - 1].to_int()
    if v == 32 || v == 9 || v == 13 {
      hi = hi - 1
    } else {
      break
    }
  }
  @core.slice_bytes(data, lo, hi)
}

///|
/// Summary of a document: relation name, attribute count, data-row count.
/// `None` on any structural error.
pub fn arff_parse(input : Bytes) -> ArffShape? {
  let n = input.length()
  let mut i = 0
  let mut relation : Bytes = b""
  let mut attributes = 0
  let mut rows = 0
  let mut in_data = false
  while i < n {
    // One line.
    let start = i
    while i < n && input[i].to_int() != 10 {
      i = i + 1
    }
    let line = arff_trim(input, start, i)
    if i < n {
      i = i + 1
    }
    if line.length() == 0 {
      continue
    }
    let first = line[0].to_int()
    if first == 37 {
      @cov.hit(530)
      continue
    }
    if !in_data {
      if first == 64 {
        // Directive.
        let upper = arff_upper_prefix(line)
        if upper.has_prefix("@RELATION") {
          @cov.hit(531)
          relation = arff_trim(line, 9, line.length())
          if relation.length() == 0 {
            @cov.hit(532)
            return None
          }
        } else if upper.has_prefix("@ATTRIBUTE") {
          @cov.hit(533)
          attributes = attributes + 1
        } else if upper.has_prefix("@DATA") {
          @cov.hit(534)
          if attributes == 0 {
            @cov.hit(535)
            return None
          }
          in_data = true
        } else {
          @cov.hit(536)
          return None
        }
      } else {
        // Rows before @data are not allowed.
        @cov.hit(537)
        return None
      }
    } else {
      // A data row: the cell count must match the declared attributes.
      if arff_cell_count(line) != attributes {
        @cov.hit(538)
        return None
      }
      rows = rows + 1
      @cov.hit(539)
    }
  }
  if !in_data {
    @cov.hit(540)
    return None
  }
  Some({ relation, attributes, rows, })
}

///|
fn arff_upper_prefix(line : Bytes) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < line.length() && i < 12 {
    let v = line[i].to_int()
    if v >= 97 && v <= 122 {
      sb.write_char((v - 32).to_byte().to_char())
    } else {
      sb.write_char(line[i].to_char())
    }
    i = i + 1
  }
  sb.to_string()
}

///|
fn arff_cell_count(line : Bytes) -> Int32 {
  let mut count = 1
  let mut i = 0
  let mut quoted = false
  while i < line.length() {
    let v = line[i].to_int()
    if v == 34 {
      quoted = !quoted
    } else if v == 44 && !quoted {
      count = count + 1
    }
    i = i + 1
  }
  count
}

///|
pub fn arff_summary(input : Bytes) -> String {
  match arff_parse(input) {
    None => "err"
    Some(shape) => {
      @cov.hit(550)
      "ok:" +
      @core.hex_all(shape.relation) +
      ":" +
      shape.attributes.to_string() +
      "x" +
      shape.rows.to_string()
    }
  }
}

///|
/// A comment must not change the summary. The appended text always starts on a
/// fresh line, so the only way it can change anything is a parsing bug.
pub fn arff_comment_invariant(input : Bytes, output : String) -> String {
  let padded = input + b"\n% moonsting comment\n"
  let after = arff_summary(padded)
  if after == output {
    ""
  } else {
    "comment changed the summary: " + output + " -> " + after
  }
}
