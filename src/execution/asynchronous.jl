struct AsynchronousExecution{T <: AbstractFloat,
                            A <: AbstractVector,
                            S <: LQSolver} <: AbstractExecution
    subworkers::Vector{SubWorker{T,A,S}}
    work::Vector{Work}
    progressqueue::ProgressQueue{T}
    x̄::Vector{RunningAverage{A}}
    δ::Vector{RunningAverage{T}}
    decisions::Decisions{A}
    r::IteratedValue{T}
    active_workers::Vector{Future}
    # Bookkeeping
    subobjectives::Vector{A}
    finished::Vector{Int}
    # Parameters
    κ::T

    function AsynchronousExecution(κ::T, ::Type{T}, ::Type{A}, ::Type{S}) where {T <: AbstractFloat, A <: AbstractVector, S <: LQSolver}
        return new{T,A,S}(Vector{SubWorker{T,A,S}}(undef, nworkers()),
                          Vector{Work}(undef,nworkers()),
                          RemoteChannel(() -> Channel{Progress{T}}(4*nworkers())),
                          Vector{RunningAverage{A}}(undef,nworkers()),
                          Vector{RunningAverage{T}}(undef,nworkers()),
                          RemoteChannel(() -> IterationChannel(Dict{Int,A}())),
                          RemoteChannel(() -> IterationChannel(Dict{Int,T}())),
                          Vector{Future}(undef,nworkers()),
                          Vector{A}(),
                          Vector{Int}(),
                          κ)
    end
end

function init_subproblems!(ph::AbstractProgressiveHedgingSolver, subsolver::QPSolver, execution::AsynchronousExecution{T,A,S}) where {T <: AbstractFloat, A <: AbstractVector, S <: LQSolver}
    # Create subproblems on worker processes
    m = ph.stochasticprogram
    @sync begin
        for w in workers()
            execution.subworkers[w-1] = RemoteChannel(() -> Channel{Vector{SubProblem{T,A,S}}}(1), w)
            @async load_worker!(scenarioproblems(m), m, w, execution.subworkers[w-1], subsolver)
        end
    end
    @sync begin
        # Continue preparation
        for w in workers()
            execution.work[w-1] = RemoteChannel(() -> Channel{Int}(round(Int,10/execution.κ)), w)
            @async execution.x̄[w-1] = remotecall_fetch((sw, xdim)->begin
                subproblems = fetch(sw)
                if length(subproblems) > 0
                    x̄ = sum([s.π*s.x for s in subproblems])
                    return RemoteChannel(()->RunningAverageChannel(x̄, [s.x for s in subproblems]), myid())
                else
                    return RemoteChannel(()->RunningAverageChannel(zeros(T,xdim), Vector{A}()), myid())
                end
            end, w, execution.subworkers[w-1], decision_length(m))
            @async execution.δ[w-1] = remotecall_fetch((sw, xdim)->RemoteChannel(()->RunningAverageChannel(zero(T), fill(zero(T),length(fetch(sw))))), w, execution.subworkers[w-1], decision_length(m))
            put!(execution.work[w-1], 1)
        end
        # Prepare memory
        push!(execution.subobjectives, zeros(nscenarios(ph)))
        push!(execution.finished, 0)
        log_val = ph.parameters.log
        ph.parameters.log = false
        log!(ph)
        ph.parameters.log = log_val
    end
    update_iterate!(ph)
    # Init δ₂
    @sync begin
        for w in workers()
            @async remotecall_fetch((sw,ξ,δ)->begin
                for (i,s) ∈ enumerate(fetch(sw))
                    take!(δ, i)
                    put!(δ, i, norm(s.x - ξ, 2)^2, s.π)
                end
            end, w, execution.subworkers[w-1], ph.ξ, execution.δ[w-1])
        end
    end
    return ph
end

function iterate!(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution{T}) where T <: AbstractFloat
    wait(execution.progressqueue)
    while isready(execution.progressqueue)
        # Add new cuts from subworkers
        t::Int, i::Int, Q::T = take!(execution.progressqueue)
        if Q == Inf
            @warn "Subproblem $(i) is infeasible, aborting procedure."
            return :Infeasible
        end
        execution.subobjectives[t][i] = Q
        execution.finished[t] += 1
        if execution.finished[t] == nscenarios(ph)
            # Update objective
            ph.Q_history[t] = current_objective_value(ph, execution.subobjectives[t])
            ph.data.Q = ph.Q_history[t]
        end
    end
    # Project and generate new iterate
    t = ph.data.iterations
    if execution.finished[t] >= execution.κ*nscenarios(ph)
        # Get dual gap
        update_dual_gap!(ph)
        # Update progress
        @unpack δ₁, δ₂ = ph.data
        ph.dual_gaps[t] = δ₂
        ph.data.δ = sqrt(δ₁ + δ₂)/(1e-10+norm(ph.ξ,2))
        # Check if optimal
        if check_optimality(ph)
            # Optimal, tell workers to stop
            map((w,aw)->!isready(aw) && put!(w,t), execution.work, execution.active_workers)
            map((w,aw)->!isready(aw) && put!(w,-1), execution.work, execution.active_workers)
            # Final log
            log!(ph)
            return :Optimal
        end
        # Update penalty (if applicable)
        update_penalty!(ph)
        # Update iterate
        update_iterate!(ph)
        # Send new work to workers
        put!(execution.decisions, t+1, ph.ξ)
        put!(execution.r, t+1, penalty(ph))
        map((w,aw)->!isready(aw) && put!(w,t+1), execution.work, execution.active_workers)
        # Prepare memory for next iteration
        push!(execution.subobjectives, zeros(nscenarios(ph)))
        push!(execution.finished, 0)
        # Log progress
        log!(ph)
    end
    # Just return a valid status for this iteration
    return :Valid
end

function init_workers!(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution)
    # Load initial decision
    put!(execution.decisions, 1, ph.ξ)
    put!(execution.r, 1, penalty(ph))
    for w in workers()
        execution.active_workers[w-1] = remotecall(work_on_subproblems!,
                                                   w,
                                                   execution.subworkers[w-1],
                                                   execution.work[w-1],
                                                   execution.progressqueue,
                                                   execution.x̄[w-1],
                                                   execution.δ[w-1],
                                                   execution.decisions,
                                                   execution.r)
    end
    return nothing
end

function close_workers!(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution)
    map(wait, execution.active_workers)
end

function resolve_subproblems!(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution)
    return nothing
end

function update_iterate!(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution)
    ξ_prev = copy(ph.ξ)
    ph.ξ[:] = sum(fetch.(execution.x̄))
    # Update δ₁
    ph.data.δ₁ = norm(ph.ξ-ξ_prev, 2)^2
    return nothing
end

function update_subproblems!(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution)
    return nothing
end

function update_dual_gap!(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution)
    ph.data.δ₂ = sum(fetch.(execution.δ))
    return nothing
end

function calculate_objective_value(ph::AbstractProgressiveHedgingSolver, execution::AsynchronousExecution)
    return calculate_objective_value(ph, execution.subworkers)
end

function
    fill_submodels!(ph::AbstractProgressiveHedgingSolver, scenarioproblems, execution::AsynchronousExecution)
    return fill_submodels!(ph, scenarioproblems, execution.subworkers)
end

# API
# ------------------------------------------------------------
"""
    Asynchronous

...
# Parameters
- `κ::Real = 0.5`: Amount of subproblems, relative to the total number of scenarios, required to generate a new iterate in master procedure.

...
"""
struct Asynchronous <: Execution
    κ::Float64

    function Asynchronous(; κ::AbstractFloat = 0.5)
        return new(κ)
    end
end

function (execution::Asynchronous)(::Type{T}, ::Type{A}, ::Type{S}) where {T <: AbstractFloat, A <: AbstractVector, S <: LQSolver}
    return AsynchronousExecution(execution.κ, T, A, S)
end

function str(::Asynchronous)
    return "asynchronous execution"
end
