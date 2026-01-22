-- Active: 1769074107997@@127.0.0.1@3306@inventory_order_management
USE inventory_order_management;
-- Create a ProcessNewOrder Stored Procedure:

-- This procedure should accept Customer ID, Product ID, and Quantity as inputs.

-- It must perform the following actions within a transaction:

-- Check if there is enough stock in the Inventory.

-- If stock is sufficient, reduce the Inventory quantity.

-- Create a new record in the Orders table.

-- Create a new record in the Order Items table.

-- If stock is insufficient, it should roll back the transaction and return an error message.


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
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    -- Validate customer
    IF NOT EXISTS (
        SELECT 1 FROM Customers WHERE customer_id = p_customer_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Customer does not exist';
    END IF;
    -- Validate JSON
    IF p_order_items IS NULL OR JSON_LENGTH(p_order_items) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Order must contain at least one item';
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
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid order item format';
        END IF;
        IF v_quantity <= 0 THEN
            SET v_error_msg = CONCAT('Invalid quantity for product ', v_product_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_msg;
        END IF;
        -- Validate product exists (FK safety)
        IF NOT EXISTS (
            SELECT 1 FROM Products WHERE product_id = v_product_id
        ) THEN
            SET v_error_msg = CONCAT('Product does not exist: ', v_product_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_msg;
        END IF;
        -- Lock inventory row & check stock
        SELECT quantity
        INTO v_current_stock
        FROM Inventory
        WHERE product_id = v_product_id
        FOR UPDATE;
        IF v_current_stock IS NULL THEN
            SET v_error_msg = CONCAT('Inventory record missing for product ', v_product_id);
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_msg;
        END IF;
        IF v_current_stock < v_quantity THEN
            SET v_error_msg = CONCAT(
                'Insufficient stock for product ', v_product_id,
                '. Available=', v_current_stock,
                ', Requested=', v_quantity
            );
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_error_msg;
        END IF;
        SET v_idx = v_idx + 1;
    END WHILE;
    INSERT INTO Orders (customer_id, order_date, total_amount, order_status)
    VALUES (p_customer_id, CURRENT_DATE, 0, 'Pending');
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
            purchase_price
        )
        VALUES (
            v_order_id,
            v_product_id,
            v_quantity,
            v_product_price
        );
        UPDATE Inventory
        SET quantity = quantity - v_quantity
        WHERE product_id = v_product_id;
        SET v_total_amount =
            v_total_amount + (v_product_price * v_quantity);
        SET v_idx = v_idx + 1;
    END WHILE;
    UPDATE Orders
    SET total_amount = v_total_amount
    WHERE order_id = v_order_id;
    COMMIT;
    SELECT
        v_order_id     AS order_id,
        v_total_amount AS total_amount,
        v_item_count   AS items_count,
        'Order processed successfully' AS message;
END $$
DELIMITER ;

-- I have to retouch this code to get the concept.

CALL ProcessNewOrder_JSON(
    1,
    '[
        {"product_id":2, "quantity":20000},
        {"product_id":20, "quantity":1000000}
     ]'
);

SELECT * FROM customers WHERE customer_id = 1;
SELECT * FROM products WHERE product_id = 20;
SELECT * FROM inventory WHERE product_id = 70;

SET FOREIGN_KEY_CHECKS = 0;
DELETE FROM orders;
SET FOREIGN_KEY_CHECKS = 1;