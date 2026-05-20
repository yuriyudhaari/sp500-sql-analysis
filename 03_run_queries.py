"""Run every SQL file in queries/ in order against the Postgres database."""

from pathlib import Path
from db import get_connection


def run_all():
    conn = get_connection()
    cur = conn.cursor()

    for sql_file in sorted(Path("queries").glob("*.sql")):
        print(f"\n=== {sql_file.name} ===")
        sql = sql_file.read_text()
        try:
            cur.execute(sql)
            conn.commit()
            # Count tables in the public schema
            cur.execute("""
                SELECT COUNT(*) FROM information_schema.tables
                WHERE table_schema = 'public'
            """)
            print(f"  OK. Tables in DB: {cur.fetchone()[0]}")
        except Exception as e:
            conn.rollback()
            print(f"  ERROR: {e}")
            break

    print("\n=== Final tables ===")
    cur.execute("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public'
        ORDER BY table_name
    """)
    for row in cur.fetchall():
        print(f"  {row[0]}")

    cur.close()
    conn.close()


if __name__ == "__main__":
    run_all()
