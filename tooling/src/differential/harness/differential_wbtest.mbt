///|
let binary_corpus : String =
  #|# mpfr-random-v1 mpfr=4.2.2 family=add seed=1 start=0 count=4
  #|1.add.0 add n 24 -126 127 a 0x1p0 0x1p-30 - 0 0x1p0 x
  #|1.add.1 add u 24 -126 127 a 0x1p0 0x1p-30 - 0 0x800001p-23 x
  #|1.add.2 add n 24 -126 127 a 0x1p0 0x1p-30 - 0 0x2p0 x
  #|1.add.3 mul n 24 -126 127 a 0x1p-100 0x1p-100 - 0 0x0p0 xu

///|
let decimal_corpus : String =
  #|-- libmpdec-random-v1 libmpdec=4.0.0 family=add seed=1 start=0 count=3
  #|version: 2.62
  #|extended: 1
  #|precision: 3
  #|rounding: half_even
  #|maxexponent: 99
  #|minexponent: -99
  #|clamp: 0
  #|d1.add.0 add 1.234 1.234 -> 2.47 Inexact Rounded
  #|precision: 3
  #|rounding: half_even
  #|maxexponent: 99
  #|minexponent: -99
  #|clamp: 0
  #|d1.add.1 add 1.234 1.234 -> 2.48 Inexact Rounded
  #|precision: 2
  #|rounding: down
  #|maxexponent: 99
  #|minexponent: -99
  #|clamp: 0
  #|d1.add.2 add 9.99 9.99 -> 19 Inexact Rounded

///|
// oracle: A
// source: batch sizes (3 then 1 of four rows) and ids written out; the corpus rows are written in the block: the first
//   three binary rows are 1 + 2^-30 at 24 bits (to nearest gives 1; rounding up gives 0x800001p-23 = 1 + 2^-23;
//   row 2 carries the wrong value 0x2p0 on purpose) and the fourth is 2^-100 * 2^-100, which underflows to 0 at
//   24 bits (all checked with Python Fractions in this review); the verdicts are written: rows 0, 1 and 3 agree,
//   row 2 differs
// shares: execute_batch runs the library on each row (the code under test); the expected texts are the corpus rows
test "a binary corpus splits into batches and runs every case" {
  let batches = split_corpus(binary_corpus, 3).unwrap()
  assert_eq(batches.length(), 2)
  assert_eq(batches[0].length(), 3)
  assert_eq(batches[1].length(), 1)
  assert_eq(batches[0].ids, ["1.add.0", "1.add.1", "1.add.2"])
  let first = execute_batch(batches[0]).unwrap()
  assert_eq(first[0], "")
  assert_eq(first[1], "")
  // the third row has a wrong expected value on purpose
  assert_true(first[2].length() > 0)
  assert_eq(execute_batch(batches[1]).unwrap(), [""])
}

///|
// oracle: A
// source: three rows written in the block with their own contexts: 1.234 + 1.234 = 2.468 is 2.47 at 3 digits half_even
//   (the row 2.48 is wrong on purpose), and 9.99 + 9.99 = 19.98 is 19 at 2 digits rounding down; verdicts
//   written (rows 0 and 2 agree, row 1 differs)
// shares: execute_batch runs the library on each row (the code under test)
test "a decTest corpus keeps each row with its own context" {
  let batches = split_corpus(decimal_corpus, 10).unwrap()
  assert_eq(batches.length(), 1)
  assert_eq(batches[0].ids, ["d1.add.0", "d1.add.1", "d1.add.2"])
  let messages = execute_batch(batches[0]).unwrap()
  assert_eq(messages[0], "")
  assert_true(messages[1].length() > 0)
  assert_eq(messages[2], "")
}

///|
// oracle: A
// source: the failing row of the written corpus is the third (1.add.2, wrong value on purpose); halving four rows down
//   to one takes 2 steps (4, 2, 1) and leaves that row, written out
// shares: halves and execute_batch (the code under test and the library run on the rows)
test "the shrinker halves a failing batch down to one case" {
  let batch = split_corpus(binary_corpus, 10).unwrap()[0]
  let mut current = batch
  let mut steps = 0
  while current.length() > 1 {
    let failing = halves(current).filter(half => {
      execute_batch(half).unwrap().any(message => message.length() > 0)
    })
    assert_true(failing.length() > 0)
    current = failing[0]
    steps += 1
  }
  assert_eq(current.ids, ["1.add.2"])
  assert_true(steps >= 2)
}

///|
// oracle: A
// source: verdicts written out: a text without a corpus header is not a corpus, and a batch size of 0 is invalid
// shares: nothing
test "a non-corpus file and a bad batch size are rejected" {
  assert_true(split_corpus("nothing here", 10) is Err(_))
  assert_true(split_corpus(binary_corpus, 0) is Err(_))
}

///|
// oracle: A
// source: the expected text is written out character by character: the count of differing cases out of the total, then
//   the id: message pairs joined by ' | '; an all-pass list reads 'all cases agree'
// shares: nothing
test "failure text names the first failing cases" {
  let text = failure_text(["a", "b", "c"], ["", "boom", "bang"])
  assert_eq(text, "2 of 3 cases differ; b: boom | c: bang")
  assert_eq(failure_text(["a"], [""]), "all cases agree")
}
