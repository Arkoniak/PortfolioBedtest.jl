using ConfigEnv
using CSV, DataFrames
using AlphaVantage

dotenv()

df1 = time_series_daily_adjusted("SPY", outputsize = "full", datatype = "csv", parser = x -> CSV.File(IOBuffer(x.body))) |> DataFrame
sort!(df1, :timestamp)
rename!(df1, :timestamp => :Date)
rename!(df1, :adjusted_close => "Adj Close")
rename!(df1, :open => :Open)
rename!(df1, :close => :Close)
rename!(df1, :high => :High)
rename!(df1, :low => :Low)
rename!(df1, :volume => :Volume)
CSV.write("SPY.csv", df1)

df2 = time_series_daily_adjusted("AGG", outputsize = "full", datatype = "csv", parser = x -> CSV.File(IOBuffer(x.body))) |> DataFrame
sort!(df2, :timestamp)
rename!(df2, :timestamp => :Date)
rename!(df2, :adjusted_close => "Adj Close")
rename!(df2, :open => :Open)
rename!(df2, :close => :Close)
rename!(df2, :high => :High)
rename!(df2, :low => :Low)
rename!(df2, :volume => :Volume)
CSV.write("AGG.csv", df2)
