# Adapt a formulae into one that will iterate over stocks. Will replace the following functions:
# - stock_comment(...) - Replace any stock arguments with the stock name, paste all args together
# - stock_iterate(stock, block) - wrap (block) with code to iterate over (stock) lengthgroup vectors
# - stock_intersect(stock, block) - wrap (block) with code to intersect with an outer stock we're iterating over
# - stock_with(stock, block) - Make sure any references to (stock) in (block) uses the right name
# References to the stock will also be renamed to their final name
g3_step <- function(step_f) {
    # For formula (f), rename all (old_name)__var variables to (new_name)__var, mangling environment to match
    stock_rename <- function(f, old_name, new_name) {
        old_name <- as.character(old_name)
        if (length(old_name) != 1) stop("Stocks should be variable references")
        f_vars <- all.vars(f)
        if (rlang::is_formula(f)) {
            f_vars <- union(f_vars, ls(rlang::f_env(f)))
        }
        stock_re <- paste0("^", old_name, "__")

        # Find all vars matching stock_re
        subs <- new.env(parent = emptyenv())
        for (old_var in f_vars[grepl(stock_re, f_vars)]) {
            new_var <- sub(stock_re, paste0(new_name, "__"), old_var)
            assign(old_var, as.symbol(new_var), envir = subs)
        }

        # Update environment with new names of variables
        if (rlang::is_formula(f)) {
            new_env <- rlang::env_clone(rlang::f_env(f))
            for (old_var in f_vars[grepl(stock_re, f_vars)]) {
                if (exists(old_var, envir = rlang::f_env(f), inherits = FALSE)) {
                    new_var <- sub(stock_re, paste0(new_name, "__"), old_var)
                    remove(list = old_var, envir = new_env)
                    assign(new_var, get(old_var, envir = rlang::f_env(f), inherits = FALSE), envir = new_env)
                }
            }
            f <- f_substitute(f, as.list(subs))
            rlang::f_env(f) <- new_env
        } else {
            # Just use regular substitute
            f <- eval(call("substitute", f, as.list(subs)))
        }

        return(f)
    }

    repl_stock_fn <- function (x, to_replace) {
        stock_var <- x[[2]]
        stock <- get(as.character(stock_var), envir = rlang::f_env(step_f))

        # Recurse first, filling out any inner functions
        inner_f <- call_to_formula(x[[3]], rlang::f_env(step_f))
        inner_f <- g3_step(inner_f)

        # Replace __iter marker with proper subsetting
        subs <- list()
        subs[[paste0(stock_var, "__iter")]] <- stock_rename(stock$iter_ss, "stock", stock_var)
        inner_f <- f_substitute(inner_f, subs)

        # Wrap with stock's code
        out_f <- f_substitute(stock_rename(stock[[to_replace]], "stock",  stock_var), list(
            extension_point = inner_f))
        out_f <- stock_rename(out_f, stock_var, stock$name)

        # Add environment to formulae's environment, return inner call
        environment_merge(rlang::f_env(step_f), rlang::f_env(out_f))
        return(rlang::f_rhs(out_f))
    }

    return(call_replace(step_f,
        stock_comment = function (x) {  # Arguments: stock variable, comment
            comment_str <- paste(vapply(tail(x, -1), function (a) {
                if (is.character(a)) return (a)
                stock <- get(as.character(a), envir = rlang::f_env(step_f))
                return(stock$name)
            }, character(1)), collapse = "")

            return(call("comment", comment_str))
        },
        stock_reshape = function (x) {  # Arguments: dest_stock, source expression, will use the first variable we come across
            stock_var <- x[[2]]
            stock <- get(as.character(stock_var), envir = rlang::f_env(step_f))
            dest_lg <- stock_definition(stock, 'stock__minlen')

            # Recurse first, letting renames happen
            inner_f <- call_to_formula(x[[3]], rlang::f_env(step_f))
            inner_f <- g3_step(inner_f)

            # Assume source stock is the first in inner_f, probably true(?)
            source_stock_var <- sub('__.*$', '', all.vars(inner_f)[[1]])
            source_stock <- get(source_stock_var, envir = rlang::f_env(step_f))
            source_lg <- stock_definition(source_stock, 'stock__minlen')

            # Get upper bound for length groups, if infinite guess something that should work
            # NB: Assuming plus-group is one-long is cheating, but probably no easy general answers
            source_upperlen <- stock_definition(source_stock, 'stock__upperlen')
            if (is.infinite(source_upperlen)) source_upperlen <- tail(source_lg, 1) + 1
            dest_upperlen <- stock_definition(stock, 'stock__upperlen')
            if (is.infinite(dest_upperlen)) dest_upperlen <- max(tail(source_lg, 1), tail(dest_lg, 1)) + 1

            if (isTRUE(all.equal(source_lg, dest_lg))) {
                # Source == dest, so no point doing a transform
                out_f <- inner_f
            } else {
                # Generate a matrix to transform one to the other
                matrix_name <- paste0(source_stock$name, '_', stock$name, '_lgmatrix')
                assign(matrix_name, do.call('rbind', lapply(seq_along(dest_lg), function (dest_idx) vapply(seq_along(source_lg), function (source_idx) {
                    lower_s <- source_lg[[source_idx]]
                    upper_s <- if (source_idx >= length(source_lg)) source_upperlen else source_lg[[source_idx + 1]]

                    lower_d <- dest_lg[[dest_idx]]
                    upper_d <- if (dest_idx >= length(dest_lg)) dest_upperlen else dest_lg[[dest_idx + 1]]

                    intersect_size <- min(upper_s, upper_d) - max(lower_s, lower_d)
                    return(if (intersect_size > 0) intersect_size / (upper_s - lower_s) else 0)
                }, numeric(1)))))

                # Formulae to apply matrix
                out_f <- f_substitute(~g3_matrix_vec(lg_matrix, inner_f), list(
                    lg_matrix = as.symbol(matrix_name),
                    inner_f = inner_f))
            }

            # Add environment to formulae's environment, return inner call
            environment_merge(rlang::f_env(step_f), rlang::f_env(out_f))
            return(rlang::f_rhs(out_f))
        },
        # stock_ss subsets stock data var, Removing the specified dimensions (i.e. blanking it's part in the normal subset)
        stock_ss = function (x) { # Arguments: stock data variable (i.e. stock__num), dimension names.
            stock_instance <- x[[2]]  # NB: A "stock__num", not "stock"
            stock_var <- gsub('__.*$', '', stock_instance)
            stock <- get(stock_var, envir = rlang::f_env(step_f))
            wanted_dims <- as.character(tail(x, -2))

            # Get subset arguments as a list
            ss <- tail(as.list(stock_rename(stock$iter_ss, "stock", stock_var)), -2)

            # Replace unwanted dimensions with missing symbol
            ss[names(stock$dimnames) %in% wanted_dims] <- list(quote(x[])[[3]])
            return(as.call(c(list(as.symbol("["), stock_instance), ss)))
        },
        # stock_ssinv subsets stock data var, keeping the specified dimensions (i.e. blanking it's part in the normal subset)
        stock_ssinv = function (x) { # Arguments: stock data variable (i.e. stock__num), dimension names.
            stock_instance <- x[[2]]  # NB: A "stock__num", not "stock"
            stock_var <- gsub('__.*$', '', stock_instance)
            stock <- get(stock_var, envir = rlang::f_env(step_f))
            wanted_dims <- as.character(tail(x, -2))

            # Get subset arguments as a list
            ss <- tail(as.list(stock_rename(stock$iter_ss, "stock", stock_var)), -2)

            # Replace unwanted dimensions with missing symbol
            ss[!(names(stock$dimnames) %in% wanted_dims)] <- list(quote(x[])[[3]])
            return(as.call(c(list(as.symbol("["), stock_instance), ss)))
        },
        stock_with = function (x) {  # Arguments: stock variable, inner code block
            return(repl_stock_fn(x, 'rename'))
        },
        stock_iterate = function (x) {  # Arguments: stock variable, inner code block
            return(repl_stock_fn(x, 'iterate'))
        },
        stock_intersect = function (x) {  # Arguments: stock variable, inner code block
            return(repl_stock_fn(x, 'intersect'))
        }))
}

# Turn number/stock/string params into a single string indentifying that step
step_id <- function (...) {
    parts <- vapply(list(...), function (part) {
        if (is.numeric(part)) {
            # Number, format with leading zeros
            return(sprintf("%03d", part))
        }
        if (is.list(part) && !is.null(part$name)) {
            # Stock, extract name
            return(part$name)
        }
        if (is.character(part)) {
            # Character, pass through
            return(part[[1]])
        }
        stop("Invalid parameter to step_id: ", deparse(part))
    }, character(1))
    paste(parts, collapse = ":")
}
