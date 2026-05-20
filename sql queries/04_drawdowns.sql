-- 04_drawdowns.sql — Drawdown analysis (running max from window functions)

-- For each stock, computes:
--   - Running peak price (max so far)
--   - Drawdown from peak at each date
--   - Max drawdown depth and duration over the full period

-- Demonstrates: MAX() OVER (... ROWS BETWEEN UNBOUNDED PRECEDING),
-- multi-CTE chains, conditional aggregation.

-- Daily drawdown table: running peak and percent below peak.

DROP TABLE IF EXISTS daily_drawdowns;
CREATE TABLE daily_drawdowns AS
SELECT
    symbol,
    date,
    close_adj,
    MAX(close_adj) OVER (
        PARTITION BY symbol
        ORDER BY date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_peak,
    (close_adj / MAX(close_adj) OVER (
        PARTITION BY symbol
        ORDER BY date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )) - 1 AS drawdown
FROM prices;

-- Per-stock drawdown summary: worst drawdown and the date it bottomed.

DROP TABLE IF EXISTS drawdown_summary;
CREATE TABLE drawdown_summary AS
WITH max_dd AS (
    SELECT
        symbol,
        MIN(drawdown) AS max_drawdown
    FROM daily_drawdowns
    GROUP BY symbol
),
trough_dates AS (
    -- Find the date when each stock hit its max drawdown.
    SELECT
        d.symbol,
        d.date AS trough_date,
        d.close_adj AS trough_price,
        d.running_peak AS peak_price,
        d.drawdown,
        ROW_NUMBER() OVER (PARTITION BY d.symbol ORDER BY d.date) AS rn
    FROM daily_drawdowns d
    JOIN max_dd m ON d.symbol = m.symbol AND d.drawdown = m.max_drawdown
)
SELECT
    symbol,
    trough_date,
    peak_price,
    trough_price,
    drawdown AS max_drawdown
FROM trough_dates
WHERE rn = 1  -- if multiple dates tie at the same drawdown, take the first
ORDER BY max_drawdown ASC;

-- "Bad market days" — dates when a large share of S&P 500 stocks fell.
-- Uses conditional aggregation to count negative-return stocks per date.

DROP TABLE IF EXISTS broad_market_drops;
CREATE TABLE broad_market_drops AS
SELECT
    date,
    COUNT(*) AS n_stocks,
    SUM(CASE WHEN daily_return < 0 THEN 1 ELSE 0 END) AS n_down,
    SUM(CASE WHEN daily_return < -0.02 THEN 1 ELSE 0 END) AS n_down_2pct,
    AVG(daily_return) AS mean_return,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY daily_return) AS median_return
FROM daily_returns
GROUP BY date
HAVING SUM(CASE WHEN daily_return < 0 THEN 1 ELSE 0 END) >= 400  -- ≥80% of stocks fell
ORDER BY mean_return ASC;