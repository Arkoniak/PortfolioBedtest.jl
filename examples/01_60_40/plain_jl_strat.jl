using CSV, DataFrames
using Dates
using TimeSeries
using Setfield
using Plots

function prep_data()
    spydf = CSV.File("SPY.csv") |> DataFrame
    aggdf = CSV.File("AGG.csv") |> DataFrame

    # filter(:Date => x -> x >= Date("2003-09-30"), spydf)
    # filter(:Date => x -> x >= Date("2003-09-30"), aggdf)

    DataFrames.rename!(spydf, "Adj Close" => :adj_close)
    ratio = spydf.adj_close ./ spydf.Close
    spydf.adj_open = spydf.Open .* ratio

    spyta = TimeArray(spydf.Date, Matrix(spydf[!, [:adj_open, :adj_close]]), [:adj_open, :adj_close])

    DataFrames.rename!(aggdf, "Adj Close" => :adj_close)
    ratio = aggdf.adj_close ./ aggdf.Close
    aggdf.adj_open = aggdf.Open .* ratio

    aggta = TimeArray(aggdf.Date, Matrix(aggdf[!, [:adj_open, :adj_close]]), [:adj_open, :adj_close])

    spyta = spyta[Date(2003, 9, 30):Day(1):Date(2019, 12, 31)]
    aggta = aggta[Date(2003, 9, 30):Day(1):Date(2019, 12, 31)]

    return (;spy = spyta, agg = aggta)
end

########################################
# Simple signals
########################################

"""
Generate `begininng of the month` signal. First day of the timeseries is considered to be non-start, if this assumption is wrong value should be overwritten manually
"""
function generate_bom_signal(ta)
    ts = timestamp(ta)
    res = Vector{Bool}(undef, length(ts))

    for (i, t) in pairs(ts)
        if i == 1 
            res[1] = false
            continue
        end
        res[i] = month(ts[i - 1]) != month(ts[i])
    end

    return TimeArray(ts, res)
end

function generate_buyandhold_signal(ta, k = 1)
    ts = timestamp(ta)
    res = zeros(Bool, length(ts))
    res[k] = true

    return TimeArray(ts, res)
end


struct Broker{T1, T2}
    cash::Float64
    shares::T1
    ratios::T2 # do not like this, should be part of the strategy, not broker
end

"""
Estimate our assets, taking into account our cash, and current prices. `k` define which price we are using, `open` or `close`
"""
function assets(broker, prices, i, k = 2)
    res = broker.cash
    for j in 1:length(prices)
        res += values(prices[j])[i, k] * broker.shares[j]
    end
    return res
end

"""
Everything is hardcoded, sorriamba. Prices should be an array or tuple of 
TimeArrays and they should be in 1 to 1 relation with `ratios` field of `Broker`. 
Signal should be the result of `generate_bom_signal`. All series should have the same size, no date checking is made.
"""
function run(broker::Broker, prices, signal)
    ts = timestamp(signal)
    signal = values(signal)
    equity_curve = Vector{Float64}(undef, length(signal))
    for i in 1:length(signal)
        if signal[i]
            # We've got rebalance signal, it's action time
            a = assets(broker, prices, i, 1) # we are buying in the morning, so we are using `open` price to estimate our current situation.
            for j in 1:length(prices)
                p = values(prices[j])[i, 1] # current price
                delta = floor(Int, a / p * broker.ratios[j]) - broker.shares[j]
                @set! broker.cash -= delta * p
                @set! broker.shares[j] += delta
            end
        end

        equity_curve[i] = assets(broker, prices, i)
    end

    return TimeArray(ts, equity_curve)
end

########################################
# Calculations
########################################

broker = Broker(1_000_000.0, (0, 0), (0.6, 0.4))
spyta, aggta = prep_data();
signal = generate_bom_signal(spyta);

sim1 = run(broker, (spyta, aggta), signal);

broker2 = Broker(1_000_000.0, (0, ), (1.0, ))

buyandhold = generate_buyandhold_signal(spyta, 2)
sim2 = run(broker2, (spyta, ), buyandhold);

plot(sim1, label = "Rebalance 60/40", legend = :topleft)
plot!(sim2, label = "SPY buy&hold")
