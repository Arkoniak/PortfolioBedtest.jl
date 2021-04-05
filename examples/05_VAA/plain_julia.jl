using Revise
using PortfolioBedtest
import PortfolioBedtest: order, execute
using Dates
using BenchmarkTools
using Setfield

# Offensive assets
spyts = yahoo("SPY") |> x -> map(x -> TimedEvent(x.Date, (; spy = getproperty(x, Symbol("Adj Close")))), x);
efats = yahoo("EFA") |> x -> map(x -> TimedEvent(x.Date, (; efa = getproperty(x, Symbol("Adj Close")))), x);
eemts = yahoo("EEM") |> x -> map(x -> TimedEvent(x.Date, (; eem = getproperty(x, Symbol("Adj Close")))), x);
aggts = yahoo("AGG") |> x -> map(x -> TimedEvent(x.Date, (; agg = getproperty(x, Symbol("Adj Close")))), x);

# Defensive assets
lqdts = yahoo("LQD") |> x -> map(x -> TimedEvent(x.Date, (; lqd = getproperty(x, Symbol("Adj Close")))), x);
iefts = yahoo("IEF") |> x -> map(x -> TimedEvent(x.Date, (; ief = getproperty(x, Symbol("Adj Close")))), x);
shyts = yahoo("SHY") |> x -> map(x -> TimedEvent(x.Date, (; shy = getproperty(x, Symbol("Adj Close")))), x);

asts = glue(spyts, efats, eemts, aggts, lqdts, iefts, shyts)
asts = filter(x -> !any(isnan, x.event), asts)
masts = momentum_score(asts)
masts = filter(x -> !any(isnan, x.event), masts)

########################################
# Simulation part
########################################

# TODO: We can make a function, which accepts keys and translate them to indices
struct VAAStrategy{T1, T2}
    off::T1
    def::T2
end 
function maxkv(v1, v2)
    i0 = v2[1]
    val0 = v1[i0]
    for i in 2:length(v2)
        i1 = v2[i]
        val1 = v1[i1]
        i0 = val1 > val0 ? i1 : i0
        val0 = val1 > val0 ? val1 : val0
    end
    return i0, val0
end
function minkv(v1, v2)
    i0 = v2[1]
    val0 = v1[i0]
    for i in 2:length(v2)
        i1 = v2[i]
        val1 = v1[i1]
        i0 = val1 < val0 ? i1 : i0
        val0 = val1 < val0 ? val1 : val0
    end
    return i0, val0
end

struct Order <: AbstractOrder
    id::Int
end

function order(strat::VAAStrategy, broker, signal, prices)
    _, v0 = minkv(signal, strat.off)
    i, v = v0 < 0 ? maxkv(signal, strat.def) : maxkv(signal, strat.off)
    return Order(i)
end

function execute(broker, order, prices)
    broker.shares[order.id] != 0 && return broker # no need to resell same share
    a = assets(broker, prices)
    nshares = floor(Int, a/prices[order.id])
    shares = NamedTuple{keys(prices)}(ntuple(i -> i == order.id ? nshares : 0, length(prices)))
    @set! broker.cash = a - nshares * prices[order.id]
    @set! broker.shares = shares
    return broker
end

broker = Broker(1_000_000.0, map(_ -> 0, asts[1].event))
strat = VAAStrategy((1, 2, 3, 4), (5, 6, 7))
signal = Signal(masts)
recorder = Recorder{Date, typeof((; shares = broker.shares, total = 10.0))}([])

# Here goes nothing...
sim(broker, strat, asts, signal, recorder)

########################################
# Plotting
########################################
using Plots

equity_curve = mutate.(x -> x.total, recorder.data)
plot(getfield.(equity_curve, :ts), getfield.(equity_curve, :event), legend = :topleft)

# Assets buy distribution

equities = map(recorder.data) do r
    mutate(r) do row
        for (k, v) in pairs(row.shares)
            v != 0 && return k
        end
        :none
    end
end

ks = (:none, keys(broker.shares)...)
findfirst(==(:shy), ks)
getfield.(equities, :event)

dts = getfield.(equities, :ts)
vals = getfield.(equities, :event)

g = scatter(dts[vals .== ks[2]], fill(1, count(==(ks[2]), vals)), legend = :outerright, markersize = 2, label = string(ks[2]), markerstrokewidth = 0.01)
for i in 3:length(ks)
    g = scatter!(dts[vals .== ks[i]], fill(i - 1, count(==(ks[i]), vals)), markersize = 2, label = string(ks[i]), markerstrokewidth = 0.01)
end
g

########################################
# Deprecated & experiments
########################################

# Move strategy to signals

# offts = mutate.(x -> (; spy = x.spy, efa = x.efa, eem = x.eem, agg = x.agg), masts)
# defts = mutate.(x -> (; lqd = x.lqd, ief = x.ief, shy = x.shy), masts)

# struct VAASignal{D, T1, T2}
#     off::Signal{D, T1}
#     def::Signal{D, T2}
# end

# function update(sig::VAASignal, ts)
#     off2 = update(sig.off, ts)
#     def2 = update(sig.def, ts)
#     VAASignal(off2, def2)
# end

# struct VAAStrategy end 
# signal = VAASignal(Signal(offts), Signal(defts))
