with source as (
    select
        po.purchase_order_id,
        po.supplier_id,
        po.product_id,
        po.quantity,
        po.unit_cost,
        po.status_id,
        po.creation_date,
        po.submitted_date,
        po.expected_date,
        po.date_received,
        po.shipping_fee,
        po.taxes,
        po.payment_date,
        po.payment_amount,
        po.payment_method,
        po.approved_by,
        po.approved_date,
        po.submitted_by,
        po.notes,
        p.product_code,
        p.product_name,
        p.supplier_company,
        p.category,
        p.standard_cost,
        p.list_price,
        dd.year,
        dd.fiscal_year,
        dd.fiscal_qtr,
        dd.month,
        dd.month_name,
        dd.year_week,
        dd.day_name,
        current_timestamp() as insertion_timestamp,
    from {{ ref('fact_purchase_order') }} po
    left join {{ ref('dim_product') }} p
        on p.product_id = po.product_id
    left join {{ ref('dim_date') }} dd
        on dd.full_date = po.creation_date
)
select *
from source
