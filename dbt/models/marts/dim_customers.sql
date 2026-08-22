with customers as (
    select * from {{ ref('stg_customers') }}
),

orders as (
    select * from {{ ref('fct_orders') }}
),

customer_orders as (
    select
        customer_id,
        count(order_id) as number_of_orders,
        min(ordered_at) as first_ordered_at,
        sum(amount_usd) as lifetime_amount_usd
    from orders
    group by customer_id
)

select
    customers.customer_id,
    customers.first_name,
    customers.last_name,
    coalesce(customer_orders.number_of_orders, 0) as number_of_orders,
    customer_orders.first_ordered_at,
    coalesce(customer_orders.lifetime_amount_usd, 0) as lifetime_amount_usd
from customers
left join customer_orders using (customer_id)
