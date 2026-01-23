CREATE VIEW CustomerSalesSummary AS
SELECT
    c.customer_id,
    c.full_name AS customer_name,
    COALESCE(
        SUM(oi.quantity * oi.price_at_purchase),
        0.00
    ) AS total_amount_spent
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.status IN ('Shipped', 'Delivered')
GROUP BY
    c.customer_id,
    c.full_name;
