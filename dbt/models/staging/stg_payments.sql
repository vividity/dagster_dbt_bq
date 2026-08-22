with source as (
    select * from {{ ref('raw_payments') }}
),

renamed as (
    select
        id as payment_id,
        order_id,
        payment_method,
        -- amounts are stored in cents in the raw data
        cast(amount as numeric) / 100 as amount_usd
    from source
)

select * from renamed
