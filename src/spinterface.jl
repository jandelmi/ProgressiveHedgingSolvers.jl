"""
    ProgressiveHedgingSolver(qpsolver::AbstractMathProgSolver; <keyword arguments>)

Return a progressive-hedging algorithm object specified. Supply `qpsolver`, a MathProgBase solver capable of solving quadratic problems.

The following penalty parameter update procedures are available
- `Fixed`:  Fixed penalty (default) ?Fixed for parameter descriptions.
- `adaptive`: Adaptive penalty update ?Adaptive for parameter descriptions.

The following execution policies are available
- `Serial`:  Classical progressive-hedging (default)
- `Synchronous`: Classical progressive-hedging run in parallel ?Synchronous for parameter descriptions.
- `Asynchronous`: Asynchronous progressive-hedging ?Asynchronous for parameter descriptions.

...
# Arguments
- `qpsolver::AbstractMathProgSolver`: MathProgBase solver capable of solving quadratic programs.
- `penalty::AbstractPenalizer = Fixed()`: Specify penalty update procedure (Fixed, Adaptive)
- `execution::AbstractExecuter = Serial`: Specify how algorithm should be executed (Serial, Synchronous, Asynchronous). Distributed variants requires worker cores.
- <keyword arguments>: Algorithm specific parameters, consult individual docstrings (see above list) for list of possible arguments and default values.
...

## Examples

The following solves a stochastic program `sp` created in `StochasticPrograms.jl` using the progressive-hedging algorithm with Ipopt as an `qpsolver`.

```jldoctest
julia> solve(sp,solver=ProgressiveHedgingSolver(IpoptSolver(print_level=0)))
Progressive Hedging Time: 0:00:06 (1315 iterations)
  Objective:  -855.8332803469432
  δ:          9.436947935542464e-7
:Optimal
```
"""
mutable struct ProgressiveHedgingSolver{S <: QPSolver,
                                        E <: Execution,
                                        P <: AbstractPenalizer} <: AbstractStructuredSolver
    qpsolver::S
    execution::E
    penalty::P
    crash::CrashMethod
    parameters::Dict{Symbol,Any}

    function ProgressiveHedgingSolver(qpsolver::QPSolver;
                                      execution::Execution = Serial(),
                                      penalty::AbstractPenalizer = Fixed(),
                                      crash::CrashMethod = Crash.None(), kwargs...)
        S = typeof(qpsolver)
        E = typeof(execution)
        P = typeof(penalty)
        return new{S, E, P}(qpsolver,
                            execution,
                            penalty,
                            crash,
                            Dict{Symbol,Any}(kwargs))
    end
end

function StructuredModel(stochasticprogram::StochasticProgram, solver::ProgressiveHedgingSolver)
    x₀ = solver.crash(stochasticprogram, solver.qpsolver)
    return ProgressiveHedging(stochasticprogram, solver.qpsolver, solver.execution, solver.penalty; solver.parameters...)
end

function add_params!(solver::ProgressiveHedgingSolver; kwargs...)
    push!(solver.parameters, kwargs...)
    for (k,v) in kwargs
        if k ∈ [:qpsolver, :execution, :penalty, :crash]
            setfield!(solver, k, v)
            delete!(solver.parameters, k)
        end
    end
    return nothing
end

function internal_solver(solver::ProgressiveHedgingSolver)
    return get_solver(solver.qpsolver)
end

function optimize_structured!(ph::AbstractProgressiveHedgingSolver)
    return ph()
end

function fill_solution!(stochasticprogram::StochasticProgram, ph::AbstractProgressiveHedgingSolver)
    # First stage
    first_stage = StochasticPrograms.get_stage_one(stochasticprogram)
    nrows, ncols = first_stage_dims(stochasticprogram)
    StochasticPrograms.set_decision!(stochasticprogram, ph.ξ)
    # stochasticprogram.redCosts = try
    #     getreducedcosts(ph.mastersolver.lqmodel)[1:ncols]
    # catch
    #     fill(NaN, ncols)
    # end
    # stochasticprogram.linconstrDuals = try
    #     getconstrduals(ph.mastersolver.lqmodel)[1:nrows]
    # catch
    #     fill(NaN, nrows)
    # end
    # Second stage
    fill_submodels!(ph, scenarioproblems(stochasticprogram))
end

function solverstr(solver::ProgressiveHedgingSolver)
    return "Progressive-hedging solver under $(str(solver.execution)) and $(str(solver.penalty))"
end
