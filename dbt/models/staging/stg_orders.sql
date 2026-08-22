with source as (
    select * from {{ ref('raw_orders') }}
),

renamed as (
    select
        id as order_id,
        user_id as customer_id,
        timestamp(order_date) as ordered_at,
        status as order_status
    from source
)

select * from renamed
