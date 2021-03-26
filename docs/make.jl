using PortfolioBedtest
using Documenter

DocMeta.setdocmeta!(PortfolioBedtest, :DocTestSetup, :(using PortfolioBedtest); recursive=true)

makedocs(;
    modules=[PortfolioBedtest],
    authors="Andrey Oskin",
    repo="https://github.com/Arkoniak/PortfolioBedtest.jl/blob/{commit}{path}#{line}",
    sitename="PortfolioBedtest.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://Arkoniak.github.io/PortfolioBedtest.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/Arkoniak/PortfolioBedtest.jl",
)
