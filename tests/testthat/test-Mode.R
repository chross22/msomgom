test_that("Mode returns the most frequent value", {
  expect_equal(Mode(c(1, 2, 2, 3)), 2)
  expect_equal(Mode(c("a", "b", "b", "b", "c")), "b")
})

test_that("Mode with a tie returns the first-occurring value", {
  # unique() preserves first-occurrence order, matching which.max()'s
  # first-index-wins tie-breaking
  expect_equal(Mode(c(2, 1, 1, 2)), 2)
})

test_that("Mode's na.rm argument works as documented", {
  expect_true(is.na(Mode(c(1, 1, NA, NA, NA))))
  expect_equal(Mode(c(1, 1, NA, NA, NA), na.rm = TRUE), 1)
})
