
test_that("Running stan() in parallel works",  {
  skip("Backwards compatibility + stan error")

  code <- "
  data {
    int N;
  } parameters {
    array[N] real y;
  }  model {
    y ~ normal(0, 1);
  }
  "
  N <- 3
  # D
  fit <- stan(model_code = code,
              data = "N",
              chains = 0,
              cores = 2,
              open_progress = FALSE)
  expect_true(fit@mode != 0)

  fit2 <- stan(fit = fit,
               data = "N",
               cores = 2,
               chains = 4,
               open_progress = FALSE)
  expect_true(fit2@mode == 0)
  expect_equal(fit2@sim$chains, 4L)

  # This should fail because check_data is false so that integer N cannot be
  # found.
  fit3 <- sampling(fit@stanmodel,
                   data = list(N = 2),
                   chains = 2,
                   check_data = FALSE,
                   iter = 40,
                   cores = 2,
                   open_progress = FALSE)
  expect_true(fit3@mode != 0)
})

test_that("stan() arguments works", {
  skip("Backwards compatibility")

  csv_fname <- "tsfa.csv"
  csv_fname2 <- "tsfa2.csv"
  diag_fname2 <- "diag2.csv"
  model_code <- "
    parameters {
      array[2] real y;
      real alpha;
    }
    transformed parameters {
      array[2, 2] real y2;
      y2[1, 1] = y[1];
      y2[1, 2] = -y[1];
      y2[2, 1] = -y[2];
      y2[2, 2] = y[2];
    }
    model {
      y ~ normal(0, 1);
    }
  "
  fit <- stan(model_code = model_code,
              iter = 100, chains = 1, thin = 3,
              sample_file = csv_fname)
  fit2 <- stan(fit = fit, iter = 1001, chains = 3, thin = 2,
               sample_file = csv_fname2, diagnostic_file = diag_fname2)
  fit3 <- stan(fit = fit, iter = 1001, chains = 3, thin = 2,
               control = list())
  fit4 <- stan(fit = fit, iter = 1001, chains = 3, thin = 2,
               control = list(adapt_gamma = .7))
  y_ii <- rnorm(2)
  fit5 <- stan(fit = fit, init = list(list(y = y_ii)), chains = 1, iter = 100)
  expect_equal(attr(fit2@sim$samples[[1]], "args")$iter, 1001)
  expect_equal(attr(fit2@sim$samples[[1]], "args")$control$adapt_delta, 0.8)
  expect_equal(attr(fit3@sim$samples[[1]], "args")$control$adapt_delta, 0.8)
  expect_equal(attr(fit4@sim$samples[[1]], "args")$control$adapt_gamma, 0.7)
  expect_equal(attr(fit5@sim$samples[[1]], "inits")[1:2], y_ii)

  fit6 <- stan(fit = fit, pars = "y", chains = 1, iter = 100)
  expect_equal(fit6@sim$pars_oi, c("y", "lp__"))

  fit6 <- stan(fit = fit, pars = c("y", "y2"), include = FALSE, chains = 1,
               iter = 100)
  expect_equal(fit6@sim$pars_oi, c("alpha", "lp__"))

  # Just test if we can specify refresh.
  fit7 <- stan(fit = fit, refresh = 10, chains = 1, iter = 100)
  fit8 <- stan(fit = fit, refresh = -1)

  csv_fname <- "tsfa*.csv"
  csv_fname2 <- "tsfa2*.csv"
  diag_fname2 <- "diag2*.csv"
  on.exit(system(paste('rm -rf ', csv_fname)), add = TRUE)
  on.exit(system(paste('rm -rf ', csv_fname2)), add = TRUE)
  on.exit(system(paste('rm -rf ', diag_fname2)), add = TRUE)
})
