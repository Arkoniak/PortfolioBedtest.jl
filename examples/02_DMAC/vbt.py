# https://polakowo.io/vectorbt/docs/#example
import numpy as np
import pandas as pd
from datetime import datetime

import vectorbt as vbt

# Prepare data
start = datetime(2019, 1, 1)
end = datetime(2020, 1, 1)
btc_price = vbt.YFData.download('BTC-USD', start=start, end=end).get('Close')

fast_ma = vbt.MA.run(btc_price, 10, short_name='fast')
slow_ma = vbt.MA.run(btc_price, 20, short_name='slow')

entries = fast_ma.ma_above(slow_ma, crossover=True)
exits = fast_ma.ma_below(slow_ma, crossover=True)

portfolio = vbt.Portfolio.from_signals(btc_price, entries, exits)

portfolio.total_return()

fast_ma = vbt.MA.run(btc_price, [10, 20], short_name='fast')
slow_ma = vbt.MA.run(btc_price, [30, 30], short_name='slow')

entries = fast_ma.ma_above(slow_ma, crossover=True)
exits = fast_ma.ma_below(slow_ma, crossover=True)
portfolio = vbt.Portfolio.from_signals(btc_price, entries, exits)

portfolio.total_return()
