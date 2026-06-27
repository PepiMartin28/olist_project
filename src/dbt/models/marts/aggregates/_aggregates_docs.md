{% docs total_orders %}
Total number of delivered orders in this group (only orders with
`isLate is not null` are counted).
{% enddocs %}

{% docs late_orders %}
Number of delivered orders in this group that arrived after the estimated
delivery date (`isLate = true`).
{% enddocs %}

{% docs late_rate_pct %}
Late-delivery rate for this group, as a percentage:
`lateOrders * 100.0 / totalOrders`. Emitted by the `delivery_metrics()` macro,
the single source of truth for the late-rate definition.
{% enddocs %}
