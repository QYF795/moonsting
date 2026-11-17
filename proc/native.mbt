// The native implementation. Every extern is gated on the native target: on
// wasm-gc/js there is no C ABI to bind to, and the stubs in stub.mbt take over.

///|
#cfg(target="native")
#borrow(cmd)
extern "C" fn system(cmd : Bytes) -> Int32 = "system"

///|
#cfg(target="native")
#borrow(path, mode)
extern "C" fn fopen(path : Bytes, mode : Bytes) -> Int64 = "fopen"

///|
#cfg(target="native")
#borrow(data)
extern "C" fn fwrite(data : Bytes, size : Int32, n : Int32, f : Int64) -> Int32 = "fwrite"

///|
#cfg(target="native")
extern "C" fn fclose(f : Int64) -> Int32 = "fclose"

///|
#cfg(target="native")
extern "C" fn fgetc(f : Int64) -> Int32 = "fgetc"

///|
#cfg(target="native")
#borrow(path)
extern "C" fn remove(path : Bytes) -> Int32 = "remove"

///|
#cfg(target="native")
extern "C" fn getpid() -> Int32 = "getpid"

///|
#cfg(target="native")
pub fn supported() -> Bool {
  true
}

///|
#cfg(target="native")
pub fn pid() -> Int32 {
  getpid()
}

///|
#cfg(target="native")
pub fn write_file(path : String, data : Bytes) -> Bool {
  let f = fopen(cstr(path), b"wb\x00")
  if f == 0L {
    return false
  }
  let written = fwrite(data, 1, data.length(), f)
  ignore(fclose(f))
  written == data.length()
}

///|
/// Read a whole file. A 16 MiB guard keeps a runaway artifact from eating
/// memory; batches and result files are kilobytes, so hitting it means a bug.
#cfg(target="native")
pub fn read_file(path : String) -> Bytes {
  let f = fopen(cstr(path), b"rb\x00")
  if f == 0L {
    return b""
  }
  let out : Array[Byte] = []
  let mut c = fgetc(f)
  while c >= 0 && out.length() < 16 * 1024 * 1024 {
    out.push(c.to_byte())
    c = fgetc(f)
  }
  ignore(fclose(f))
  Bytes::from_array(out)
}

///|
#cfg(target="native")
pub fn remove_file(path : String) -> Unit {
  ignore(remove(cstr(path)))
}

///|
/// Run a command line, return its exit code. On POSIX `system` encodes the
/// wait status (exit code << 8); callers only distinguish zero from non-zero.
#cfg(target="native")
pub fn run_command(line : String) -> Int32 {
  system(cstr(line))
}
