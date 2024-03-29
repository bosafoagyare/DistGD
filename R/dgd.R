
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Helper Functions %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

calc_grad <- function(f) {
  force(f)
  function(x) grad(f, x)
}

make_main_tbl <- function(f_list,
                          grad_list = NULL,
                          init_xs,
                          init_step_size,
                          weight_mat) {
  if (is.null(grad_list)) {
    grad_list <- map(f_list, calc_grad)
  }
  tibble(
    f = f_list,
    grad = grad_list,
    weights = apply(weight_mat, 1, identity, simplify = FALSE), # List of rows
    curr_x = init_xs,
    curr_step_size = init_step_size
  )
}

calc_next_x <- function(id_tbl, context) {
  for (nm in names(context)) {
    assign(nm, context[[nm]], envir = .GlobalEnv)
  }

  id <- id_tbl$id
  weights <- main_tbl$weights[[id]]
  curr_xs <- main_tbl$curr_x
  curr_x <- curr_xs[[id]]
  curr_step_size <- main_tbl$curr_step_size[id]
  grad_ <- main_tbl$grad[[id]]
  curr_weighted_sum <- Reduce( # Sum weighted x_i's
    `+`,
    mapply(`*`, weights, curr_xs, SIMPLIFY = FALSE) # Mult x_i by weight i
  )
  next_x <- curr_weighted_sum - curr_step_size * grad_(curr_x)

  l <- as.list(next_x) # l's entries are individual coordinates of next_x
  names(l) <- paste0("x", seq_along(next_x))
  as.data.frame(l) # 1-row data frame, next_x coordinates in different cols
  # Function given to spark_apply must return data frame
}

perform_dgd_update <- function(main_tbl) {
  p <- main_tbl %>% pull(curr_x) %>% first() %>% length() # x lives in R^p
  columns <- c("integer", rep("double", p)) %>%
    set_names(c("id", str_c("x", seq_len(p)))) # Give output col types for speed
  context <- list( # calc_next_x uses these, so must give to cluster
    grad = grad,
    grad.default = numDeriv:::grad.default, # Dispatched by grad
    main_tbl = main_tbl
  )
  next_xs <- sdf_len(sc, nrow(main_tbl)) %>% # Spark data frame with one col, id
    spark_apply(
      calc_next_x, columns = columns, group_by = "id", context = context
    ) %>% # Gives Spark data frame w/ 1 row per func, id col, p coordinate cols
    collect() %>% # Turn Spark data frame into a plain tibble
    select(-id) %>%
    pmap(c) %>% # Transform tibble with coordinate cols into list of vectors
    map(unname)
  mutate(main_tbl, curr_x = next_xs)
}

#%%%%%%%%%%%%%%%%%%%%%%% Function to be Exported %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

#' @name dgd
#'
#' @title Distributed Gradient Descent
#'
#' @description \code{dgd} optimizes a global objective function  expressed as a
#'   sum of a list of local objective functions belonging to different agents
#'   situated in a network. It returns unified list of the optimal values from
#'   each agent.
#'
#' @param sc a connection to a Spark cluster.
#' @param f_list a list of local objective functions.
#' @param grad_list an optional list of the gradients of the functions in
#'   \code{f_list}. Must be written as R functions. If not supplied,
#'   \code{\link[numDeriv]{grad}} in the \code{numDeriv} package is used to approximate them.
#' @param init_xs a list of initial values.
#' @param init_step_size An initial step size.
#' @param weight_mat a matrix of weights of the connections between the agents.
#' @param num_iters the number of iterations to perform.
#' @param print a logical value indicating whether to print the current estimates on each iteration.
#' @param make_trace a logical value indicating whether to return a list with the minimizer estimates from
#'  the iterations.
#'
#' @return a list of global min/max from each network
#' @export
#'
#@examples
dgd <- function(sc,
                f_list,
                grad_list = NULL,
                init_xs,
                init_step_size,
                weight_mat,
                num_iters,
                print = FALSE,
                make_trace = FALSE) {
  if (missing(init_xs)) {
    stop("argument init_xs is missing, with no default")
  }
  if (missing(init_step_size)) {
    stop("argument init_step_size is missing, with no default")
  }
  if (missing(weight_mat)) {
    stop("argument weight_mat is missing, with no default")
  }

  if (!is.null(grad_list) && (length(f_list) != length(grad_list))) {
    stop("there must be one gradient for each function")
  }
  if (length(f_list) != length(init_xs)) {
    stop("there must be one initial value for each function")
  }

  main_tbl <- make_main_tbl(
    f_list, grad_list, init_xs, init_step_size, weight_mat
  )

  if (print) {
    cat("Iter 0\n")
    main_tbl %>% pull(curr_x) %>% print()
  }
  if (make_trace) {
    trace <- vector("list", num_iters + 1)
    trace[[1]] <- pull(main_tbl, curr_x)
  }
  for (iter in seq_len(num_iters)) {
    main_tbl <- perform_dgd_update(main_tbl)
    if (print) {
      cat(str_interp("Iter ${iter}\n"))
      main_tbl %>% pull(curr_x) %>% print()
    }
    if (make_trace) {
      trace[[iter + 1]] <- pull(main_tbl, curr_x)
    }
  }

  if (make_trace) {
    trace %>%
      set_names(seq_along(.) - 1) %>%
      map(enframe, name = "f_id", value = "curr_x") %>%
      bind_rows(.id = "iter_num") %>%
      mutate(iter_num = as.integer(iter_num))
  } else {
    main_tbl$curr_x
  }
}
