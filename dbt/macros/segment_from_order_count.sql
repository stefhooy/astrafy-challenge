{% macro segment_from_order_count(prior_order_count_column) %}
{#
    Buckets a customer's count of orders placed in the trailing 12 months (strictly before
    the current order) into the three business segments defined in Exercise 5. Thresholds are
    dbt vars (see dbt_project.yml), not hardcoded here, so the business rule lives in one place.
#}
    case
        when {{ prior_order_count_column }} >= {{ var('vip_order_threshold') }}
            then 'VIP'
        when {{ prior_order_count_column }} >= {{ var('returning_order_threshold') }}
            then 'Returning'
        else 'New'
    end
{% endmacro %}
