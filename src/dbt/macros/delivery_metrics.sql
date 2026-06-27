{#
    Shared late-delivery metric columns for the agg_delivery_* models.
    Single source of truth for how "late rate" is defined, so the three
    aggregates stay in sync. Caller must already filter to delivered orders
    (isLate is not null) and group by its own key.

    Args:
        is_late_column: boolean column flagging a late order (default 'isLate').
#}
{% macro delivery_metrics(is_late_column='isLate') %}
    count(*) as totalOrders,
    count_if({{ is_late_column }}) as lateOrders,
    (count_if({{ is_late_column }}) * 100.0 / count(*)) as lateRatePct
{% endmacro %}
