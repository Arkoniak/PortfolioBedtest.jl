var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = PortfolioBedtest","category":"page"},{"location":"#PortfolioBedtest","page":"Home","title":"PortfolioBedtest","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Documentation for PortfolioBedtest.","category":"page"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [PortfolioBedtest]","category":"page"},{"location":"#PortfolioBedtest.YahooOpt","page":"Home","title":"PortfolioBedtest.YahooOpt","text":"struct YahooOpt <: AbstractQueryOpt\n  period1  # the start time\n  period2  # the end time\n  interval # \"1d\", \"1wk\" or \"1mo\"\n  events   # currently only `:history` supported\nend\n\nThe Yahoo Finance HTTP API query object.\n\nExamples\n\njulia> t = Dates.now()\n2020-08-09T01:38:04.735\njulia> YahooOpt(period1 = t - Year(2), period2 = t)\nYahooOpt{DateTime} with 4 entries:\n  :period1  => 1533778685\n  :period2  => 1596937085\n  :interval => \"1d\"\n  :events   => :history\n\n\n\n\n\n","category":"type"}]
}
