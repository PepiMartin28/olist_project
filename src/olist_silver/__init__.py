"""Shared helpers for the Olist silver layer.

Pure transformation helpers (return Columns / DataFrames) plus a thin MERGE
wrapper. The SQL-building logic is separated from `spark.sql` execution so it can
be unit-tested without a running Spark session.
"""

from olist_silver.transformations import (
    UUID_REGEX,
    build_merge_sql,
    is_valid_uuid,
    merge_into,
    null_invalid_uuid,
    parse_timestamp,
    with_processed_timestamp,
)

__all__ = [
    "UUID_REGEX",
    "build_merge_sql",
    "is_valid_uuid",
    "merge_into",
    "null_invalid_uuid",
    "parse_timestamp",
    "with_processed_timestamp",
]
