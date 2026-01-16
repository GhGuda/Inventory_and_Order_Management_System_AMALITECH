-- Create a saved result that shows how much money each customer has spent in total.
CREATE OR REPLACE VIEW CustomerSalesSummary AS
SELECT
    c.customer_id,
    c.full_name AS customer_name,
    SUM(oi.quantity * oi.price_at_purchase) AS total_amount_spent
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.status IN ('Shipped', 'Delivered')
GROUP BY c.customer_id, c.full_name;


SELECT * FROM CustomerSalesSummary;
