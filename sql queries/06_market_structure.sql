-- 06_market_structure.sql — Equal-weighted index and market-wide patterns

-- Constructs a simple equal-weighted index from the underlying data and uses
-- it to study market-wide structure: returns over time, cross-sectional
-- dispersion, volume regimes.

-- Demonstrates: aggregation at the date grain, ratio calculations against a
-- baseline, percentile and dispersion measures.

-- Equal-weighted index: average daily return across all stocks each date,
-- then compound to get a cumulative index value.
-- Restricted to full-history stocks for consistency.

DROP TABLE IF EXISTS ew_index_daily;
CREATE TABLE ew_index_daily AS
WITH full_history_symbols AS (
    SELECT symbol FROM cumulative_returns  -- already filtered to n_days >= 1000
),
ew_returns AS (
    SELECT
        date,
        AVG(daily_return) AS ew_daily_return,
        COUNT(*) AS n_stocks,
        STDDEV_SAMP(daily_return) AS cross_section_dispersion,
        MIN(daily_return) AS worst_stock_return,
        MAX(daily_return) AS best_stock_return
    FROM daily_returns
    WHERE symbol IN (SELECT symbol FROM full_history_symbols)
    GROUP BY date
)
SELECT
    date,
    ew_daily_return,
    n_stocks,
    cross_section_dispersion,
    worst_stock_return,
    best_stock_return,
    -- Cumulative index value starting from 100 on day 1
    100.0 * EXP(SUM(LN(1.0 + ew_daily_return)) OVER (ORDER BY date)) AS ew_index_level
FROM ew_returns
ORDER BY date;

-- Annual summary of the equal-weighted index.

DROP TABLE IF EXISTS ew_index_annual;
CREATE TABLE ew_index_annual AS
WITH year_bookends AS (
    SELECT
        EXTRACT(year FROM date) AS year,
        FIRST_VALUE(ew_index_level) OVER (
            PARTITION BY EXTRACT(year FROM date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS year_open,
        LAST_VALUE(ew_index_level) OVER (
            PARTITION BY EXTRACT(year FROM date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS year_close
    FROM ew_index_daily
)
SELECT DISTINCT
    year,
    year_open,
    year_close,
    (year_close / year_open) - 1 AS annual_return
FROM year_bookends
ORDER BY year;

-- Volume regimes — characterize each calendar month by aggregate volume
-- relative to the trailing average.

DROP TABLE IF EXISTS monthly_volume_regimes;
CREATE TABLE monthly_volume_regimes AS
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', date) AS month_start,
        SUM(volume_adj) AS total_volume,
        AVG(daily_return) AS avg_return,
        STDDEV_SAMP(daily_return) AS realized_vol
    FROM daily_returns
    GROUP BY DATE_TRUNC('month', date)
),
with_baseline AS (
    SELECT
        month_start,
        total_volume,
        avg_return,
        realized_vol,
        AVG(total_volume) OVER (
            ORDER BY month_start
            ROWS BETWEEN 6 PRECEDING AND 1 PRECEDING
        ) AS trailing_6m_avg_volume
    FROM monthly
)
SELECT
    month_start,
    total_volume,
    trailing_6m_avg_volume,
    CASE
        WHEN total_volume > 1.3 * trailing_6m_avg_volume THEN 'HIGH'
        WHEN total_volume < 0.7 * trailing_6m_avg_volume THEN 'LOW'
        ELSE 'NORMAL'
    END AS volume_regime,
    avg_return * 21 AS month_avg_return,  -- approx monthly return
    realized_vol * SQRT(21) AS month_realized_vol
FROM with_baseline
ORDER BY month_start;