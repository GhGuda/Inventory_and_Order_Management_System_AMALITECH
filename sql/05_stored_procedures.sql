CREATE PROCEDURE ProcessNewOrder (
    IN p_customer_id INT,
    IN p_product_id INT,
    IN p_quantity INT
)
BEGIN
    DECLARE v_stock INT;
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_order_id INT;

    START TRANSACTION;

    SELECT quantity_on_hand
    INTO v_stock
    FROM inventory
    WHERE product_id = p_product_id
    FOR UPDATE;

    IF v_stock IS NULL OR v_stock < p_quantity THEN
        ROLLBACK;
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Insufficient stock to process order';
    END IF;

    SELECT price
    INTO v_price
    FROM products
    WHERE product_id = p_product_id;

    INSERT INTO orders (customer_id, total_amount, status)
    VALUES (p_customer_id, v_price * p_quantity, 'Pending');

    SET v_order_id = LAST_INSERT_ID();

    INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase)
    VALUES (v_order_id, p_product_id, p_quantity, v_price);

    UPDATE inventory
    SET quantity_on_hand = quantity_on_hand - p_quantity
    WHERE product_id = p_product_id;

    COMMIT;
END;

SHOW PROCEDURE STATUS
WHERE Name = 'ProcessNewOrder';


CALL ProcessNewOrder(2, 5, 1);

SELECT * FROM orders;
