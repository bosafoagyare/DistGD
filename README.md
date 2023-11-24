
<!-- README.md is generated from README.Rmd. Please edit that file -->

# DistGD

<!-- badges: start -->
<!-- badges: end -->

The goal of DistGD (Distributed Gradient Descent) is to efficiently
optimize a global objective function expressed as a sum of a list of
local objective functions belonging to different agents situated in a
network via a cluster architecture like
[Spark](https://spark.apache.org/). You supply a list of local objective
functions, weights of the connections between the agents, initialize a
vector initial values, and it takes care of the computations, returning the
optimal values.

*You can read more about the [reference](papers/yang_et_al_2019.pdf) and
the [write-up](papers/report.pdf) for this library.*

## Installation

You can install the development version of DistGD from
[GitHub](https://github.com/bosafoagyare/DistGD/) with:

``` r
install.packages("devtools")
devtools::install_github("bosafoagyare/DistGD")
```

## Example

### Implementing Ordinary Logistic Regression for a very big data

**Load Packages**

``` r
library(DistGD)
library(ggplot2)
library(devtools)
library(sparklyr)
library(numDeriv)
library(tidyverse)
```

**Simulate data:**

``` r
N       <- 100000
X       <- rnorm(n = N, 0, 1)
epsilon <- rnorm(n = N, 0, 1)
X       <- cbind(rep(1, N),X)
beta    <- c(-3,4)

Y       <- X%*%beta + epsilon
```

**Distribute data and cost function to agents**

``` r
N_1 = round(N / 3)
N_2 = round(N * 2 / 3)

X_1 = X[1:N_1,]
X_2 = X[(N_1 + 1):N_2,]
X_3 = X[(N_2 + 1):N,]

Y_1 = Y[1:N_1]
Y_2 = Y[(N_1 + 1):N_2]
Y_3 = Y[(N_2 + 1):N]

regress_loss <- function(beta_hat){
  return(sum((Y - X%*%beta_hat)^2))
}

regress_loss_1 <- function(beta_hat){
  return(sum((Y_1 - X_1%*%beta_hat)^2))
}
environment(regress_loss_1) <- list2env(x = list(X_1 = X_1, Y_1 = Y_1))


regress_loss_2 <- function(beta_hat){
  return(sum((Y_2 - X_2%*%beta_hat)^2))
}
environment(regress_loss_2) <- list2env(x = list(X_2 = X_2, Y_2 = Y_2))


regress_loss_3 <- function(beta_hat){
  return(sum((Y_3 - X_3%*%beta_hat)^2))
}
environment(regress_loss_3) <- list2env(x = list(X_3 = X_3, Y_3 = Y_3))
```

**Submit to Spark**

``` r
sc <- spark_connect(master = "local")

trace <- DistGD::dgd(
  sc,
  f_list = list(regress_loss_1, 
                regress_loss_2,
                regress_loss_3),
  grad_list = NULL,
  init_xs = list(c(-4,0), c(-1,-1), c(0,5)),
  init_step_size = 0.00001,
  weight_mat = rbind(c(1/3, 1/3, 1/3), 
                     c(1/3, 1/3, 1/3), 
                     c(1/3, 1/3, 1/3)),
  num_iters = 10,
  print = TRUE,
  make_trace = TRUE
)
```

**Collect results and visualize the traces**

``` r
grid <- expand.grid(beta_0 = seq(from = -7, to = 1, length.out = 10),
                    beta_1 = seq(from = -1, to = 7, length.out = 10))
z <- c()
for (i in 1:dim(grid)[1]) {
  z[i] <- regress_loss(c(grid[i,1], grid[i,2]))
}
grid['loss'] <- z

optimal <- lm.fit(X, Y)$coefficients
optimal <- data.frame(beta_0=optimal[1], beta_1=optimal[2])

iterations_1 <- trace %>%
  relocate(f_id) %>%
  arrange(f_id, iter_num) %>%
  mutate(
    f_id = as_factor(f_id),
    curr_x_1 = map_dbl(curr_x, 1),
    curr_x_2 = map_dbl(curr_x, 2)
  ) %>%
  select(!curr_x)

ggplot() +
  geom_point(data=iterations_1, aes(curr_x_1, curr_x_2, color = iter_num)) +
  facet_wrap(vars(f_id)) +
  geom_path(data=iterations_1, aes(curr_x_1, curr_x_2, color = iter_num)) +
  geom_contour(data=grid, aes(beta_0, beta_1, z = loss), size=0.2) + 
  geom_point(data=optimal, aes(beta_0, beta_1)) + 
  theme_bw()
```

**Visualization of output** ![](OLS.jpg)

## Reference

If you use DistGD, please cite the following paper:

    @techreport{osafoagyare_distgd_2022,
      abstract = {In distributed optimization, there is a global objective function that is expressed as a sum
                  of local objective functions, each of which is assigned to an agent. An example of an agent is a
                  node in a computer network. Each agent attempts to minimize its local objective function using
                  information on its function and information from the other agents. The aim of our project was
                  to create an R package that implements two distributed optimization algorithms. We describe
                  the algorithms and our package, which implements one of the algorithms. We also discuss the
                  results of experiments in which we used our code to solve distributed versions of statistical
                  problems.},
      author = {Osafo Agyare, Benjamin and Ochoa, Eduardo and Verma, Victor},
      institution = {University of Michigan, Ann Arbor},
      title = {A Distributed Optimization Package for R},
      year = {2022}
}


## License

DistGD is MIT licensed, as found in the [LICENSE](LICENSE) file
