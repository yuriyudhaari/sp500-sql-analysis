-- 01_returns.sql — Returns analysis at multiple time grains

-- Computes daily, monthly, and annual returns from split-adjusted prices.
-- Uses window functions (LAG) and date-part aggregation.

-- Tables produced:
--   monthly_returns  — first/last close + total return per stock per month
--   annual_returns   — first/last close + total return per stock per year
--   cumulative_returns — total return over the full 4-year period

-- Monthly returns: compounded daily log returns within each calendar month.

DROP TABLE IF EXISTS monthly_returns;
CREATE TABLE monthly_returns AS
WITH month_anchors AS (
    SELECT
        symbol,
        DATE_TRUNC('month', date) AS month_start,
        FIRST_VALUE(close_adj) OVER (
            PARTITION BY symbol, DATE_TRUNC('month', date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS month_open,
        LAST_VALUE(close_adj) OVER (
            PARTITION BY symbol, DATE_TRUNC('month', date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS month_close,
        COUNT(*) OVER (PARTITION BY symbol, DATE_TRUNC('month', date)) AS trading_days
    FROM prices
)
SELECT DISTINCT
    symbol,
    month_start,
    month_open,
    month_close,
    (month_close / month_open) - 1 AS monthly_return,
    trading_days
FROM month_anchors
ORDER BY symbol, month_start;

-- Annual returns: same pattern at the year grain.

DROP TABLE IF EXISTS annual_returns;
CREATE TABLE annual_returns AS
WITH year_anchors AS (
    SELECT
        symbol,
        EXTRACT(year FROM date) AS year,
        FIRST_VALUE(close_adj) OVER (
            PARTITION BY symbol, EXTRACT(year FROM date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS year_open,
        LAST_VALUE(close_adj) OVER (
            PARTITION BY symbol, EXTRACT(year FROM date)
            ORDER BY date
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        ) AS year_close,
        COUNT(*) OVER (PARTITION BY symbol, EXTRACT(year FROM date)) AS trading_days
    FROM prices
)
SELECT DISTINCT
    symbol,
    year,
    year_open,
    year_close,
    (year_close / year_open) - 1 AS annual_return,
    trading_days
FROM year_anchors
ORDER BY symbol, year;

-- Cumulative returns over the entire period (Jan 2014 — Dec 2017).
-- Only includes symbols with the full trading history (≥1000 days).

DROP TABLE IF EXISTS cumulative_returns;
CREATE TABLE cumulative_returns AS
WITH bookends AS (
    SELECT
        symbol,
        MIN(date) AS start_date,
        MAX(date) AS end_date,
        COUNT(*) AS n_days
    FROM prices
    GROUP BY symbol
)
SELECT
    b.symbol,
    b.n_days,
    b.start_date,
    b.end_date,
    p_start.close_adj AS start_price,
    p_end.close_adj AS end_price,
    (p_end.close_adj / p_start.close_adj) - 1 AS cumulative_return,
    -- Annualized: (1 + total_return)^(1/years) - 1
    POWER(p_end.close_adj / p_start.close_adj, 252.0 / b.n_days) - 1 AS annualized_return
FROM bookends b
JOIN prices p_start ON b.symbol = p_start.symbol AND b.start_date = p_start.date
JOIN prices p_end   ON b.symbol = p_end.symbol   AND b.end_date   = p_end.date
WHERE b.n_days >= 1000
ORDER BY cumulative_return DESC;