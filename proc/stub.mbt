// Non-native fallbacks. Same API, no OS access: `supported()` is false and the
// callers (engine, CLI) degrade to in-process execution instead of failing.

///|
#cfg(not(target="native"))
pub fn supported() -> Bool {
  false
}

///|
#cfg(not(target="native"))
pub fn pid() -> Int32 {
  0
}

///|
#cfg(not(target="native"))
pub fn write_file(_path : String, _data : Bytes) -> Bool {
  false
}

///|
#cfg(not(target="native"))
pub fn read_file(_path : String) -> Bytes {
  b""
}

///|
#cfg(not(target="native"))
pub fn remove_file(_path : String) -> Unit {
  ()
}

///|
#cfg(not(target="native"))
pub fn run_command(_line : String) -> Int32 {
  -1
}

///|
#cfg(not(target="native"))
pub fn open_out(_path : String) -> Int64 {
  0L
}

///|
#cfg(not(target="native"))
pub fn put(_handle : Int64, _data : Bytes) -> Int32 {
  -1
}

///|
#cfg(not(target="native"))
pub fn flush(_handle : Int64) -> Unit {
  ()
}

///|
#cfg(not(target="native"))
pub fn close_out(_handle : Int64) -> Unit {
  ()
}
