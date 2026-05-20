-- 03_rankings.sql — Performance rankings and multi-criteria leaderboards

-- Demonstrates RANK(), DENSE_RANK(), ROW_NUMBER(), NTILE() window functions
-- applied to cumulative-return and volatility data.

-- Top 20 and bottom 20 performers by cumulative return over the full period.

DROP TABLE IF EXISTS performance_rankings;
CREATE TABLE performance_rankings AS
SELECT
    symbol,
    cumulative_return,
    annualized_return,
    RANK() OVER (ORDER BY cumulative_return DESC) AS rank_best,
    RANK() OVER (ORDER BY cumulative_return ASC) AS rank_worst,
    NTILE(5) OVER (ORDER BY cumulative_return) AS return_quintile
FROM cumulative_returns;

-- Top 20 best and bottom 20 worst performers (full period).

DROP TABLE IF EXISTS top_bottom_performers;
CREATE TABLE top_bottom_performers AS
SELECT
    symbol,
    cumulative_return,
    annualized_return,
    rank_best,
    'TOP' AS bucket
FROM performance_rankings
WHERE rank_best <= 20
UNION ALL
SELECT
    symbol,
    cumulative_return,
    annualized_return,
    rank_worst AS rank_best,
    'BOTTOM' AS bucket
FROM performance_rankings
WHERE rank_worst <= 20
ORDER BY bucket DESC, rank_best;

-- Year-by-year leadership: which 5 stocks led each calendar year.
-- Uses RANK() within the year partition.

DROP TABLE IF EXISTS yearly_leaders;
CREATE TABLE yearly_leaders AS
WITH ranked AS (
    SELECT
        year,
        symbol,
        annual_return,
        RANK() OVER (PARTITION BY year ORDER BY annual_return DESC) AS year_rank
    FROM annual_returns
    WHERE trading_days >= 200  -- only stocks present for most of the year
)
SELECT *
FROM ranked
WHERE year_rank <= 5
ORDER BY year, year_rank;

-- Risk-adjusted leaders: return/volatility quintile cross-tabulation.
-- High return + low vol = strongest risk-adjusted profile.

DROP TABLE IF EXISTS risk_return_grid;
CREATE TABLE risk_return_grid AS
WITH joined AS (
    SELECT
        c.symbol,
        c.cumulative_return,
        c.annualized_return,
        v.vol_annualized,
        v.return_to_vol_ratio,
        NTILE(5) OVER (ORDER BY c.cumulative_return) AS return_quintile,
        NTILE(5) OVER (ORDER BY v.vol_annualized) AS vol_quintile
    FROM cumulative_returns c
    JOIN volatility_summary v ON c.symbol = v.symbol
)
SELECT
    return_quintile,
    vol_quintile,
    COUNT(*) AS n_stocks,
    AVG(annualized_return) AS avg_annualized_return,
    AVG(vol_annualized) AS avg_vol_annualized,
    AVG(return_to_vol_ratio) AS avg_return_to_vol
FROM joined
GROUP BY return_quintile, vol_quintile
ORDER BY return_quintile DESC, vol_quintile;