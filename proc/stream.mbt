// Streaming file output, for the worker's per-input result lines.
//
// The worker must leave a durable trace after *every* input: the whole point is
// that the next input may kill the process. That rules out "buffer and write at
// the end", so the API is deliberately handle-based (open once, put + flush per
// line, close at the end).

///|
#cfg(target="native")
extern "C" fn fflush(f : Int64) -> Int32 = "fflush"

///|
#cfg(target="native")
pub fn open_out(path : String) -> Int64 {
  fopen(cstr(path), b"wb\x00")
}

///|
#cfg(target="native")
pub fn put(handle : Int64, data : Bytes) -> Int32 {
  if handle == 0L {
    -1
  } else {
    fwrite(data, 1, data.length(), handle)
  }
}

///|
#cfg(target="native")
pub fn flush(handle : Int64) -> Unit {
  if handle != 0L {
    ignore(fflush(handle))
  }
}

///|
#cfg(target="native")
pub fn close_out(handle : Int64) -> Unit {
  if handle != 0L {
    ignore(fclose(handle))
  }
}
