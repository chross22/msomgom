test_that("padstr0 zero-pads to the target width", {
  expect_equal(padstr0(800, 6), "000800")
  expect_equal(padstr0(0, 6), "000000")
  expect_equal(padstr0(123456, 6), "123456")
})

test_that("padstr0 avoids the scientific-notation bug it was written to fix", {
  # as.character(200000) would give "2e+05"; formatC(..., format = "d") must not
  expect_equal(padstr0(200000, 6), "200000")
  expect_false(grepl("e", padstr0(200000, 6)))
})

test_that("padstr0 is vectorized", {
  expect_equal(padstr0(c(1, 22, 333), 4), c("0001", "0022", "0333"))
})
