-- 02_volatility.sql — Rolling and full-period volatility

-- Daily return volatility computed at two grains:
--   1. Rolling 30-day standard deviation (annualized via sqrt(252))
--   2. Full-period annualized volatility per symbol

-- Uses window functions with frame clauses (ROWS BETWEEN N PRECEDING ...).

-- Rolling 30-day volatility, annualized.
-- The trading-day convention is 252 days/year; sqrt(252) ≈ 15.87.

DROP TABLE IF EXISTS rolling_volatility;
CREATE TABLE rolling_volatility AS
SELECT
    symbol,
    date,
    daily_return,
    STDDEV_SAMP(daily_return) OVER (
        PARTITION BY symbol
        ORDER BY date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) * SQRT(252) AS rolling_30d_vol_annualized,
    AVG(daily_return) OVER (
        PARTITION BY symbol
        ORDER BY date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ) * 252 AS rolling_30d_mean_annualized
FROM daily_returns;

-- Full-period volatility per symbol.
-- Restricted to symbols with the full history to make values comparable.

DROP TABLE IF EXISTS volatility_summary;
CREATE TABLE volatility_summary AS
WITH per_symbol AS (
    SELECT
        symbol,
        COUNT(*) AS n_days,
        AVG(daily_return) * 252 AS mean_annualized,
        STDDEV_SAMP(daily_return) * SQRT(252) AS vol_annualized,
        MIN(daily_return) AS worst_day,
        MAX(daily_return) AS best_day
    FROM daily_returns
    GROUP BY symbol
    HAVING COUNT(*) >= 1000
)
SELECT
    symbol,
    n_days,
    mean_annualized,
    vol_annualized,
    -- Sharpe-like ratio (assumes 0% risk-free rate for simplicity)
    mean_annualized / NULLIF(vol_annualized, 0) AS return_to_vol_ratio,
    worst_day,
    best_day
FROM per_symbol
ORDER BY vol_annualized DESC;