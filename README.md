
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
vector initial values, and it takes care of the details, returning the
optimal values.

## Installation

You can install the development version of DistGD from
[GitHub](https://github.com/bosafoagyare/DistGD/) with:

``` r
install.packages("devtools")
devtools::install_github("bosafoagyare/DistGD")
```

## Example
