test_that("outputing csv and extracting work", {
  skip("Backwards compatibility")

  csv_fname <- "teststanfit.csv"
  model_code <- "
    transformed data {
      int n;
      n = 0;
    }
    parameters {
      array[2] real y;
      array[n] real zeroleny;
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
    generated quantities {
      array[3, 2, 3] real y3;
      y3[1,1,1] = 1;   y3[1,1,2] = 2;   y3[1,1,3] = 3;
      y3[1,2,1] = 4;   y3[1,2,2] = 5;   y3[1,2,3] = 6;
      y3[2,1,1] = 7;   y3[2,1,2] = 8;   y3[2,1,3] = 9;
      y3[2,2,1] = 10;  y3[2,2,2] = 11;  y3[2,2,3] = 12;
      y3[3,1,1] = 13;  y3[3,1,2] = 14;  y3[3,1,3] = 15;
      y3[3,2,1] = 16;  y3[3,2,2] = 17;  y3[3,2,3] = 18;
    }
  "

  fit <- stan(model_code = model_code,
              iter = 100, chains = 1, thin = 3,
              sample_file = csv_fname)

  pmean <- get_posterior_mean(fit)[ ,1]
  pmean2 <- summary(fit)$c_summary[ , "mean", 1]
  expect_equal(pmean, pmean2, tolerance = 0.00001)

  expect_true(file.exists(csv_fname))
  d <- read.csv(file = csv_fname, comment.char = '#',
                header = TRUE)
  y_names <- paste0("y.", 1:2)
  cat2 <- function(a, b) paste0(a, ".", b)
  y2_names <- paste0("y2.", t(outer(1:2, 1:2, cat2)))
  y3_names <- paste0("y3.", t(outer(as.vector(t(outer(1:3, 1:2, cat2))), 1:3, cat2)))

  dfit <- as.data.frame(fit)
  iter1 <- unlist(d[1,])
  names(iter1) <-  sqrfnames_to_dotfnames(names(iter1))
  expect_equal(iter1["y.1"], iter1["y2.1.1"], ignore_attr = "names")
  expect_equal(iter1["y.1"], -iter1["y2.1.2"], ignore_attr = "names")
  expect_equal(iter1["y.2"], iter1["y2.2.2"], ignore_attr = "names")
  expect_equal(iter1["y.2"], -iter1["y2.2.1"], ignore_attr = "names")
  expect_equal(iter1[y3_names], 1:18, ignore_attr = "names")

  # FIXME Uncomment the following line:
  #expect_equal(colnames(d), c("lp__", "treedepth__", "stepsize__", y_names, y2_names, y3_names))

  iter1 <- unlist(d[1,])
  # to check if the order is also row-major
  expect_equal(iter1["y.1"], iter1["y2.1.1"], ignore_attr = "names")
  expect_equal(iter1["y.1"], -iter1["y2.1.2"], ignore_attr = "names")
  expect_equal(iter1["y.2"], iter1["y2.2.2"], ignore_attr = "names")
  expect_equal(iter1["y.2"], -iter1["y2.2.1"], ignore_attr = "names")
  expect_equal(iter1[y3_names], 1:18, ignore_attr = "names")

  fit2 <- read_stan_csv(csv_fname)
  expect_equal(is_sf_valid(fit), TRUE)
  expect_equal(is_sf_valid(fit2), FALSE)
  fit2_m <- as.vector(get_posterior_mean(fit2))
  fit2_m2 <- summary(fit2)$summary[,"mean"]
  expect_equal(fit2_m, fit2_m2, ignore_attr = "names")
  unlink(csv_fname)

  # test extract
  fitb <- stan(fit = fit, iter = 105, warmup = 100, chains = 3, thin = 3)
  e1 <- extract(fitb)
  expect_equal(e1$y3[1,1,1,1], 1)
  expect_equal(e1$y3[1,2,2,2], 11)
  expect_equal(e1$y3[1,2,1,2], 8)
  expect_equal(e1$y3[1,3,1,2], 14)

  m1 <- as.matrix(fitb, pars = "y3")
  expect_equal(dim(m1), c(6L, 18L))
  old_asmatrix_stanfit <- function(x, ...) {
    if (x@mode != 0) return(numeric(0))
    e <- extract(x, permuted = FALSE, inc_warmup = FALSE, ...)
    out <- apply(e, 3, FUN = function(y) y)
    if (length(dim(out)) < 2L) out <- t(as.matrix(out))
    dimnames(out) <- dimnames(e)[-2]
    return(out)
  }
  expect_true(identical(m1, old_asmatrix_stanfit(fitb, pars = 'y3')))
  m2 <- as.matrix(fitb)
  expect_true(identical(m2, old_asmatrix_stanfit(fitb)))
})

test_that("init zero gradient fails", {
  skip("Backwards compatibility + error")

  code <- "
    parameters {
      real x;
    }
    model {
      x ~ normal(0, -1);
    }
  "
  sm <- stan_model(model_code = code)
  mod <- sm@dso@.CXXDSOMISC$module
  model_cppname <- sm@model_cpp$model_cppname
  sf_mod <- eval(call("$", mod, paste0('stan_fit4', model_cppname)))
  dat <- list()
  # FIXME: This errors. (No valid constructor)
  sampler <- new(sf_mod, dat, 12345, sm@dso@.CXXDSOMISC$cxxfun)
  args <- list(init = "0", iter = 1)
  expect_error({s <- sampler$call_sampler(args)})
  errmsg <- geterrmessage()
  #expect_true(grepl('.*Rejecting initial value.*', errmsg))
  expect_true(grepl("Error", errmsg))
})

test_that("init zero throws exception for infinite lp", {
  skip("Backwards compatibility + error")
  code <- "
    parameters {
      real x;
    }
    model {
      target += 1 / x;
    }
  "
  sm <- stan_model(model_code = code)
  mod <- sm@dso@.CXXDSOMISC$module
  model_cppname <- sm@model_cpp$model_cppname
  sf_mod <- eval(call("$", mod, paste0('stan_fit4', model_cppname)))
  dat <- list()
  # FIXME: This errors (No valid constructor)
  sampler <- new(sf_mod, dat, 12345, sm@dso@.CXXDSOMISC$cxxfun)
  args <- list(init = "0", iter = 1)
  expect_error({s <- sampler$call_sampler(args)})
  errmsg <- geterrmessage()
  #expect_true(grepl('.*negative infinity.*', errmsg))
  expect_true(grepl("Error", errmsg))
})

test_that("init zero throws exception for infinite gradient", {
  skip("Backwards compatibility + error")

  code <- "
    parameters {
      real x;
    }
    model {
      target += 1 / log(x);
    }
  "
  sm <- stan_model(model_code = code)
  mod <- sm@dso@.CXXDSOMISC$module
  model_cppname <- sm@model_cpp$model_cppname
  sf_mod <- eval(call("$", mod, paste0('stan_fit4', model_cppname)))
  dat <- list()
  # FIXME: This errors (No valid constructor)
  sampler <- new(sf_mod, dat, 12345, sm@dso@.CXXDSOMISC$cxxfun)
  args <- list(init = "0", iter = 1)
  expect_exception({s <- sampler$call_sampler(args)})
  errmsg <- geterrmessage()
  #expect_error(grepl('.*not finite.*', errmsg))
  expect_true(grepl("Error", errmsg))
})

test_that("grad log is correct", {
  skip("Backwards compatibility + failure")

  y <- c(0.70,  -0.16,  0.77, -1.37, -1.99,  1.35, 0.08,
         0.02,  -1.48, -0.08,  0.34,  0.03, -0.42, 0.87,
         -1.36,  1.43,  0.80, -0.48, -1.61, -1.27)

  code <- "
    data {
      array[20] real y;
    }
    parameters {
      real mu;
      real<lower=0> sigma;
    }
    model {
      y ~ normal(mu, sigma);
    }
  "

  log_prob_fun <- function(mu, log_sigma, adjust = TRUE) {
    sigma <- exp(log_sigma)
    lp <- -sum((y - mu)^2) / (2 * (sigma^2)) - length(y) * log(sigma)
    if (adjust) lp <- lp + log(sigma)
    lp
  }

  log_prob_grad_fun <- function(mu, log_sigma, adjust = TRUE) {
    sigma <- exp(log_sigma)
    g_lsigma <- sum((y - mu)^2) * sigma^(-2) - length(y)
    if (adjust) g_lsigma <- g_lsigma + 1
    g_mu <- sum(y - mu) * sigma^(-2)
    c(g_mu, g_lsigma)
  }

  sf <- stan(model_code = code, data = list(y = y), iter = 200)
  mu <- 0.1
  sigma <- 2

  # FIXME: This test fails.
  expect_equal(
    log_prob(sf, unconstrain_pars(sf, list(mu = mu, sigma = sigma))),
    log_prob_fun(mu, log(sigma))
  )
  # FIXME: This test fails.
  expect_equal(
    log_prob(sf, unconstrain_pars(sf, list(mu = mu, sigma = sigma)), FALSE),
    log_prob_fun(mu, log(sigma), adjust = FALSE)
  )
  lp1 <- log_prob(sf, unconstrain_pars(sf, list(mu = mu, sigma = sigma)), FALSE, TRUE)
  expect_equal(attr(lp1, 'gradient'), log_prob_grad_fun(mu, log(sigma), FALSE))

  g1 <- grad_log_prob(sf, unconstrain_pars(sf, list(mu = mu, sigma = sigma)), FALSE)
  expect_equal(attr(g1, 'log_prob'), log_prob_fun(mu, log(sigma), adjust = FALSE))

  attributes(g1) <- NULL
  expect_equal(g1, log_prob_grad_fun(mu, log(sigma), adjust = FALSE))
})

test_that("Specifying arguments and data works", {
  skip("Backwards compatibility")
  y <- c(0.70,  -0.16,  0.77, -1.37, -1.99,  1.35, 0.08,
         0.02,  -1.48, -0.08,  0.34,  0.03, -0.42, 0.87,
         -1.36,  1.43,  0.80, -0.48, -1.61, -1.27)

  code <- "
    data {
      int N;
      array[N] real y;
    }
    parameters {
      real mu;
      real<lower=0> sigma;
    }
    model {
      y ~ normal(mu, sigma);
    }
  "
  stepsize0 <- 0.15
  sf <- stan(model_code = code, data = list(y = y, N = length(y)), iter = 200,
             control = list(adapt_engaged = FALSE, stepsize = stepsize0))
  expect_equal(
    attr(sf@sim$samples[[1]], "sampler_params")$stepsize__[1],
    stepsize0
  )

  sf2 <- stan(fit = sf, iter = 20, algorithm = 'HMC',
              data = list(y = y, N = length(y)),
              control = list(adapt_engaged = FALSE, stepsize = stepsize0))
  expect_equal(
    attr(sf2@sim$samples[[1]],"sampler_params")$stepsize__[1],
    stepsize0
  )

  sf3 <- stan(fit = sf, iter = 1, data = list(y = y, N = length(y)),
              init = 0, chains = 1)
  i_u <- unconstrain_pars(sf3, get_inits(sf3)[[1]])
  expect_equal(i_u, rep(0, 2))

  # Data in a function frame.
  tfun2 <- function() {
    y <- rnorm(20)
    N <- length(y)
    sm <- sf@stanmodel
    fit <- sampling(sm, data = c("y", "N"))
    fit
  }
  s1 <- tfun2()
  expect_equal(s1@mode, 0L)

  tfun <- function() {
    y <- rnorm(20)
    N <- length(y)
    fit <- stan(fit = sf, data = c("y", "N"))
    fit
  }
  s <- tfun()
  expect_equal(s@mode, 0L)
})
