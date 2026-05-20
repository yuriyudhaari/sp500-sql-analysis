-- 05_correlations.sql — Pairwise return correlations

-- Demonstrates self-joins on the daily_returns table and the CORR() aggregate.
-- Pairwise computation across 480+ symbols is O(n²) — restrict to a meaningful
-- subset (top 50 by absolute cumulative return) to keep the query tractable
-- and the result interpretable.

-- Select the universe for pairwise comparison: the 50 stocks with the
-- largest absolute moves (best gainers and worst losers combined).

DROP TABLE IF EXISTS correlation_universe;
CREATE TABLE correlation_universe AS
SELECT symbol
FROM cumulative_returns
ORDER BY ABS(cumulative_return) DESC
LIMIT 50;

-- All pairwise correlations within the universe.
-- Self-join on date, then aggregate with CORR over the joined return series.
-- Filter symbol_a < symbol_b to avoid duplicate pairs and self-correlations.

DROP TABLE IF EXISTS pairwise_correlations;
CREATE TABLE pairwise_correlations AS
SELECT
    a.symbol AS symbol_a,
    b.symbol AS symbol_b,
    CORR(a.daily_return, b.daily_return) AS correlation,
    COUNT(*) AS n_joint_obs
FROM daily_returns a
JOIN daily_returns b ON a.date = b.date
WHERE a.symbol < b.symbol
  AND a.symbol IN (SELECT symbol FROM correlation_universe)
  AND b.symbol IN (SELECT symbol FROM correlation_universe)
GROUP BY a.symbol, b.symbol
HAVING COUNT(*) >= 500  -- require enough joint history
;

-- Top 20 most-correlated pairs.

DROP TABLE IF EXISTS top_correlated_pairs;
CREATE TABLE top_correlated_pairs AS
SELECT *
FROM pairwise_correlations
ORDER BY correlation DESC
LIMIT 20;

-- Top 20 most anti-correlated pairs.

DROP TABLE IF EXISTS bottom_correlated_pairs;
CREATE TABLE bottom_correlated_pairs AS
SELECT *
FROM pairwise_correlations
ORDER BY correlation ASC
LIMIT 20;