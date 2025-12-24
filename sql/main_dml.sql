-- =========================================
-- STEP 3: KPI & ADVANCED SQL QUERYING (DML)
-- Inventory & Order Management System
-- =========================================


-- KPI 1: Total Revenue from Shipped/Delivered Orders
SELECT SUM(oi.quantity * oi.price_at_purchase) AS total_revenue
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.status IN ('Shipped', 'Delivered');



-- KPI 2: Top 10 Customers by Total Spending
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


-- KPI 3: Top 5 Best-Selling Products by Quantity Sold
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



-- KPI 4: Monthly Sales Trend
SELECT
    DATE_FORMAT(o.order_date, '%Y-%m') AS sales_month,
    SUM(oi.quantity * oi.price_at_purchase) AS total_revenue
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.status IN ('Shipped', 'Delivered')
GROUP BY DATE_FORMAT(o.order_date, '%Y-%m')
ORDER BY sales_month;



-- ANALYTICAL QUERY 1: Sales Rank by Category
SELECT
    category,
    product_name,
    total_revenue,
    RANK() OVER (
        PARTITION BY category
        ORDER BY total_revenue DESC
    ) AS sales_rank
FROM (
    SELECT
        p.category,
        p.product_name,
        SUM(oi.quantity * oi.price_at_purchase) AS total_revenue
    FROM products p
    JOIN order_items oi
        ON p.product_id = oi.product_id
    JOIN orders o
        ON o.order_id = oi.order_id
    WHERE o.status IN ('Shipped', 'Delivered')
    GROUP BY p.product_id, p.category, p.product_name
) product_sales;



-- ANALYTICAL QUERY 2: Customer Order Frequency
SELECT
    c.full_name AS customer_name,
    o.order_date AS current_order_date,
    LAG(o.order_date) OVER (
        PARTITION BY c.customer_id
        ORDER BY o.order_date
    ) AS previous_order_date
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id;



-- VIEW: Customer Sales Summary
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




-- STORED PROCEDURE: Process New Order
DROP PROCEDURE IF EXISTS ProcessNewOrder;
CREATE PROCEDURE ProcessNewOrder(
    IN p_customers_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE product_available INT;
    DECLARE product_price DECIMAL(10,2);
    DECLARE new_order_id INT;

    DECLARE v_sqlstate CHAR(5);
    DECLARE v_error_msg TEXT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN

        -- Get the actual SQL error message
        GET DIAGNOSTICS CONDITION 1
        v_sqlstate = RETURNED_SQLSTATE,
        v_error_msg = MESSAGE_TEXT;

        -- Undo partial changes
        ROLLBACK;

        -- Log both custom + actual error
        INSERT INTO error_logs (procedure_name, error_msg, actual_error)
        VALUES (
            'ProcessNewOrder',
            'Order processing failed',
            CONCAT('SQLSTATE: ', v_sqlstate, ' | ', v_error_msg)
        );
    END;

    START TRANSACTION;

    SELECT quantity_on_hand
    INTO product_available
    FROM inventory
    WHERE product_id = p_product_id;

    IF product_available IS NULL OR product_available < p_quantity THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Low on stocks';
    END IF;

    SELECT price
    INTO product_price
    FROM products
    WHERE product_id = p_product_id;

    INSERT INTO orders (customer_id, total_amount)
    VALUES (p_customers_id, product_price * p_quantity);

    SET new_order_id = LAST_INSERT_ID();

    INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase)
    VALUES (new_order_id, p_product_id, p_quantity, product_price);

    UPDATE inventory
    SET quantity_on_hand = quantity_on_hand - p_quantity
    WHERE product_id = p_product_id;

    COMMIT;
END;