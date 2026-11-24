///|
fn pad(s : String, width : Int32) -> String {
  let sb = StringBuilder()
  sb.write_string(s)
  let mut i = s.length()
  while i < width {
    sb.write_char(' ')
    i = i + 1
  }
  sb.to_string()
}

///|
fn exec_rate(execs : Int32, ms : UInt64) -> Int32 {
  if ms == 0UL {
    execs
  } else {
    let micros = ms
    (execs.to_uint64() * 1000UL / micros).to_int()
  }
}

///|
/// The one-screen summary. Order is deliberate: target, throughput, corpus,
/// findings — the four questions a person asks after a run, in that order.
pub fn summary(session : @engine.Session) -> String {
  let stats = session.stats()
  let sb = StringBuilder()
  let case = session.case()
  sb.write_string(
    pad("target", 9) +
    ": " +
    case.name() +
    "  (oracle: " +
    case.oracle().label() +
    ")\n",
  )
  sb.write_string(
    pad("execs", 9) +
    ": " +
    stats.execs().to_string() +
    " in " +
    stats.elapsed_ms().to_string() +
    " ms  (" +
    exec_rate(stats.execs(), stats.elapsed_ms()).to_string() +
    " exec/s)\n",
  )
  sb.write_string(
    pad("corpus", 9) +
    ": " +
    session.corpus_size().to_string() +
    " entries, " +
    session.bucket_count().to_string() +
    " buckets, " +
    stats.novelty().to_string() +
    " novel inputs\n",
  )
  sb.write_string(
    pad("findings", 9) + ": " + stats.findings().to_string() + "\n",
  )
  let findings = session.findings()
  let mut i = 0
  while i < findings.length() {
    let f = findings[i]
    sb.write_string(
      "  [" +
      f.kind().label() +
      "] " +
      f.target() +
      "  input=" +
      @core.hex_of(f.input(), 24) +
      " (" +
      f.input().length().to_string() +
      "B)\n        " +
      @core.short(f.detail(), 160) +
      "\n",
    )
    i = i + 1
  }
  sb.to_string()
}

///|
/// One JSON object per finding. Kept on one line so the output can be piped
/// into `diff` between two backends or two runs.
pub fn json_line(f : @core.Finding) -> String {
  let sb = StringBuilder()
  sb.write_string("{")
  sb.write_string("\"kind\":\"" + f.kind().label() + "\"")
  sb.write_string(",\"target\":\"" + @core.escape_json(f.target()) + "\"")
  sb.write_string(",\"exec\":" + f.exec().to_string())
  sb.write_string(",\"input\":\"" + @core.hex_all(f.input()) + "\"")
  sb.write_string(
    ",\"ascii\":\"" + @core.escape_json(@core.ascii_of(f.input(), 64)) + "\"",
  )
  sb.write_string(",\"detail\":\"" + @core.escape_json(f.detail()) + "\"")
  sb.write_string("}\n")
  sb.to_string()
}

///|
pub fn jsonl(session : @engine.Session) -> String {
  let sb = StringBuilder()
  let findings = session.findings()
  let mut i = 0
  while i < findings.length() {
    sb.write_string(json_line(findings[i]))
    i = i + 1
  }
  sb.to_string()
}

///|
/// A MoonBit test the author can paste into their package. `expected` is the
/// value the oracle says is *correct*, so the test fails until the bug is
/// fixed — which is the point.
pub fn regression_test(f : @core.Finding) -> String {
  let sb = StringBuilder()
  sb.write_string("///|\n")
  sb.write_string(
    "test \"regress: " +
    f.target() +
    " #" +
    f.input().length().to_string() +
    "\" {\n",
  )
  sb.write_string(
    "  // found by moonsting at exec " + f.exec().to_string() + "\n",
  )
  sb.write_string("  // " + @core.short(f.detail(), 100) + "\n")
  sb.write_string(
    "  let input = @core.parse_hex(\"" + @core.hex_all(f.input()) + "\")\n",
  )
  sb.write_string("  // TODO: replace with the failing call\n")
  sb.write_string("  let output = " + f.target() + "(input)\n")
  sb.write_string("  assert_eq(output, \"<expected>\")\n")
  sb.write_string("}\n")
  sb.to_string()
}

///|
/// The corpus as hex lines, one input per line.
///
/// This is the persistence mechanism that does not need a filesystem: redirect
/// the output to a file, then replay it on the next run with `--seed-input`.
/// A run that found a deep state can therefore be resumed on a machine that
/// has no idea what a `corpus/` directory is.
pub fn corpus_dump(session : @engine.Session) -> String {
  let sb = StringBuilder()
  let inputs = session.corpus_inputs()
  let mut i = 0
  while i < inputs.length() {
    if inputs[i].length() > 0 {
      sb.write_string(@core.hex_all(inputs[i]))
      sb.write_string("\n")
    }
    i = i + 1
  }
  sb.to_string()
}

///|
fn html_escape(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let c = s.get_char(i).unwrap()
    if c == '<' {
      sb.write_string("&lt;")
    } else if c == '>' {
      sb.write_string("&gt;")
    } else if c == '&' {
      sb.write_string("&amp;")
    } else {
      sb.write_char(c)
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// Self-contained report. No external CSS, no fonts, no scripts: it has to open
/// from a downloaded artifact in a locked-down environment.
pub fn html(session : @engine.Session) -> String {
  let stats = session.stats()
  let sb = StringBuilder()
  sb.write_string("<!doctype html><html><head><meta charset=\"utf-8\">")
  sb.write_string(
    "<title>moonsting: " + html_escape(session.case().name()) + "</title>",
  )
  sb.write_string(
    "<style>body{font:14px/1.5 ui-monospace,Menlo,Consolas,monospace;margin:2rem;color:#111}" +
    "h1{font-size:18px}table{border-collapse:collapse;width:100%}" +
    "th,td{border-bottom:1px solid #ddd;padding:.4rem .6rem;text-align:left;vertical-align:top}" +
    "code{background:#f4f4f4;padding:.1rem .3rem}.k{color:#b00}</style></head><body>",
  )
  sb.write_string("<h1>moonsting report</h1>")
  sb.write_string(
    "<p>target <b>" +
    html_escape(session.case().name()) +
    "</b> &middot; oracle <code>" +
    html_escape(session.case().oracle().label()) +
    "</code></p>",
  )
  sb.write_string(
    "<p>execs " +
    stats.execs().to_string() +
    " &middot; " +
    exec_rate(stats.execs(), stats.elapsed_ms()).to_string() +
    " exec/s &middot; corpus " +
    session.corpus_size().to_string() +
    " &middot; buckets " +
    session.bucket_count().to_string() +
    " &middot; findings <span class=\"k\">" +
    stats.findings().to_string() +
    "</span></p>",
  )
  sb.write_string(
    "<table><tr><th>kind</th><th>exec</th><th>bytes</th><th>input (hex)</th><th>ascii</th><th>detail</th></tr>",
  )
  let findings = session.findings()
  let mut i = 0
  while i < findings.length() {
    let f = findings[i]
    sb.write_string("<tr>")
    sb.write_string("<td>" + html_escape(f.kind().label()) + "</td>")
    sb.write_string("<td>" + f.exec().to_string() + "</td>")
    sb.write_string("<td>" + f.input().length().to_string() + "</td>")
    sb.write_string(
      "<td><code>" + html_escape(@core.hex_all(f.input())) + "</code></td>",
    )
    sb.write_string(
      "<td><code>" + html_escape(@core.ascii_of(f.input(), 64)) + "</code></td>",
    )
    sb.write_string("<td>" + html_escape(f.detail()) + "</td>")
    sb.write_string("</tr>")
    i = i + 1
  }
  sb.write_string("</table></body></html>")
  sb.to_string()
}

///|
/// What the instrumentation saw, and — more useful — what it never took.
///
/// When the target declares the ids it assigned, a missing id means a branch no
/// input reached. Without declarations the report can only point at holes in the
/// observed span, which conflates "unreached" with "never assigned".
pub fn coverage_report(ids : Array[Int32]) -> String {
  if ids.length() == 0 {
    return "coverage : none (target is not instrumented)"
  }
  let sorted = @cov.sorted_seen_from(ids)
  let spans = @cov.ranges(sorted)
  let declared = @cov.declared_list()
  let sb = StringBuilder()
  sb.write_string(
    "coverage : " +
    sorted.length().to_string() +
    " ids hit (" +
    @cov.format_ranges(spans) +
    ")\n",
  )
  if declared.length() > 0 {
    let missing = @cov.unreached(sorted)
    if missing.length() == 0 {
      sb.write_string(
        "branches : all " +
        declared.length().to_string() +
        " declared ids were reached\n",
      )
    } else {
      sb.write_string(
        "unreached: " +
        @cov.format_ranges(@cov.ranges(missing)) +
        " (" +
        missing.length().to_string() +
        " of " +
        declared.length().to_string() +
        " declared branches never taken)\n",
      )
    }
    let stray = @cov.undeclared_hits(sorted)
    if stray.length() > 0 {
      sb.write_string(
        "warning  : hit ids that were never declared: " +
        @cov.format_ranges(@cov.ranges(stray)) +
        "\n",
      )
    }
  } else {
    let holes = @cov.gaps(sorted)
    if holes.length() == 0 {
      sb.write_string("gaps     : none inside the observed span\n")
    } else {
      sb.write_string(
        "gaps     : " +
        @cov.format_ranges(holes) +
        " (no declarations: could be unreached branches or unassigned ids)\n",
      )
    }
  }
  sb.to_string()
}

///|
/// One JSON line describing a `cmin` run, for machines.
pub fn cmin_line(
  before : Int32,
  kept : Int32,
  ids_covered : Int32,
  ids_total : Int32,
  out : String,
) -> String {
  "{\"kind\":\"cmin\",\"before\":" +
  before.to_string() +
  ",\"kept\":" +
  kept.to_string() +
  ",\"ids\":" +
  ids_covered.to_string() +
  ",\"ids_total\":" +
  ids_total.to_string() +
  ",\"out\":\"" +
  out +
  "\"}"
}
