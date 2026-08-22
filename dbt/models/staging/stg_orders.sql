with source as (
    select * from {{ ref('raw_orders') }}
),

renamed as (
    select
        id as order_id,
        user_id as customer_id,
        timestamp(order_date) as ordered_at,
        status as order_status,
        -- Smoke test for Slim CI: touching only this model should build
        -- stg_orders, fct_orders and dim_customers, and nothing else.
        date(order_date) as ordered_on
    from source
)

select * from renamed
