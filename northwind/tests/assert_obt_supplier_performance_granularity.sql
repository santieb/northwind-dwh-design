-- Granularity test for obt_supplier_performance
-- Asserts that the grain of the model is (purchase_order_id, product_id).
-- A purchase order can contain multiple products, so uniqueness is defined
-- by the combination of both keys.
-- Returns duplicate rows — test fails if any rows are returned.

select
    purchase_order_id,
    product_id,
    count(*) as n_records
from {{ ref('obt_supplier_performance') }}
group by
    purchase_order_id,
    product_id
having count(*) > 1
