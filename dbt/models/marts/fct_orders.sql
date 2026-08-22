with orders as (
    select * from {{ ref('stg_orders') }}
),

payments as (
    select * from {{ ref('stg_payments') }}
),

order_payments as (
    select
        order_id,
        sum(amount_usd) as amount_usd
    from payments
    group by order_id
),

final as (
    select
        orders.order_id,
        orders.customer_id,
        orders.ordered_at,
        orders.order_status,
        coalesce(order_payments.amount_usd, 0) as amount_usd
    from orders
    left join order_payments using (order_id)
)

select * from final
