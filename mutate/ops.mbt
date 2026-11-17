///|
fn min_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn truncate_to(data : Array[Byte], limit : Int32) -> Unit {
  while data.length() > limit && data.length() > 0 {
    pop(data)
  }
}

///|
fn Mutator::havoc(self : Mutator, data : Array[Byte]) -> Unit {
  let n = data.length()
  let roll = self.rng_.below(8)
  if roll == 0 {
    if n > 0 {
      let pos = self.rng_.below(n)
      let bit = self.rng_.below(8)
      data[pos] = (data[pos].to_int() ^ (1 << bit)).to_byte()
    }
  } else if roll == 1 {
    if n > 0 {
      data[self.rng_.below(n)] = self.rng_.next_interesting_byte()
    }
  } else if roll == 2 {
    if n < self.max_len_ {
      data.insert(self.rng_.below(n + 1), self.rng_.next_interesting_byte())
    }
  } else if roll == 3 {
    if n > 1 {
      let start = self.rng_.below(n)
      let len = 1 + self.rng_.below(min_int(16, n - start))
      let mut i = 0
      while i < len && start < data.length() {
        ignore(data.remove(start))
        i = i + 1
      }
    }
  } else if roll == 4 {
    if n > 0 && n < self.max_len_ {
      let start = self.rng_.below(n)
      let len = 1 + self.rng_.below(min_int(16, n - start))
      let copy : Array[Byte] = []
      let mut i = 0
      while i < len {
        copy.push(data[start + i])
        i = i + 1
      }
      let at = self.rng_.below(data.length() + 1)
      let mut j = 0
      while j < copy.length() && data.length() < self.max_len_ {
        data.insert(at + j, copy[j])
        j = j + 1
      }
    }
  } else if roll == 5 {
    if n > 1 {
      let a = self.rng_.below(n)
      let b = self.rng_.below(n)
      let tmp = data[a]
      data[a] = data[b]
      data[b] = tmp
    }
  } else if roll == 6 {
    if n > 2 {
      truncate_to(data, self.rng_.below(n))
    }
  } else if n > 0 {
    data[self.rng_.below(n)] = self.rng_.below(256).to_byte()
  }
}

///|
fn first_significant(data : Array[Byte]) -> Int32 {
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v != 32 && v != 9 && v != 10 && v != 13 {
      return i
    }
    i = i + 1
  }
  data.length()
}

///|
fn looks_json(data : Array[Byte]) -> Bool {
  let at = first_significant(data)
  if at >= data.length() {
    false
  } else {
    let v = data[at].to_int()
    v == 123 || v == 91 || v == 34
  }
}

///|
fn looks_csv(data : Array[Byte]) -> Bool {
  let mut commas = 0
  let mut newlines = 0
  let mut i = 0
  while i < data.length() {
    let v = data[i].to_int()
    if v == 44 {
      commas = commas + 1
    } else if v == 10 {
      newlines = newlines + 1
    }
    i = i + 1
  }
  commas + newlines > 0
}

///|
/// `(start, end)` of every double-quoted run, ignoring escaped quotes.
fn quoted_spans(data : Array[Byte]) -> Array[(Int32, Int32)] {
  let spans : Array[(Int32, Int32)] = []
  let mut i = 0
  while i < data.length() {
    if data[i].to_int() == 34 {
      let start = i
      let mut j = i + 1
      let mut closed = false
      while j < data.length() && !closed {
        let v = data[j].to_int()
        if v == 92 {
          j = j + 2
        } else if v == 34 {
          closed = true
        } else {
          j = j + 1
        }
      }
      let end = if j < data.length() { j + 1 } else { data.length() }
      spans.push((start, end))
      i = end
    } else {
      i = i + 1
    }
  }
  spans
}

///|
fn Mutator::structural(self : Mutator, data : Array[Byte]) -> Unit {
  if looks_json(data) {
    self.json_edit(data)
  } else if looks_csv(data) {
    self.csv_edit(data)
  } else {
    self.havoc(data)
  }
}

///|
fn Mutator::json_edit(self : Mutator, data : Array[Byte]) -> Unit {
  let roll = self.rng_.below(6)
  if roll == 0 && data.length() < self.max_len_ {
    let punct : Array[Byte] = [b'{', b'}', b'[', b']', b',', b':', b'"', b'\\']
    data.insert(
      self.rng_.below(data.length() + 1),
      punct[self.rng_.below(punct.length())],
    )
  } else if roll == 1 {
    if data.length() > 1 {
      truncate_to(data, self.rng_.below(data.length()))
    }
  } else if roll == 2 {
    let spans = quoted_spans(data)
    if spans.length() > 0 {
      let (start, end) = spans[self.rng_.below(spans.length())]
      let span = @core.slice_bytes(@core.bytes_of(data), start, end)
      if data.length() + span.length() < self.max_len_ {
        let at = self.rng_.below(data.length() + 1)
        let copy = @core.array_of(span)
        let mut i = 0
        while i < copy.length() {
          data.insert(at + i, copy[i])
          i = i + 1
        }
      }
    }
  } else if roll == 3 {
    // Walk into the middle of a string and break its quoting from the inside.
    let spans = quoted_spans(data)
    if spans.length() > 0 {
      let (start, end) = spans[self.rng_.below(spans.length())]
      if end - start > 2 {
        let at = start + 1 + self.rng_.below(end - start - 1)
        data[at] = b'"'
      }
    }
  } else if roll == 4 {
    if data.length() > 0 {
      let at = self.rng_.below(data.length())
      let v = data[at].to_int()
      if v >= 48 && v <= 57 {
        data[at] = (48 + self.rng_.below(10)).to_byte()
      } else {
        data[at] = self.rng_.next_interesting_byte()
      }
    }
  } else {
    self.dict_insert(data)
  }
}

///|
fn Mutator::csv_edit(self : Mutator, data : Array[Byte]) -> Unit {
  let roll = self.rng_.below(5)
  if roll == 0 && data.length() < self.max_len_ {
    let seps : Array[Byte] = [b',', b'"', b'\n', b'\r', b';', b'\t']
    data.insert(
      self.rng_.below(data.length() + 1),
      seps[self.rng_.below(seps.length())],
    )
  } else if roll == 1 {
    // Duplicate a whole record: the classic "row count off by one" trigger.
    if data.length() > 0 && data.length() < self.max_len_ {
      let at = self.rng_.below(data.length() + 1)
      let copy = @core.slice_bytes(@core.bytes_of(data), 0, data.length())
      let mut i = 0
      let pieces = @core.array_of(copy)
      while i < pieces.length() && data.length() < self.max_len_ {
        data.insert(at + i, pieces[i])
        i = i + 1
      }
    }
  } else if roll == 2 {
    if data.length() > 1 {
      truncate_to(data, self.rng_.below(data.length()))
    }
  } else if roll == 3 {
    if data.length() > 0 {
      data[self.rng_.below(data.length())] = b'"'
    }
  } else {
    self.dict_insert(data)
  }
}

///|
fn Mutator::dict_insert(self : Mutator, data : Array[Byte]) -> Unit {
  let token = self.take_token()
  if token.length() == 0 {
    return
  }
  if data.length() + token.length() >= self.max_len_ {
    return
  }
  let at = self.rng_.below(data.length() + 1)
  let mut i = 0
  while i < token.length() {
    data.insert(at + i, token[i])
    i = i + 1
  }
}

///|
fn Mutator::splice(
  self : Mutator,
  data : Array[Byte],
  corpus : Array[Bytes],
) -> Unit {
  if corpus.length() == 0 || data.length() == 0 {
    return
  }
  let other = corpus[self.rng_.below(corpus.length())]
  if other.length() == 0 {
    return
  }
  let cut_self = self.rng_.below(data.length())
  let cut_other = self.rng_.below(other.length())
  let head = @core.slice_bytes(@core.bytes_of(data), 0, cut_self)
  let tail = @core.slice_bytes(other, cut_other, other.length())
  let merged = @core.array_of(head + tail)
  truncate_to(merged, self.max_len_)
  // Replace `data` in place: callers hold the same array reference.
  truncate_to(data, 0)
  let mut i = 0
  while i < merged.length() {
    data.push(merged[i])
    i = i + 1
  }
}

///|
fn Mutator::boundary(self : Mutator, data : Array[Byte]) -> Unit {
  let roll = self.rng_.below(4)
  if roll == 0 {
    truncate_to(data, 0)
  } else if roll == 1 {
    truncate_to(data, 1)
  } else if roll == 2 {
    // Repeat the current content until the size limit is hit.
    if data.length() > 0 {
      let copy = @core.array_of(@core.bytes_of(data))
      while data.length() + copy.length() < self.max_len_ {
        let mut i = 0
        while i < copy.length() {
          data.push(copy[i])
          i = i + 1
        }
      }
    }
  } else if data.length() > 0 {
    // Long run of one byte: trips length-prefix and padding logic.
    let b = data[self.rng_.below(data.length())]
    truncate_to(data, 0)
    while data.length() < min_int(self.max_len_, 512) {
      data.push(b)
    }
  }
}
