# action_time: General timekeeping step

g3a_time <- function(start_year, end_year, steps = c(12)) {
    if (sum(steps) != 12) stop("steps should sum to 12 (i.e. represent a whole year)")

    # If these are literals, they should be integers
    if (is.numeric(start_year)) start_year <- as.integer(start_year)
    if (is.numeric(end_year)) end_year <- as.integer(end_year)
    if (is.numeric(steps)) steps <- as.integer(steps)

    step_count <- length(steps)
    cur_time <- as.integer(0)
    cur_step <- as.integer(0)
    cur_step_len <- as.integer(0)
    cur_year <- as.integer(0)
    cur_step_final <- FALSE
    total_steps <- ~length(steps) * (end_year - start_year) + length(steps) - 1

    list(step0 = ~{
        comment("g3a_time")
        if (cur_time > total_steps) break
        cur_year <- start_year + (cur_time %/% step_count)
        cur_step <- (cur_time %% step_count) + 1
        cur_step_len <- steps[[g3_idx(cur_step)]]
        cur_step_final <- cur_step == step_count
        debugf("** Tick: %d-%d\n", cur_year, cur_step)
    }, step999 = ~{
        cur_time <- cur_time + 1
    })
}