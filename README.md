# S&P 500 Stock Price Analysis (2014–2017)

Historical analysis of daily prices for ~505 S&P 500 constituents over 1,007 trading days, using PostgreSQL for analytical SQL and Python for orchestration and visualization.

Backward-looking analysis only. Not investment advice. Not predictive.

## Findings

1. **NVDA returned 1,120%** over 2014–2017, the start of the GPU/AI rally. Top performers were dominated by semiconductors (AVGO, SWKS, LRCX), gaming (EA, ATVI), and streaming (NFLX, FB).

2. **The energy sector was destroyed.** CHK lost 85%, RRC -79%, multiple oil & gas names (NOV, MRO, APA, KMI) lost more than half their value as oil collapsed from $100 to $30/barrel.

3. **CHK had a 95% maximum drawdown** — from $31.30 down to $1.59 in February 2016, the bottom of the oil panic.

4. **Worst market days line up with known macro events:** August 24, 2015 (China yuan devaluation / "Black Monday"), June 24, 2016 (Brexit vote), the Aug–Sep 2015 China growth scare.

5. **Pairwise correlations cluster by industry.** AMAT/LRCX (semi equipment) at 0.74, UNH/AET/ANTM (health insurance) at 0.68–0.69. Stocks in the same industry share common drivers.

6. **The equal-weighted index gained ~55%** over the 4 years: +16.5% in 2014, -1.1% in 2015, +15.3% in 2016, +16.9% in 2017.

## Stack

- **PostgreSQL** for analytical SQL (window functions, CTEs, self-joins, COPY FROM bulk loading)
- **Python** (psycopg2, SQLAlchemy, pandas, matplotlib) for orchestration and visualization
- **Jupyter** notebook as the narrative layer

## Pipeline

```
data_raw.csv (497K rows)
    │
    ├── etl.py             →  Postgres: prices, daily_returns, split_events (via COPY FROM)
    ├── run_queries.py     →  runs all queries/*.sql, populates 18 analytical tables
    └── visualize.py       →  figures/*.png
```

## SQL queries

Each query file is a standalone, runnable artifact:

| File | Demonstrates |
|---|---|
| `queries/01_returns.sql` | Window functions (FIRST_VALUE, LAST_VALUE), date-grain aggregation |
| `queries/02_volatility.sql` | Rolling window stats (STDDEV_SAMP OVER ROWS BETWEEN) |
| `queries/03_rankings.sql` | RANK, DENSE_RANK, NTILE, multi-criteria leaderboards |
| `queries/04_drawdowns.sql` | Running max via MAX OVER (UNBOUNDED PRECEDING), PERCENTILE_CONT |
| `queries/05_correlations.sql` | Self-joins, CORR() aggregate, pairwise computation |
| `queries/06_market_structure.sql` | Date-grain aggregation, cumulative compounding, regime classification |

## Setup

### 1. Install PostgreSQL

On Windows, install from [postgresql.org](https://www.postgresql.org/download/windows/). During install, set a password for the `postgres` superuser.

On macOS:
```bash
brew install postgresql@16
brew services start postgresql@16
```

### 2. Create the database

Open psql (or pgAdmin) and run:
```sql
CREATE DATABASE sp500;
```

### 3. Configure the connection

The scripts read the connection string from `db.py`. Edit `DATABASE_URL` to match your local setup, or set it as an environment variable:

```bash
# Windows PowerShell
$env:DATABASE_URL = "postgresql://postgres:YOUR_PASSWORD@localhost:5432/sp500"

# macOS/Linux
export DATABASE_URL="postgresql://postgres:YOUR_PASSWORD@localhost:5432/sp500"
```

Default if unset: `postgresql://postgres:postgres@localhost:5432/sp500`.

### 4. Run the pipeline

```bash
pip install -r requirements.txt
python etl.py             # loads CSV via COPY FROM, builds prices and daily_returns
python run_queries.py     # runs all 6 SQL files in order
python visualize.py       # generates 7 figures
# Open 01_notebook.ipynb for the narrative
```

The raw dataset is not in this repo. Save the S&P 500 daily prices CSV (Kaggle: "S&P 500 stock data" by camnugent) to the project root as `data_raw.csv`.

## Files

| File | Purpose |
|---|---|
| `01_notebook.ipynb` | Narrative + tables + charts |
| `methodology.md` | Cleaning decisions, split detection, limitations |
| `db.py` | Database connection helper |
| `etl.py` | CSV → Postgres via COPY FROM, with split detection and adjustment |
| `run_queries.py` | Runs all SQL files in order |
| `visualize.py` | Generates the seven figure files |
| `queries/*.sql` | The actual SQL — 6 files |
| `requirements.txt` | Python dependencies |
| `figures/` | Output charts |

## Limitations

- Split detection is heuristic (magnitude-based). Catches real splits but also some large news moves; a production pipeline would use a corporate-actions feed.
- No sector data in this dataset. Sector analysis would require an external mapping.
- No fundamentals. Prices only.
- 2014–2017 was a bull market. Findings don't generalize.
- No survivorship adjustment.
