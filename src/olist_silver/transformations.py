"""
Reusable column/DataFrame transformations for the silver layer.
"""

from __future__ import annotations

from pyspark.sql import Column, DataFrame, SparkSession
from pyspark.sql.functions import col, current_timestamp, expr, when

# 32 hex chars, the shape of every Olist id column.
UUID_REGEX = "^[0-9a-fA-F]{32}$"

# Silver timestamps always parse with this explicit format (never auto-detect).
_TIMESTAMP_FORMAT = "yyyy-MM-dd HH:mm:ss"


def parse_timestamp(column: str, fmt: str = _TIMESTAMP_FORMAT) -> Column:
    """
    Parse a STRING column to TIMESTAMP, returning NULL on unparseable input.
    """
    return expr(f"try_to_timestamp({column}, '{fmt}')")


def is_valid_uuid(column: str) -> Column:
    """
    Boolean predicate for the WHERE clause — strict validation on merge keys.

    Rows whose key is not a valid UUID are dropped (they cannot form a key).
    """
    return col(column).rlike(UUID_REGEX)


def null_invalid_uuid(column: str) -> Column:
    """
    Null-out an FK/attribute UUID when invalid, keeping the row.
    """
    return when(col(column).rlike(UUID_REGEX), col(column)).otherwise(None)


def with_processed_timestamp(df: DataFrame) -> DataFrame:
    """Append the standard ``processedTimestamp`` audit column (CLAUDE.md §4.8)."""
    return df.withColumn("processedTimestamp", current_timestamp())


def build_merge_sql(
    target: str,
    source_view: str,
    keys: list[str],
    update_cols: list[str],
) -> str:
    """
    Build an idempotent ``MERGE INTO`` statement. Supports composite keys.
    """
    if not keys:
        raise ValueError("merge requires at least one key column")
    if not update_cols:
        raise ValueError("merge requires at least one column to update")

    on_clause = " AND ".join(f"target.{k} = source.{k}" for k in keys)
    set_clause = ", ".join(f"target.{c} = source.{c}" for c in update_cols)
    return (
        f"MERGE INTO {target} target "
        f"USING {source_view} source "
        f"ON {on_clause} "
        f"WHEN MATCHED THEN UPDATE SET {set_clause} "
        f"WHEN NOT MATCHED THEN INSERT *"
    )


def merge_into(
    spark: SparkSession,
    target: str,
    source_view: str,
    keys: list[str],
    update_cols: list[str] | None = None,
    source_df: DataFrame | None = None,
) -> None:
    """
    Register ``source_df`` (if given) as a temp view and run the MERGE.

    ``update_cols`` defaults to every column of ``source_df`` that is not a key,
    so callers don't have to keep a hand-maintained column list in sync with the
    schema. Pass either ``source_df`` (to derive ``update_cols``) or an explicit
    ``update_cols`` with a pre-registered ``source_view``.
    """
    if source_df is not None:
        source_df.createOrReplaceTempView(source_view)
        if update_cols is None:
            update_cols = [c for c in source_df.columns if c not in keys]
    if update_cols is None:
        raise ValueError("provide update_cols or source_df to derive them from")

    spark.sql(build_merge_sql(target, source_view, keys, update_cols))
