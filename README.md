# ProgressiveHedgingSolvers

[![Build Status](https://travis-ci.org/martinbiel/ProgressiveHedgingSolvers.jl.svg?branch=test)](https://travis-ci.org/martinbiel/ProgressiveHedgingSolvers.jl)

[![Coverage Status](https://coveralls.io/repos/martinbiel/ProgressiveHedgingSolvers.jl/badge.svg?branch=test&service=github)](https://coveralls.io/github/martinbiel/ProgressiveHedgingSolvers.jl?branch=test)

[![codecov.io](http://codecov.io/github/martinbiel/ProgressiveHedgingSolvers.jl/coverage.svg?branch=test)](http://codecov.io/github/martinbiel/ProgressiveHedgingSolvers.jl?branch=test)

`ProgressiveHedgingSolvers` includes implementations of the Progressive-hedging algorithm for two-stage stochastic recourse problems. All algorithm variants are based on the original progressive-hedging algorithm by Rockafellar and Wets. `ProgressiveHedgingSolvers` interfaces with [StochasticPrograms.jl][StochProg], and a given recourse model `sp` is solved effectively through

```julia
julia> using ProgressiveHedgingSolvers

julia> solve(sp,solver=ProgressiveHedgingSolver(IpoptSolver(print_level=0)))
Progressive Hedging Time: 0:00:06 (1315 iterations)
  Objective:  -855.8332803469432
  δ:          9.436947935542464e-7
:Optimal

```

Note, that a QP capable `AbstractMathProgSolver` is required to solve emerging subproblems. In addition, there are distributed variants of the algorithm: `ProgressiveHedgingSolver(execution = Synchronous())` and `ProgressiveHedgingSolver(execution = Asynchronous())`, which requires adding processes with `addprocs` prior to execution.

The algorithm has a set of parameters that can be tuned prior to execution. For a list of these parameters and their default values, use `?` in combination with the solver object. For example, `?Adaptive` gives the parameter list for the adaptive penalty procedure. For a list of all solvers and their handle names, use `?ProgressiveHedgingSolver`.

[StochProg]: https://github.com/martinbiel/StochasticPrograms.jl

## References

1. R. T. Rockafellar and Roger J.-B. Wets (1991), [Scenarios and Policy Aggregation in Optimization Under Uncertainty](https://pubsonline.informs.org/doi/10.1287/moor.16.1.119),
Mathematics of Operations Research, vol. 16, no. 1, pp. 119-147.
