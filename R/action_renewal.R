# Assign number / mean weight based on formulae
g3a_initialconditions <- function (stock, num_f, wgt_f, run_f = ~cur_time == 0L, run_at = 0) {
    stock__num <- stock_instance(stock)
    stock__wgt <- stock_instance(stock)

    out <- list()
    out[[step_id(run_at, stock)]] <- g3_step(f_substitute(~if (cur_time == 0L) {
        stock_comment("g3a_initialconditions for ", stock)
        stock_iterate(stock, {
            stock_ss(stock__num) <- num_f
            stock_ss(stock__wgt) <- wgt_f
        })
    }, list(num_f = num_f, wgt_f = wgt_f)))
    return(out)
}

# Steps to set up renewal of stocks on first step
g3a_initialconditions_normalparam <- function (stock, factor_f, mean_f, stddev_f, alpha_f, beta_f, run_f = ~cur_time == 0L, run_at = 0) {
    # See InitialCond::Initialise
    stock__num <- stock_instance(stock)
    stock__wgt <- stock_instance(stock)

    out <- list()
    out[[step_id(run_at, stock)]] <- g3_step(f_substitute(~{
        stock_comment("g3a_initialconditions_normalparam for ", stock)
        stock_iterate(stock, if (run_f) {
            # exp(-(dnorm**2) * 0.5)
            stock_ss(stock__num) <- exp(-(((stock__midlen - mean_f) * (1.0 / stddev_f)) ** 2) * 0.5)
            # scale results
            stock_ss(stock__num) <- stock_ss(stock__num) * (10000.0 / sum(stock_ss(stock__num))) * factor_f
            stock_ss(stock__wgt) <- alpha_f * stock__midlen ** beta_f
        })
    }, list(
        run_f = run_f,
        factor_f = factor_f,
        mean_f = mean_f,
        stddev_f = stddev_f,
        alpha_f = alpha_f,
        beta_f = beta_f)))
    return(out)
}

# Assign number / mean weight based on formulae
g3a_renewal <- function (stock, num_f, wgt_f, run_f = ~TRUE, run_at = 8) {
    stock__num <- stock_instance(stock)
    stock__wgt <- stock_instance(stock)
    stock__renewalnum <- stock_instance(stock)
    stock__renewalwgt <- stock_instance(stock)

    out <- list()
    out[[step_id(run_at, stock)]] <- g3_step(f_substitute(~if (cur_time == 0L) {
        stock_comment("g3a_renewal for ", stock)
        stock_iterate(stock, {
            stock_ss(stock__renewalnum) <- num_f
            stock_ss(stock__renewalwgt) <- wgt_f

            # To total weight
            stock_ss(stock__wgt) <- stock_ss(stock__wgt) * stock_ss(stock__num)
            # Add new stock
            stock_ss(stock__num) <- stock_ss(stock__num) + stock_ss(stock__renewalnum)
            stock_ss(stock__wgt) <- stock_ss(stock__wgt) + (stock_ss(stock__renewalnum) * stock_ss(stock__renewalwgt))
            # Back to mean weight
            stock_ss(stock__wgt) <- stock_ss(stock__wgt) / logspace_add_vec(stock_ss(stock__num), 0)
        })
    }, list(num_f = num_f, wgt_f = wgt_f)))
    return(out)
}

# Steps to set up renewal of stocks on any stock
g3a_renewal_normalparam <- function (stock, factor_f, mean_f, stddev_f, alpha_f, beta_f, run_f = ~TRUE, run_at = 8) {
    # See InitialCond::Initialise
    stock__num <- stock_instance(stock)
    stock__wgt <- stock_instance(stock)
    stock__renewalnum <- stock_instance(stock)
    stock__renewalwgt <- stock_instance(stock)

    out <- list()
    out[[step_id(run_at, stock)]] <- g3_step(f_substitute(~{
        stock_comment("g3a_renewal_normalparam for ", stock)
        stock_iterate(stock, if (run_f) {
            # exp(-(dnorm**2) * 0.5)
            stock_ss(stock__renewalnum) <- exp(-(((stock__midlen - mean_f) * (1.0 / stddev_f)) ** 2) * 0.5)
            # scale results
            stock_ss(stock__renewalnum) <- stock_ss(stock__renewalnum) * (10000.0 / sum(stock_ss(stock__renewalnum))) * factor_f
            stock_ss(stock__renewalwgt) <- alpha_f * stock__midlen ** beta_f

            # To total weight
            stock_ss(stock__wgt) <- stock_ss(stock__wgt) * stock_ss(stock__num)
            # Add new stock
            stock_ss(stock__num) <- stock_ss(stock__num) + stock_ss(stock__renewalnum)
            stock_ss(stock__wgt) <- stock_ss(stock__wgt) + (stock_ss(stock__renewalnum) * stock_ss(stock__renewalwgt))
            # Back to mean weight
            stock_ss(stock__wgt) <- stock_ss(stock__wgt) / logspace_add_vec(stock_ss(stock__num), 0)
        })
    }, list(
        run_f = run_f,
        factor_f = factor_f,
        mean_f = mean_f,
        stddev_f = stddev_f,
        alpha_f = alpha_f,
        beta_f = beta_f)))
    return(out)
}
