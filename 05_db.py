"""
Database connection configuration.
Edit DATABASE_URL to match your local Postgres setup, or set the
DATABASE_URL environment variable to override the default.
Default expects:
    - PostgreSQL running on localhost:5432
    - Database named 'sp500'
    - User 'postgres' with password 'postgres'
"""

import os

DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/sp500"
)


def get_engine():
    """Return a SQLAlchemy engine for the configured database."""
    from sqlalchemy import create_engine
    return create_engine(DATABASE_URL)


def get_connection():
    """Return a raw psycopg2 connection for COPY operations."""
    import psycopg2
    # Parse the URL into psycopg2 connection kwargs
    from urllib.parse import urlparse
    p = urlparse(DATABASE_URL)
    return psycopg2.connect(
        host=p.hostname,
        port=p.port or 5432,
        dbname=p.path.lstrip("/"),
        user=p.username,
        password=p.password,
    )