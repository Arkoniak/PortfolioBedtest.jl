using Revise
using PortfolioBedtest
import PortfolioBedtest: order, execute
using Dates
using Statistics
using Setfield
using Convex, SCS # It can be simplifed, but existing solutions are fine

########################################
# Auxiliary functions
########################################
function get_optim_weights(w, risk, ret, λ)
    p = minimize(λ * risk - (1 - λ) * ret,
                 sum(w) == 1,
                 0.0 <= w,
                 w <= 1.0)
    solve!(p, () -> SCS.Optimizer(verbose = false))
    
    return sqrt(evaluate(risk)), evaluate(w)
end

function find_weights(M, r, risk0, tol = 1e-8)
    w = Variable(length(r))
    risk = quadform(w, M)
    ret = dot(w, r)
    l1 = 0.01
    risk1, _ = get_optim_weights(w, risk, ret, l1)
    l2 = 0.99
    risk2, _ = get_optim_weights(w, risk, ret, l2)
    l3 = (l1 + l2)/2
    risk3, _ = get_optim_weights(w, risk, ret, l3)
    while abs(l1 - l2) > tol
        if risk1 >= risk0 >= risk3
            l2 = l3
        else
            l1 = l3
        end
        l3 = (l1 + l2) / 2
        risk3, _ = get_optim_weights(w, risk, ret, l3)
    end
    risk3, w3 = get_optim_weights(w, risk, ret, l3)

    return risk3, w3
end

function build(assts, rng, risk = 0.1)
    # not very efficient, but ok
    wnd = assts[rng]
    wnd2 = wnd[2:end] ./ wnd[1:end - 1]
    ret = exp.((252 * mean(map.(log, wnd2))).event) .- 1
    # It can be done in row-wise format, but optimization is not important here
    # So we transform data to column-wise matrix
    M = 252 .* cov(hcat(map(i -> getindex.(getfield.(wnd2, :event), i), 1:length(ret))...))
    _, w = find_weights(M, ret, risk)

    return w
end

function create_signal(assts, risk = 0.1, period = 36)
    indx = filter_eom_indices(assts)
    w = build(assts, indx[1]:indx[period+1], risk)
    w2 = tuple(w...)
    res = [TimedEvent(assts[indx[period + 1]].ts, w2)]
    for i in period+2:length(indx)
        w = build(assts, indx[i - period]:indx[i], risk)
        w2 = tuple(w...)
        push!(res, TimedEvent(assts[indx[i]].ts, w2))
    end
    Signal(res)
end

########################################
# Simulation auxiliary structures
########################################
struct RatioStrategy end

struct Order{T} <: AbstractOrder
    shares::T
end

function order(strat::RatioStrategy, broker, signal, prices)
    a = assets(broker, prices)
    ntuple(length(signal)) do i
        floor(Int, a * signal[i] / prices[i])
    end |> Order
end

function execute(broker, ord::Order, prices)
    a = assets(broker, prices)
    for i in 1:length(ord.shares)
        a -= ord.shares[i] * prices[i]
    end
    Broker(a, ord.shares)
end

########################################
# Calculations
########################################

# ETF
spyts = yahoo("SPY") |> x -> map(x -> TimedEvent(x.Date, getproperty(x, Symbol("Adj Close"))), x);
aggts = yahoo("AGG") |> x -> map(x -> TimedEvent(x.Date, getproperty(x, Symbol("Adj Close"))), x);
gldts = yahoo("GLD") |> x -> map(x -> TimedEvent(x.Date, getproperty(x, Symbol("Adj Close"))), x);

assts = glue(spyts, aggts, gldts) do v1, v2, k
    k == 0 && return (v1..., v2...)
    k == 1 && return (v1..., map(_ -> NaN, v2)...)
    return (map(_ -> NaN, v1)..., v2...)
end

assts = filter(x -> !any(isnan.(x.event)), assts)
signal = create_signal(assts)
broker = Broker(1_000_000.0, ntuple(_ -> 0, length(assts[1].event)))
strat = RatioStrategy()
recorder = Recorder{Date, typeof((; shares = broker.shares, total = 0.0))}([])

sim(broker, strat, assts, signal, recorder)

########################################
# Volatility 7.5%
########################################
vol75_signal = create_signal(assts, 0.075)
vol75_recorder = Recorder{Date, typeof((; shares = broker.shares, total = 0.0))}([])

sim(broker, strat, assts, vol75_signal, vol75_recorder)

########################################
# 60/40 comparison
########################################

sfsignal = Signal(mutate.(_ -> (0.6, 0.4, 0.0), signal.signal))
sfrecorder = Recorder{Date, typeof((; shares = broker.shares, total = 0.0))}([])

sim(broker, strat, assts, sfsignal, sfrecorder)

########################################
# Plotting
########################################
using Plots
tsts = getfield.(signal.signal, :ts)
plot(tsts, getfield.(mutate.(x -> x[1], signal.signal), :event), legend = :outerright, label = "SPY")
plot!(tsts, getfield.(mutate.(x -> x[2], signal.signal), :event), label = "AGG")
plot!(tsts, getfield.(mutate.(x -> x[3], signal.signal), :event), label = "GLD")


# Equities
equity_curve = mutate.(x -> x.total, recorder.data)
plot(getfield.(equity_curve, :ts), getfield.(equity_curve, :event), legend = :topleft, label = "10% volatilty rebalance")

sfequity_curve = mutate.(x -> x.total, sfrecorder.data)
plot!(getfield.(sfequity_curve, :ts), getfield.(sfequity_curve, :event), label = "60/40 SPY/AGG")

vol75_equity_curve = mutate.(x -> x.total, vol75_recorder.data)
plot!(getfield.(vol75_equity_curve, :ts), getfield.(vol75_equity_curve, :event))

########################################
# Volatility spectre
########################################
function build_vol_plot(assts, rng)
    isfirst = true
    broker = Broker(1_000_000.0, ntuple(_ -> 0, length(assts[1].event)))
    strat = RatioStrategy()
    recorder = Recorder{Date, typeof((; shares = broker.shares, total = 0.0))}([])
    local g
    for vol in rng
        signal = create_signal(assts, vol)
        sim(broker, strat, assts, signal, recorder)
        equity_curve = mutate.(x -> x.total, recorder.data)
        g = if isfirst
            isfirst = false
            plot(getfield.(equity_curve, :ts), getfield.(equity_curve, :event), legend = :topleft, label = "Risk: $vol")
        else
            plot!(getfield.(equity_curve, :ts), getfield.(equity_curve, :event), label = "Risk: $vol")
        end
    end

    return g
end

build_vol_plot(assts, 0.06:0.02:0.12)

########################################
# Sliding window spectre
########################################

function build_win_plot(assts, rng, risk = 0.1)
    isfirst = true
    broker = Broker(1_000_000.0, ntuple(_ -> 0, length(assts[1].event)))
    strat = RatioStrategy()
    recorder = Recorder{Date, typeof((; shares = broker.shares, total = 0.0))}([])
    local g
    for wnd in rng
        signal = create_signal(assts, risk, wnd)
        sim(broker, strat, assts, signal, recorder)
        equity_curve = mutate.(x -> x.total, recorder.data)
        g = if isfirst
            isfirst = false
            plot(getfield.(equity_curve, :ts), getfield.(equity_curve, :event), legend = :topleft, label = "Window: $wnd", linewidth = 0.5)
        else
            plot!(getfield.(equity_curve, :ts), getfield.(equity_curve, :event), label = "Window: $wnd", linewidth = 0.5)
        end
    end

    return g
end

build_win_plot(assts, 12:6:48)
build_win_plot(assts, 20:2:28)
build_win_plot(assts, 20:2:28, 0.12)
