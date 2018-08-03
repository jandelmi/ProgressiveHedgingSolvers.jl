Crops = [:wheat,:corn,:beets]
Purchased = [:wheat,:corn]
Sold = [:wheat,:corn,:beets_quota,:beets_extra]

Cost = Dict(:wheat=>150,:corn=>230,:beets=>260)
Required = Dict(:wheat=>200,:corn=>240,:beets=>0)
PurchasePrice = Dict(:wheat=>238,:corn=>210)
SellPrice = Dict(:wheat=>170,:corn=>150,:beets_quota=>36,:beets_extra=>10)
Budget = 500

@everywhere begin
    struct FarmerScenario <: StochasticPrograms.AbstractScenarioData
        Yield::Dict{Symbol,Float64}
    end
    StochasticPrograms.probability(::FarmerScenario) = 1/3
    function StochasticPrograms.expected(scenarios::Vector{FarmerScenario})
        sd = FarmerScenario(Dict(:wheat=>sum([probability(s)*s.Yield[:wheat] for s in scenarios]),
                                 :corn=>sum([probability(s)*s.Yield[:corn] for s in scenarios]),
                                 :beets=>sum([probability(s)*s.Yield[:beets] for s in scenarios])))
    end
end

s1 = FarmerScenario(Dict(:wheat=>3.0,:corn=>3.6,:beets=>24.0))
s2 = FarmerScenario(Dict(:wheat=>2.5,:corn=>3.0,:beets=>20.0))
s3 = FarmerScenario(Dict(:wheat=>2.0,:corn=>2.4,:beets=>16.0))

sp = StochasticProgram((Crops,Cost,Budget),(Required,PurchasePrice,SellPrice),[s1,s2,s3])

@first_stage sp = begin
    (Crops,Cost,Budget) = stage
    @variable(model, x[c = Crops] >= 0)
    @objective(model, Min, sum(Cost[c]*x[c] for c in Crops))
    @constraint(model, sum(x[c] for c in Crops) <= Budget)
end

@second_stage sp = begin
    @decision x
    (Required,PurchasePrice,SellPrice) = stage
    s = scenario
    @variable(model, y[p = Purchased] >= 0)
    @variable(model, w[s = Sold] >= 0)
    @objective(model, Min, sum( PurchasePrice[p] * y[p] for p = Purchased) - sum( SellPrice[s] * w[s] for s in Sold))

    @constraint(model, const_minreq[p=Purchased],
                   s.Yield[p] * x[p] + y[p] - w[p] >= Required[p])
    @constraint(model, const_minreq_beets,
                   s.Yield[:beets] * x[:beets] - w[:beets_quota] - w[:beets_extra] >= Required[:beets])
    @constraint(model, const_aux, w[:beets_quota] <= 6000)
end

push!(problems,(sp,"Farmer"))
