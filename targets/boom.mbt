///|
/// A deliberately crashing target: any input containing byte 0xDE aborts the
/// process. It exists to demonstrate (and test) crash isolation — the only way
/// to observe it is `--isolate`, because without it the abort takes the fuzzer
/// with it.
///
/// Kept in the catalog on purpose: a fuzzer whose crash path is never exercised
/// is a fuzzer whose crash path is broken. The README says plainly that
/// `--target boom` without `--isolate` will kill the process.
pub fn boom_body(input : Bytes) -> String {
  let mut i = 0
  while i < input.length() {
    if input[i].to_int() == 222 {
      abort("boom: the target died on byte 0xDE")
    }
    i = i + 1
  }
  "ok:" + input.length().to_string()
}

///|
pub fn boom_case() -> Case {
  let seeds : Array[Bytes] = [b"aaa", b"bbbb", b"ccccc", b"0"]
  Case::new(
    "boom",
    @core.Target::new("boom", seeds, boom_body),
    @core.Oracle::Same,
  )
}
