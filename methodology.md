# Methodology

## Data

Daily OHLCV (open/high/low/close/volume) prices for ~505 S&P 500 constituent stocks, January 2014 to December 2017. 497,472 rows, 1,007 trading days.

Source: publicly available S&P 500 dataset. Each row is one trading day for one symbol.

## Cleaning

### Missing values
27 missing values across `open`/`high`/`low` (less than 0.01% of rows). Stored as NULL in Postgres. No imputation; daily returns simply skip rows where the prior close is missing.

### Symbols with partial history
20 symbols have fewer than 900 trading days because they were added to the index mid-period (DWDP from the DowDuPont merger, BHF from MetLife spinoff, FTV from Fortive spinoff, etc.). Cumulative-return and correlation analyses filter to symbols with ≥1,000 trading days. Other analyses include partial-history symbols where appropriate.

### Stock splits and corporate actions
The raw CSV is not split-adjusted. A stock that does a 2-for-1 split appears in the data as a 50% one-day "crash" with no real economic event.

**Detection:** flag any single-day absolute return >35% as a split candidate. Catches all routine splits (50% moves for 2-for-1, 67% for 3-for-1, etc.) plus a few large news-driven moves.

**Adjustment:** multiply all historical prices for the symbol by the cumulative product of split factors that occur on or after each date. Standard back-adjustment — historical prices are scaled to the most-recent scale.

**11 events detected** in the 2014–2017 period:

| Symbol | Date | Likely event |
|---|---|---|
| DISCK | 2014-08-07 | 2-for-1 split |
| DISCA | 2014-08-07 | 2-for-1 split |
| VRTX | 2014-06-24 | News (cystic fibrosis drug approval) |
| BAX | 2015-07-01 | Baxalta spinoff |
| EBAY | 2015-07-20 | PayPal spinoff |
| NI | 2015-07-02 | Columbia Pipeline spinoff |
| AMD | 2016-04-22 | News (earnings beat) |
| LNT | 2016-05-19 | 2-for-1 split |
| LNT | 2016-05-20 | continuation |
| NWL | 2017-09-15 | News |

The AMD and VRTX events are not splits — they are real price discovery. Adjusting them slightly understates those stocks' volatility but does not materially affect downstream analyses. A production pipeline would use a corporate-actions feed.

### Volume adjustment
Volume is inversely adjusted by the same factor — a 2-for-1 split doubles the share count, so historical volume is multiplied by 2 to make pre- and post-split volumes comparable on a like-for-like basis.

## Database design

PostgreSQL 16, single schema (`public`). Tables organized in layers:

- **Raw**: `prices_raw` — CSV-loaded data, primary key on (symbol, date)
- **Cleaned**: `prices`, `split_events` — adjusted prices and detected splits
- **Derived**: `daily_returns` — log and simple returns computed via LAG window function
- **Analytical** (18 tables): returns at various grains, rankings, drawdowns, correlations, market structure

Indexes on `(symbol, date)` and `date` for query performance.

### Bulk loading
The ETL uses `psycopg2.copy_expert` with `COPY FROM STDIN` to load the CSV directly into Postgres. This is 10–50x faster than `INSERT` or pandas `to_sql` for bulk loads. 497K rows load in approximately 5 seconds on modest hardware.

## Returns

### Daily returns
Computed as `close_adj / prev_close_adj - 1` using split-adjusted closes. Log returns also stored for compounding calculations.

### Monthly and annual returns
Ratio of last close in period to first close in period — not the sum of daily returns. Correctly handles compounding within the period.

### Cumulative returns
Same approach over the full 4-year period. Restricted to symbols with ≥1,000 trading days to make values comparable.

### Annualized return
`(1 + total_return)^(252 / n_days) - 1`. 252 trading days per year is the standard convention.

## Volatility

### Rolling 30-day volatility
Standard deviation of daily returns over a trailing 30-day window, multiplied by `sqrt(252)` to annualize.

### Full-period volatility
Same formula over the entire history per symbol. Restricted to full-history symbols.

### Return-to-volatility ratio
Annualized mean return divided by annualized volatility. Analogous to a Sharpe ratio with a 0% risk-free rate. Descriptive only, not tradable.

## Drawdowns

### Daily drawdown
For each date and symbol, the running maximum close from the start of history to the current date, minus 1. Computed with `MAX(close_adj) OVER (PARTITION BY symbol ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`.

### Maximum drawdown
The deepest drawdown over the full history. Reported with the date of the trough.

### Broad market drops
Days when ≥80% of stocks fell (n_down ≥ 400 of ~500). Used to identify market-wide stress events. Median return computed using `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY daily_return)` — Postgres's ordered-set aggregate.

## Correlations

Restricted to the 50 stocks with the largest absolute cumulative returns. All-pairs computation across all 480 full-history symbols would be ~115,000 pair-correlations — too many to be interpretable.

Computed using Postgres's `CORR()` aggregate over the joined daily-return series, with `a.symbol < b.symbol` to avoid duplicate pairs.

## Equal-weighted index

For each date, the simple average of all full-history symbols' daily returns. Compounded to produce a cumulative index level starting at 100. Research index, not tradable, not directly comparable to the cap-weighted S&P 500.

## Limitations

- Future price movements are not predictable from this data
- Individual stocks cannot be classified as over- or undervalued from this data
- Trading strategies are not modeled (no costs, slippage, taxes)
- Causal relationships not identified — only correlations and patterns
- Performance outside the 2014–2017 bull-market period would look different
- Survivorship bias: companies delisted before mid-2014 are not in the data
- Index churn: some "Bottom 15 performers" may have been removed from the index after their decline