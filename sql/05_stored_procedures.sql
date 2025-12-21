-- Create a ProcessNewOrder Stored Procedure:

-- This procedure should accept Customer ID, Product ID, and Quantity as inputs.

-- It must perform the following actions within a transaction:

-- Check if there is enough stock in the Inventory.

-- If stock is sufficient, reduce the Inventory quantity.

-- Create a new record in the Orders table.

-- Create a new record in the Order Items table.

-- If stock is insufficient, it should roll back the transaction and return an error message.


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
