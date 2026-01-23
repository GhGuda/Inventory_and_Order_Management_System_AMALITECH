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



-- STORED PROCEDURE: Process New Order
DELIMITER $$
CREATE PROCEDURE ProcessNewOrder_JSON(
    IN p_customer_id INT,
    IN p_order_items JSON
)
BEGIN
    DECLARE v_order_id INT;
    DECLARE v_total_amount DECIMAL(10,2) DEFAULT 0.00;
    DECLARE v_item_count INT;
    DECLARE v_idx INT DEFAULT 0;
    DECLARE v_product_id INT;
    DECLARE v_quantity INT;
    DECLARE v_current_stock INT;
    DECLARE v_product_price DECIMAL(10,2);
    DECLARE v_error_msg VARCHAR(500);
    DECLARE v_actual_error TEXT;

    -- ==============================
    -- Error handler (LOG + ROLLBACK)
    -- ==============================
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_actual_error = MESSAGE_TEXT;

        INSERT INTO error_logs (
            procedure_name,
            error_msg,
            actual_error
        )
        VALUES (
            'ProcessNewOrder_JSON',
            v_error_msg,
            v_actual_error
        );

        ROLLBACK;
        RESIGNAL;
    END;

    -- Validate customer
    IF NOT EXISTS (
        SELECT 1 FROM Customers WHERE customer_id = p_customer_id
    ) THEN
        SET v_error_msg = 'Customer does not exist';
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = v_error_msg;
    END IF;


    -- Validate JSON
    IF p_order_items IS NULL OR JSON_LENGTH(p_order_items) = 0 THEN
        SET v_error_msg = 'Order must contain at least one item';
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = v_error_msg;
    END IF;


    SET v_item_count = JSON_LENGTH(p_order_items);

    START TRANSACTION;

    SET v_idx = 0;
    WHILE v_idx < v_item_count DO

        SET v_product_id =
            CAST(JSON_UNQUOTE(JSON_EXTRACT(p_order_items, CONCAT('$[', v_idx, '].product_id'))) AS UNSIGNED);

        SET v_quantity =
            CAST(JSON_UNQUOTE(JSON_EXTRACT(p_order_items, CONCAT('$[', v_idx, '].quantity'))) AS UNSIGNED);

        -- Validate fields
        IF v_product_id IS NULL OR v_quantity IS NULL THEN
            SET v_error_msg = 'Invalid order item format';
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;

        IF v_quantity <= 0 THEN
            SET v_error_msg = CONCAT('Invalid quantity for product ', v_product_id);
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;

        -- Validate product exists
        IF NOT EXISTS (
            SELECT 1 FROM Products WHERE product_id = v_product_id
        ) THEN
            SET v_error_msg = CONCAT('Product does not exist: ', v_product_id);
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;

        -- Lock inventory row
        SELECT quantity_on_hand
        INTO v_current_stock
        FROM Inventory
        WHERE product_id = v_product_id
        FOR UPDATE;


        IF v_current_stock IS NULL THEN
            SET v_error_msg = CONCAT('Inventory record missing for product ', v_product_id);
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;

        IF v_current_stock < v_quantity THEN
            SET v_error_msg = CONCAT(
                'Insufficient stock for product ', v_product_id,
                '. Available=', v_current_stock,
                ', Requested=', v_quantity
            );
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = v_error_msg;
        END IF;

        SET v_idx = v_idx + 1;
    END WHILE;

    INSERT INTO Orders (customer_id, total_amount)
    VALUES (p_customer_id, 0);

    SET v_order_id = LAST_INSERT_ID();

    SET v_idx = 0;

    WHILE v_idx < v_item_count DO

        SET v_product_id =
            CAST(JSON_UNQUOTE(JSON_EXTRACT(p_order_items, CONCAT('$[', v_idx, '].product_id'))) AS UNSIGNED);

        SET v_quantity =
            CAST(JSON_UNQUOTE(JSON_EXTRACT(p_order_items, CONCAT('$[', v_idx, '].quantity'))) AS UNSIGNED);

        SELECT price
        INTO v_product_price
        FROM Products
        WHERE product_id = v_product_id;

        INSERT INTO Order_Items (
            order_id,
            product_id,
            quantity,
            price_at_purchase
        )
        VALUES (
            v_order_id,
            v_product_id,
            v_quantity,
            v_product_price
        );


        UPDATE Inventory
        SET quantity_on_hand = quantity_on_hand - v_quantity
        WHERE product_id = v_product_id;


        SET v_total_amount =
            v_total_amount + (v_product_price * v_quantity);

        SET v_idx = v_idx + 1;
    END WHILE;

    UPDATE Orders
    SET total_amount = v_total_amount
    WHERE order_id = v_order_id;

    COMMIT;

    -- ==============================
    -- Audit log (SUCCESS)
    -- ==============================
    INSERT INTO audit_logs (
        entity_name,
        entity_id,
        action,
        action_details
    )
    VALUES (
        'Orders',
        v_order_id,
        'CREATE',
        CONCAT('Order created for customer ', p_customer_id,
               ' with total amount ', v_total_amount)
    );

    SELECT
        v_order_id     AS order_id,
        v_total_amount AS total_amount,
        v_item_count   AS items_count,
        'Order processed successfully' AS message;
END $$
DELIMITER ;