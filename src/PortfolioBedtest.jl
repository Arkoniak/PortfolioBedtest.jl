module PortfolioBedtest

using Dates
using CSV
using HTTP

export TimedEvent, glue, yahoo, momentum_score, mutate, Signal, Broker, current, assets, update, issignal, sim, Recorder, AbstractOrder, order, execute

# From https://github.com/JuliaQuant/MarketData.jl/blob/master/src/downloads.jl
"""
    struct YahooOpt <: AbstractQueryOpt
      period1  # the start time
      period2  # the end time
      interval # "1d", "1wk" or "1mo"
      events   # currently only `:history` supported
    end
The Yahoo Finance HTTP API query object.

Examples
========
```julia
julia> t = Dates.now()
2020-08-09T01:38:04.735
julia> YahooOpt(period1 = t - Year(2), period2 = t)
YahooOpt{DateTime} with 4 entries:
  :period1  => 1533778685
  :period2  => 1596937085
  :interval => "1d"
  :events   => :history
```
"""
struct YahooOpt
    period1::DateTime
    period2::DateTime
    interval::String
    events::String
end
function YahooOpt(; period1::DateTime = DateTime(1971, 2, 8),
                    period2::DateTime = Dates.now(),
                    interval::String  = "1d",
                    events::Symbol    = "history")
    YahooOpt(period1, period2, interval, events)
end

function asquery(yo::YahooOpt)
    return ("period1" => round(Int, datetime2unix(yo.period1)),
            "period2" => round(Int, datetime2unix(yo.period2)),
            "interval" => yo.interval,
            "events" => yo.events)
end

function yahoo(sym; period1 = DateTime(1971, 2, 8), period2 = Dates.now(), interval = "1d", events = "history")
    yo = YahooOpt(period1, period2, interval, events)
    yahoo(sym, yo)
end

function yahoo(sym, yo::YahooOpt)
    host = rand(("query1", "query2"))
    url  = "https://$host.finance.yahoo.com/v7/finance/download/$sym"
    res  = HTTP.get(url, query = asquery(yo))
    res.status == 200 || throw("Error requesting yahoo $res")
    csv = CSV.File(res.body, missingstrings = ["null"])
end

########################################
# TimedEvents (idea from Timestamps.jl)
########################################
struct TimedEvent{D, T}
    ts::D
    event::T
end

function Base.show(io::IO, te::TimedEvent)
    print(io, te.ts, ": ", te.event)
end

Base.isless(v1::TimedEvent{D}, v2::TimedEvent{D}) where D = v1.ts < v2.ts

function glue(f::Function, v1::Vector{TimedEvent{D, T1}}, v2::Vector{TimedEvent{D, T2}}) where {D, T1, T2}
    sort!(v1)
    sort!(v2)
    
    T = typeof(f(v1[1].event, v2[1].event, 0)) # ugly hack...
    res = TimedEvent{D, T}[]
    
    # double index
    i1, i2 = 1, 1
    # We should do beggars push here for performance
    @inbounds while (i1 <= length(v1)) & (i2 <= length(v2))
        if v1[i1] < v2[i2]
            while (v1[i1] < v2[i2]) & (i1 <= length(v1))
                push!(res, TimedEvent(v1[i1].ts, f(v1[i1].event, v2[i2].event, 1)))
                i1 += 1
            end
        elseif v2[i2] < v1[i1]
            while (v2[i2] < v1[i1]) & (i2 <= length(v2))
                push!(res, TimedEvent(v2[i2].ts, f(v1[i1].event, v2[i2].event, 2)))
                i2 += 1
            end
        end
        v1[i1].ts != v2[i2].ts && continue
        # there are no duplicates, so we can simplify calculations
        push!(res, TimedEvent(v1[i1].ts, f(v1[i1].event, v2[i2].event, 0)))
        i1 += 1
        i2 += 1
    end

    return res
end

function mfun(v1, v2, k)
    k == 0 && return merge(v1, v2)
    k == 1 && return merge(v1, map(x -> NaN, v2))
    return merge(map(x -> NaN, v1), v2)
end

glue(v1::Vector{TimedEvent{D, T1}}, v2::Vector{TimedEvent{D, T2}}) where {D, T1, T2} = glue(mfun, v1, v2)
glue(v1::Vector, v2::Vector...) = foldl((x, y) -> glue(x, y), v2; init = v1)

function filter_eom(v)
    res = similar(v, 0)
    for (i, c) in pairs(v)
        i == length(v) && continue
        month(v[i].ts) != month(v[i+1].ts) && push!(res, c)
    end
    return res
end

Base.map(f::Function, te::TimedEvent) = TimedEvent(te.ts, map(f, te.event))
mutate(f::Function, te::TimedEvent) = TimedEvent(te.ts, f(te.event))

function momentum_score(v)
    v = filter_eom(v)
    res = similar(v)
    for i in eachindex(v)
        if i < 13
            res[i] = map(x -> NaN, v[i])
            continue
        end
        p0 = values(v[i].event)
        p1 = values(v[i - 1].event)
        p3 = values(v[i - 3].event)
        p6 = values(v[i - 6].event)
        p12 = values(v[i - 12].event)
        momentum = @. 12 * (p0 / p1 - 1) + 4 * (p0 / p3 - 1) + 2 * (p0 / p6 - 1) + (p0 / p12 - 1)
        res[i] = TimedEvent(v[i].ts, NamedTuple{keys(v[i].event)}(momentum))
    end
    res
end

########################################
# Simulation part
########################################

abstract type AbstractOrder end
function order end

struct Signal{D, T}
    idx::Int
    signal::Vector{TimedEvent{D, T}}
end
Signal(sig) = Signal(1, sig)

function update(sig::Signal, ts)
    sig.signal[sig.idx].ts >= ts && return sig
    sig.idx == length(sig.signal) && return sig
    idx = sig.idx
    while idx <= length(sig.signal)
        sig.signal[idx].ts >= ts && return Signal(idx, sig.signal)
        idx += 1
    end
    return Signal(length(signal), sig.signal)
end
issignal(sig::Signal, ts) = @inbounds sig.signal[sig.idx].ts == ts
current(sig::Signal) = sig.signal[sig.idx]


struct Recorder{D, T}
    data::Vector{TimedEvent{D, T}}
end

function record(r::Recorder, broker, prices, ts)
    event = (; shares = broker.shares, total = assets(broker, prices))
    te = TimedEvent(ts, event)
    push!(r.data, te)
    nothing
end

abstract type AbstractBroker end

struct Broker{T} <: AbstractBroker
    cash::Float64
    shares::T
end

assets(broker::Broker, prices) = sum(values(broker.shares) .* values(prices)) + broker.cash

function execute end

function sim(broker::AbstractBroker, strategy, prices, signal, recorder)
    for i in eachindex(prices)
        ev = prices[i]
        ts = ev.ts
        signal = update(signal, ts)
        if issignal(signal, ts)
            ord = order(strategy, broker, current(signal).event, ev.event)
            broker = execute(broker, ord, ev.event)
        end
        record(recorder, broker, ev.event, ts)
    end

    return assets(broker, prices[end].event)
end

end # module
