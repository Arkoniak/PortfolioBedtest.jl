using Revise
using PortfolioBedtest
import PortfolioBedtest: order, execute
using Dates
using Statistics
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
    res = [TimedEvent(assts[indx[period + 1]].ts, w)]
    for i in period+2:length(indx)
        w = build(assts, indx[i - period]:indx[i], risk)
        push!(res, TimedEvent(assts[indx[i]].ts, w))
    end
    Signal(res)
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

using Plots
tsts = getfield.(signal.signal, :ts)
plot(tsts, getfield.(mutate.(x -> x[1], signal.signal), :event), legend = :outerright, label = "SPY")
plot!(tsts, getfield.(mutate.(x -> x[2], signal.signal), :event), label = "AGG")
plot!(tsts, getfield.(mutate.(x -> x[3], signal.signal), :event), label = "GLD")
