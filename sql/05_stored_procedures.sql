-- Active: 1769074107997@@127.0.0.1@3306@inventory_order_management
USE inventory_order_management;
-- ============================================================
-- Stored Procedure: ProcessNewOrder_JSON
-- ============================================================
-- Purpose:
-- This stored procedure processes a customer order containing
-- multiple products in a single, atomic transaction.
--
-- Inputs:
-- 1. p_customer_id (INT)
--    - Unique identifier of the customer placing the order.
-- 2. p_order_items (JSON)
--    - A JSON array of order items.
--    - Each item must contain:
--        • product_id (INT)
--        • quantity (INT)
--
-- Transaction Management:
-- All operations are executed within a single database
-- transaction to ensure atomicity, consistency, isolation,
-- and durability (ACID compliance).
--
-- Business Rules and Validations:
-- 1. Verifies that the customer exists.
-- 2. Ensures the order payload contains at least one item.
-- 3. Iterates through each order item to:
--    - Validate input structure and data integrity.
--    - Confirm product existence.
--    - Lock inventory records to prevent race conditions.
--    - Verify sufficient inventory availability.
--
-- Error Handling:
-- • If any validation, inventory check, or database operation
--   fails, the transaction is rolled back in full.
-- • Detailed error information is captured and persisted in
--   the error_logs table for traceability and diagnostics.
-- • The error is re-thrown to the calling application.
--
-- Order Processing:
-- Upon successful validation:
-- 1. A new record is created in the Orders table.
-- 2. Associated order line items are inserted into the
--    Order_Items table.
-- 3. Inventory quantities are updated accordingly.
-- 4. The total order value is calculated and stored.
--
-- Auditing:
-- • Successful order creation is recorded in the audit_logs
--   table, including entity reference and action details.
--
-- Outcome:
-- • On success: the procedure commits the transaction and
--   returns order metadata to the caller.
-- • On failure: the transaction is rolled back, logged, and
--   an error is returned.
--
-- This procedure ensures data integrity, concurrency safety,
-- operational transparency, and auditability in an
-- enterprise-grade order management system.


DROP PROCEDURE IF EXISTS ProcessNewOrder_JSON;
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


CALL ProcessNewOrder_JSON(
    7,
    '[
        {"product_id":2, "quantity":1},
        {"product_id":5, "quantity":1}
     ]'
);