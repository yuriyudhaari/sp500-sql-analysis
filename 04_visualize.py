"""
Generate visualizations from the Postgres analytical tables.
Run after etl.py and run_queries.py.
"""

import os
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

from db import get_engine

sns.set_style("whitegrid")
plt.rcParams["figure.dpi"] = 110
plt.rcParams["savefig.dpi"] = 140
plt.rcParams["font.size"] = 10

os.makedirs("figures", exist_ok=True)
engine = get_engine()


#1. Equal-weighted index over time
ew = pd.read_sql("SELECT date, ew_index_level FROM ew_index_daily ORDER BY date", engine)
fig, ax = plt.subplots(figsize=(11, 4.5))
ax.plot(ew["date"], ew["ew_index_level"], color="#2c3e50", linewidth=1.5)
ax.axhline(100, color="grey", linestyle="--", alpha=0.4, label="Starting value")
ax.set_xlabel("Date")
ax.set_ylabel("Index level (start = 100)")
ax.set_title("Equal-weighted S&P 500 index, 2014–2017")
ax.legend()
plt.tight_layout()
plt.savefig("figures/01_ew_index.png")
plt.close()


#2. Top and bottom 15 performers
top = pd.read_sql("""
    SELECT symbol, cumulative_return FROM top_bottom_performers
    WHERE bucket = 'TOP' AND rank_best <= 15 ORDER BY rank_best
""", engine)
bot = pd.read_sql("""
    SELECT symbol, cumulative_return FROM top_bottom_performers
    WHERE bucket = 'BOTTOM' AND rank_best <= 15 ORDER BY rank_best
""", engine)

fig, axes = plt.subplots(1, 2, figsize=(12, 5))
axes[0].barh(top["symbol"][::-1], top["cumulative_return"][::-1] * 100, color="#27ae60")
axes[0].set_xlabel("Cumulative return (%)")
axes[0].set_title("Top 15 performers")
for i, v in enumerate(top["cumulative_return"][::-1] * 100):
    axes[0].text(v + 20, i, f"{v:.0f}%", va="center", fontsize=9)

axes[1].barh(bot["symbol"][::-1], bot["cumulative_return"][::-1] * 100, color="#c0392b")
axes[1].set_xlabel("Cumulative return (%)")
axes[1].set_title("Bottom 15 performers")
for i, v in enumerate(bot["cumulative_return"][::-1] * 100):
    axes[1].text(v - 3, i, f"{v:.0f}%", va="center", ha="right", fontsize=9, color="white")

plt.tight_layout()
plt.savefig("figures/02_top_bottom.png")
plt.close()


#3. Risk-return scatter
rr = pd.read_sql("""
    SELECT c.symbol, c.annualized_return, v.vol_annualized
    FROM cumulative_returns c JOIN volatility_summary v ON c.symbol = v.symbol
""", engine)

fig, ax = plt.subplots(figsize=(9, 6))
ax.scatter(rr["vol_annualized"] * 100, rr["annualized_return"] * 100,
           alpha=0.4, s=25, color="#34495e")
top5 = rr.nlargest(5, "annualized_return")
bot5 = rr.nsmallest(5, "annualized_return")
for _, r in top5.iterrows():
    ax.annotate(r["symbol"], (r["vol_annualized"]*100, r["annualized_return"]*100),
                fontsize=9, color="#27ae60", fontweight="bold")
for _, r in bot5.iterrows():
    ax.annotate(r["symbol"], (r["vol_annualized"]*100, r["annualized_return"]*100),
                fontsize=9, color="#c0392b", fontweight="bold")
ax.axhline(0, color="grey", alpha=0.4)
ax.set_xlabel("Annualized volatility (%)")
ax.set_ylabel("Annualized return (%)")
ax.set_title("Risk-return scatter, all S&P 500 stocks with full history")
plt.tight_layout()
plt.savefig("figures/03_risk_return.png")
plt.close()


#4. Drawdown distribution
dd = pd.read_sql("SELECT max_drawdown FROM drawdown_summary", engine)

fig, ax = plt.subplots(figsize=(9, 4.5))
ax.hist(dd["max_drawdown"] * 100, bins=40, color="#c0392b", alpha=0.75, edgecolor="white")
ax.axvline(dd["max_drawdown"].median() * 100, color="black", linestyle="--",
           label=f"Median: {dd['max_drawdown'].median()*100:.1f}%")
ax.set_xlabel("Maximum drawdown (%)")
ax.set_ylabel("Number of stocks")
ax.set_title("Distribution of maximum drawdowns across the S&P 500, 2014–2017")
ax.legend()
plt.tight_layout()
plt.savefig("figures/04_drawdown_distribution.png")
plt.close()


#5. Cross-sectional dispersion
disp = pd.read_sql("""
    SELECT date, cross_section_dispersion FROM ew_index_daily ORDER BY date
""", engine)
disp["rolling_30d"] = disp["cross_section_dispersion"].rolling(30).mean()

fig, ax = plt.subplots(figsize=(11, 4))
ax.plot(disp["date"], disp["rolling_30d"] * 100, color="#c0392b", linewidth=1.4)
ax.set_xlabel("Date")
ax.set_ylabel("Cross-section dispersion (30d rolling mean, %)")
ax.set_title("Cross-sectional dispersion — how differently stocks moved each day")
ax.annotate("Aug 2015\nChina scare", xy=(pd.Timestamp("2015-09-15"), 1.85), fontsize=9,
            ha="center", color="black")
plt.tight_layout()
plt.savefig("figures/05_dispersion.png")
plt.close()


#6. Correlation heatmap of top 20 most-traded names
top20 = pd.read_sql("""
    SELECT cumulative_returns.symbol FROM cumulative_returns
    JOIN (SELECT symbol AS s, AVG(volume_adj) AS v FROM prices GROUP BY symbol) t
    ON cumulative_returns.symbol = t.s
    ORDER BY t.v DESC LIMIT 20
""", engine)["symbol"].tolist()

placeholders = ",".join([f"'{s}'" for s in top20])
ret_pivot = pd.read_sql(f"""
    SELECT date, symbol, daily_return
    FROM daily_returns
    WHERE symbol IN ({placeholders})
""", engine).pivot(index="date", columns="symbol", values="daily_return")

corr = ret_pivot.corr()
fig, ax = plt.subplots(figsize=(10, 8))
sns.heatmap(corr, cmap="RdBu_r", center=0, vmin=-1, vmax=1,
            square=True, linewidths=0.5, cbar_kws={"label": "Correlation"}, ax=ax)
ax.set_title("Daily return correlation, 20 most-traded S&P 500 stocks")
plt.tight_layout()
plt.savefig("figures/06_correlation_heatmap.png")
plt.close()


#7. Worst market days
worst = pd.read_sql("""
    SELECT date, mean_return FROM broad_market_drops
    ORDER BY mean_return ASC LIMIT 15
""", engine)
worst["date_str"] = pd.to_datetime(worst["date"]).dt.strftime("%Y-%m-%d")

fig, ax = plt.subplots(figsize=(9, 5))
ax.barh(worst["date_str"][::-1], worst["mean_return"][::-1] * 100, color="#c0392b")
for i, v in enumerate(worst["mean_return"][::-1] * 100):
    ax.text(v - 0.05, i, f"{v:.2f}%", va="center", ha="right", fontsize=9, color="white")
ax.set_xlabel("Mean S&P 500 stock daily return (%)")
ax.set_title("15 worst market days, 2014–2017 (≥80% of stocks fell)")
plt.tight_layout()
plt.savefig("figures/07_worst_days.png")
plt.close()


print("All figures generated.")