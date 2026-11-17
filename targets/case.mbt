///|
/// A named target plus the oracle that judges it. The CLI registers a list of
/// these so `--target json` is all a user has to type.
pub struct Case {
  name_ : String
  target_ : @core.Target
  oracle_ : @core.Oracle
}

///|
pub fn Case::new(
  name : String,
  target : @core.Target,
  oracle : @core.Oracle,
) -> Case {
  { name_: name, target_: target, oracle_: oracle, }
}

///|
pub fn Case::name(self : Case) -> String {
  self.name_
}

///|
pub fn Case::target(self : Case) -> @core.Target {
  self.target_
}

///|
pub fn Case::oracle(self : Case) -> @core.Oracle {
  self.oracle_
}

///|
pub fn Case::seeds(self : Case) -> Array[Bytes] {
  self.target_.seeds()
}
