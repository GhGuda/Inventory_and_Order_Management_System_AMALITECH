USE inventory_order_management;

-- Total Revenue: Calculate the total revenue from all 'Shipped' or 'Delivered' orders.

SELECT SUM(oi.quantity * oi.price_at_purchase) AS total_revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status IN ('Shipped', 'Delivered');




-- Top 10 Customers: Find the top 10 customers by their total spending. Show Customer Name and Total Amount Spent.

SELECT c.full_name AS customer_name, 
    SUM(oi.quantity * oi.price_at_purchase) AS total_amount_spent
FROM customers c
JOIN orders o
  ON c.customer_id = o.customer_id
JOIN order_items oi
  ON oi.order_id = o.order_id
WHERE o.status IN ('Shipped', 'Delivered')
GROUP BY c.customer_id, c.full_name
ORDER BY total_amount_spent DESC
LIMIT 10
;


-- Best-Selling Products: List the top 5 best-selling products by quantity sold.

SELECT 
  p.product_name AS product_name,
  SUM(oi.quantity) as total_quantity_sold 
FROM products p
JOIN order_items oi
  ON p.product_id = oi.product_id
JOIN orders o
  ON o.order_id = oi.order_id
WHERE o.status IN ('Shipped', 'Delivered')
GROUP BY p.product_id, p.product_name
ORDER BY total_quantity_sold DESC
LIMIT 5;



-- Monthly Sales Trend: Show the total sales revenue for each month.

SELECT
    DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
    SUM(oi.quantity * oi.price_at_purchase) AS total_revenue
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.status IN ('Shipped', 'Delivered')
GROUP BY sales_month
ORDER BY sales_month;
