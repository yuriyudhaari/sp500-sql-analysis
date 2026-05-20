"""
Phase A: ETL pipeline (PostgreSQL).
Loads the raw S&P 500 CSV into a PostgreSQL database with:
- Proper types and a primary key on (symbol, date)
- Stock split detection (heuristic: |daily return| > 35%) and split-adjusted
  price columns
- Quality flag columns
Uses psycopg2's COPY FROM for fast bulk loading (10-50x faster than INSERT).
"""

from db import get_connection

RAW_CSV = "data_raw.csv"
SPLIT_THRESHOLD = 0.35


def build_database():
    """Run the full ETL into the configured PostgreSQL database."""
    conn = get_connection()
    cur = conn.cursor()

    #Drop tables if rerunning
    cur.execute("""
        DROP TABLE IF EXISTS daily_returns CASCADE;
        DROP TABLE IF EXISTS prices CASCADE;
        DROP TABLE IF EXISTS split_events CASCADE;
        DROP TABLE IF EXISTS prices_raw CASCADE;
    """)

    #Create raw table and bulk-load via COPY
    cur.execute("""
        CREATE TABLE prices_raw (
            symbol TEXT NOT NULL,
            date   DATE NOT NULL,
            open   DOUBLE PRECISION,
            high   DOUBLE PRECISION,
            low    DOUBLE PRECISION,
            close  DOUBLE PRECISION,
            volume BIGINT
        );
    """)

    print(f"Loading {RAW_CSV} via COPY...")
    with open(RAW_CSV, "r") as f:
        #Skip the header line. COPY reads remaining rows directly.
        next(f)
        cur.copy_expert(
            "COPY prices_raw (symbol, date, open, high, low, close, volume) "
            "FROM STDIN WITH (FORMAT csv)",
            f,
        )
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM prices_raw")
    raw_count = cur.fetchone()[0]
    print(f"Loaded raw: {raw_count:,} rows")

    #Add primary key + index for downstream query performance
    cur.execute("""
        ALTER TABLE prices_raw ADD PRIMARY KEY (symbol, date);
        CREATE INDEX idx_prices_raw_date ON prices_raw (date);
    """)
    conn.commit()

    #Detect splits
    #Any single-day return whose magnitude exceeds the threshold is a split
    #candidate. We store the adjustment factor (= new / old) for use later.
    cur.execute(f"""
        CREATE TABLE split_events AS
        WITH returns AS (
            SELECT
                symbol,
                date,
                close,
                LAG(close) OVER (PARTITION BY symbol ORDER BY date) AS prev_close,
                close / LAG(close) OVER (PARTITION BY symbol ORDER BY date) AS price_ratio
            FROM prices_raw
        )
        SELECT
            symbol,
            date,
            prev_close,
            close,
            price_ratio,
            price_ratio AS adjustment_factor
        FROM returns
        WHERE prev_close IS NOT NULL
          AND ABS(price_ratio - 1.0) > {SPLIT_THRESHOLD};
    """)
    conn.commit()

    cur.execute("SELECT COUNT(*) FROM split_events")
    splits = cur.fetchone()[0]
    print(f"Split candidates detected: {splits}")

    # Examples
    cur.execute("""
        SELECT symbol, date, prev_close, close, adjustment_factor
        FROM split_events
        ORDER BY ABS(adjustment_factor - 1.0) DESC
        LIMIT 10
    """)
    print("\nLargest split candidates (likely splits or major corporate events):")
    print(f"{'symbol':<8}{'date':<14}{'prev_close':>12}{'close':>10}{'factor':>10}")
    for r in cur.fetchall():
        print(f"{r[0]:<8}{str(r[1]):<14}{r[2]:>12.2f}{r[3]:>10.2f}{r[4]:>10.4f}")

    #Build adjusted prices
    #Multiply each row's price by the cumulative product of all split adjustment
    #factors occurring on dates STRICTLY AFTER this row's date.
    cur.execute("""
        CREATE TABLE prices AS
        WITH adj AS (
            SELECT
                p.symbol,
                p.date,
                p.open,
                p.high,
                p.low,
                p.close,
                p.volume,
                COALESCE(
                    (SELECT EXP(SUM(LN(s.adjustment_factor)))
                     FROM split_events s
                     WHERE s.symbol = p.symbol AND s.date > p.date),
                    1.0
                ) AS cum_adj_factor
            FROM prices_raw p
        )
        SELECT
            symbol,
            date,
            open  AS open_raw,
            high  AS high_raw,
            low   AS low_raw,
            close AS close_raw,
            volume AS volume_raw,
            open  * cum_adj_factor AS open_adj,
            high  * cum_adj_factor AS high_adj,
            low   * cum_adj_factor AS low_adj,
            close * cum_adj_factor AS close_adj,
            -- Volume is inversely adjusted: a 2-for-1 split halves the price but
            -- doubles the share count, so historical volume should be doubled.
            (volume / cum_adj_factor)::BIGINT AS volume_adj,
            cum_adj_factor
        FROM adj;
    """)
    conn.commit()

    cur.execute("""
        ALTER TABLE prices ADD PRIMARY KEY (symbol, date);
        CREATE INDEX idx_prices_date ON prices (date);
        CREATE INDEX idx_prices_symbol ON prices (symbol);
    """)
    conn.commit()

    #Build the daily_returns derived table
    cur.execute(f"""
        CREATE TABLE daily_returns AS
        WITH base AS (
            SELECT
                symbol,
                date,
                close_adj,
                LAG(close_adj) OVER (PARTITION BY symbol ORDER BY date) AS prev_close_adj,
                volume_adj
            FROM prices
        )
        SELECT
            symbol,
            date,
            close_adj,
            prev_close_adj,
            (close_adj / prev_close_adj) - 1 AS daily_return,
            LN(close_adj / prev_close_adj) AS log_return,
            volume_adj,
            CASE
                WHEN ABS((close_adj / prev_close_adj) - 1) > {SPLIT_THRESHOLD}
                THEN TRUE ELSE FALSE
            END AS extreme_move_flag
        FROM base
        WHERE prev_close_adj IS NOT NULL;
    """)
    conn.commit()

    cur.execute("""
        ALTER TABLE daily_returns ADD PRIMARY KEY (symbol, date);
        CREATE INDEX idx_daily_returns_date ON daily_returns (date);
    """)
    conn.commit()

    #Summary
    cur.execute("""
        SELECT
            (SELECT COUNT(*) FROM prices),
            (SELECT COUNT(DISTINCT symbol) FROM prices),
            (SELECT COUNT(DISTINCT date) FROM prices),
            (SELECT MIN(date) FROM prices),
            (SELECT MAX(date) FROM prices),
            (SELECT COUNT(*) FROM daily_returns),
            (SELECT COUNT(*) FROM daily_returns WHERE extreme_move_flag)
    """)
    r = cur.fetchone()
    print(f"\n--- Database summary ---")
    print(f"  prices table:           {r[0]:,} rows")
    print(f"  unique symbols:         {r[1]:,}")
    print(f"  unique trading days:    {r[2]:,}")
    print(f"  date range:             {r[3]} to {r[4]}")
    print(f"  daily_returns table:    {r[5]:,} rows")
    print(f"  residual extreme moves: {r[6]} (after split adjustment)")

    cur.close()
    conn.close()
    print(f"\nETL complete.")


if __name__ == "__main__":
    build_database()