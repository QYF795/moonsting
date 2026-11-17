///|
test "recorder: sorted ids and compression" {
  let ids : Array[Int32] = [603, 600, 601, 700]
  let sorted = @cov.sorted_seen_from(ids)
  assert_eq(@cov.format_ranges(@cov.ranges(sorted)), "600-601, 603, 700")
}

///|
test "recorder: gaps are the ids that were never hit" {
  let ids : Array[Int32] = [600, 601, 605, 606]
  assert_eq(@cov.format_ranges(@cov.gaps(ids)), "602-604")
  let contiguous : Array[Int32] = [600, 601, 602]
  assert_eq(@cov.format_ranges(@cov.gaps(contiguous)), "")
  let single : Array[Int32] = [600]
  assert_eq(@cov.format_ranges(@cov.gaps(single)), "")
}
