__precompile__()
module ProgressiveHedgingSolvers

# Standard library
using LinearAlgebra
using SparseArrays
using Distributed
using Printf

# External libraries
using Parameters
using JuMP
using StochasticPrograms
using StochasticPrograms: _WS
using MathProgBase
using ProgressMeter

import Base: show, put!, wait, isready, take!, fetch
import StochasticPrograms: StructuredModel, internal_solver, optimize_structured!, fill_solution!, solverstr

const MPB = MathProgBase

export
    ProgressiveHedgingSolver,
    Fixed,
    Adaptive,
    Serial,
    Synchronous,
    Asynchronous,
    Crash,
    StructuredModel,
    optimsolver,
    optimize_structured!,
    fill_solution!,
    get_decision,
    get_objective_value

# Include files
include("types/types.jl")
include("penalties/penalization.jl")
include("execution/execution.jl")
include("ProgressiveHedging.jl")
include("spinterface.jl")

end # module
