using CSV, DataFrames
using Dates
using TimeSeries

spydf = CSV.File("SPY.csv") |> DataFrame;
aggdf = CSV.File("AGG.csv") |> DataFrame;

filter(:Date => x -> x >= Date("2003-09-30"), spydf)
filter(:Date => x -> x >= Date("2003-09-30"), aggdf)

first(spydf[:, 2:6], 6) |> Matrix


DataFrames.rename!(spydf, "Adj Close" => :adj_close)
ratio = spydf.adj_close ./ spydf.Close
spydf.adj_open = spydf.Open .* ratio
spydf[!, [:adj_open, :adj_close]]

ta = TimeArray(spydf.Date, Matrix(spydf[!, [:adj_open, :adj_close]]), [:adj_open, :adj_close])

timestamp(ta)
ta2 = ta[Date(2003, 9, 30):Day(1):Date(2003, 10, 30)]

values(ta2)

a, b, c = 1, 2, 3

(a > b) *(b >= c)
(a - b)*(b - c) >=0

xor((a>b), (b>=c))

((a > b)&(b>=c)) | ((a < b)&(b < c))
xor(false, true)

using BenchmarkTools

f1(a, b, c) = (a == b) | (b == c) | ((a > b)&(b>c)) | ((a < b)&(b < c))
f2(a, b, c) = (a - b)*(b - c) >= 0
f3(a, b, c) = (a == b) | (b == c) | xor(a > b, b < c)

@btime f1($(Ref(a))[], $(Ref(b))[], $(Ref(c))[])
@btime f2($(Ref(a))[], $(Ref(b))[], $(Ref(c))[])
@btime f3($(Ref(a))[], $(Ref(b))[], $(Ref(c))[])
a, b, c = 100000000, 100000001, 100000002
