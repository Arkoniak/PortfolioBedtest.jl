using ConfigEnv
using AlphaVantage
using DataFrames, CSV
using Dates
using Indicators
using Setfield
using Plots
using BenchmarkTools

dotenv();

########################################
# Downloading data
########################################
df = digital_currency_daily("BTC", datatype = "csv", parser = x -> CSV.File(x.body)) |> DataFrame

df = filter(:timestamp => x -> Date(2019, 1, 1) <= x <= Date(2020, 1, 1), df)
price = df."close (USD)"

sma1 = sma(price; n = 10)
sma2 = sma(price; n = 20)

########################################
# Converting raw data to signal generation
########################################

struct MAH{T}
    ma::T
    mah::T
end

function build_mah(v)
    T = eltype(v)
    res = Vector{MAH{T}}(undef, length(v))
    @inbounds res[1] = MAH(v[1], T(NaN))
    @inbounds for i in 2:length(v)
        res[i] = MAH(v[i], v[i - 1])
    end
    return res
end

sma1 = build_mah(sma1)
sma2 = build_mah(sma2)

function cross_signal(mah1, mah2)
    (mah1.mah < mah2.mah) & (mah1.ma > mah2.ma) && return 1
    (mah1.mah > mah2.mah) & (mah1.ma < mah2.ma) && return -1
    return 0
end

########################################
# Broker and single simulation run
########################################

struct Broker
    cash::Float64
    shares::Int
end

function run(broker, price, sma1, sma2)
    @inbounds for i in eachindex(sma1)
        signal = cross_signal(sma1[i], sma2[i])
        if signal > 0
            p = price[i]
            shares = floor(Int, broker.cash/p)
            @set! broker.shares = shares
            @set! broker.cash -= shares*p
        elseif signal < 0
            broker.shares > 0 || continue # no shorting
            p = price[i]
            @set! broker.cash += broker.shares*p
            @set! broker.shares = 0
        end
    end

    # Cash out
    p = price[end]
    @set! broker.cash += broker.shares*p
    @set! broker.shares = 0

    return broker
end

broker = Broker(1_000_000, 0)

@btime run($broker, $price, $sma1, $sma2)
  # 352.389 ns (0 allocations: 0 bytes)

########################################
# Grid run
########################################

smas = map(n -> sma(price; n = n), 10:100) .|> build_mah

struct SimInfo
    i::Int
    j::Int
    x::Float64
end

function run(broker, price, smas)
    res = SimInfo[]
    for i in 1:length(smas)
        for j in i+1:length(smas)
            sma1 = smas[i]
            sma2 = smas[j]
            out = run(broker, price, sma1, sma2)
            push!(res, SimInfo(i, j, out.cash))
        end
    end
    return res
end

@btime run($broker, $price, $smas);
  # 1.635 ms (12 allocations: 192.55 KiB)

########################################
# Final heatmap 
########################################

res = run(broker, price, smas)

res_dual = map(x -> SimInfo(x.j, x.i, x.x), res)

res_diag = map(i -> SimInfo(i, i, broker.cash), 1:length(smas))

res = vcat(res, res_dual, res_diag)
sort!(res, by = x -> (x.i, x.j))
vals = map(x -> x.x/broker.cash - 1, reshape(res, :, length(smas)))
heatmap(vals, c=cgrad([:blue,:gray,:red]))
savefig("BTC_DMAC.png")
