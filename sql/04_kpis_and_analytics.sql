USE inventory_order_management;


-- Customers
INSERT INTO customers (full_name, email, phone, shipping_address) VALUES
('Francis Class-Peters', 'class.Peters@mymail.com', '82478727937', 'Suhum'),
('Solomon Owusu', 'sos@mymail.com', '829878283877', 'Accra'),
('Life-Hard Kwabena Addo', 'vexful@mymail.com', '2647678232', 'Tema'),
('Jessica Azonto', 'esinamazonto@mymail.com', '2535675736', 'Kumasi'),
('Puulele Annegret Agyeman', 'puulele@mymail.com', '2357673213', 'Takoradi'),
('Kwaku Manu', 'manu@mymail.com', '23967829713', 'Shama'),
('Anita Mintah Bonsu', 'a.bonsu@mymail.com', '2375662376', 'USA');
SELECT * FROM customers;


-- Products for Phones and accessories
INSERT INTO products (product_name, category, price) VALUES
('Samsung S23 Ultra', 'Mobile Phone', 5000.00),
('Itel S25 Ultra', 'Mobile Phone', 2000.00),
('Samsung S23 Ultra Charger', 'Mobile Accessories', 150.00),
('Iphone 7+', 'Mobile Phone', 900.00),
('Iphone 16+ Screen', 'Mobile Accessories', 2500.00),
('Techno Camon 100', 'Mobile Phone', 4500.00),
('Xiaomi 17 Pro Max', 'Mobile Phone', 15000.00);
SELECT * FROM products;


-- Inventory
INSERT INTO inventory (product_id, quantity_on_hand) VALUES
(1, 34),
(2, 20),
(3, 10),
(4, 50),
(5, 80),
(6, 2),
(7, 13);

SELECT * FROM inventory;


-- Orders
INSERT INTO orders (customer_id, total_amount, status) VALUES
(9, 7000.00, 'Pending'),
(13, 150.00, 'Delivered'),
(15, 5000.00, 'Shipped'),
(11, 2900.00, 'Pending'),
(10, 2500.00, 'Delivered'),
(9, 15000.00, 'Pending'),
(11, 7500.00, 'Delivered'),
(10, 2500.00, 'Cancelled');


SELECT * FROM orders;
SELECT * FROM products;


-- Order Items
INSERT INTO order_items (order_id, product_id, quantity, price_at_purchase) VALUES
(1, 5, 1, 2500.00),
(1, 6, 1, 4500.00),
(2, 2, 1, 150.00),
(3, 3, 1, 5000.00),
(4, 2, 1, 2000.00),
(4, 4, 1, 900.00),
(5, 5, 1, 2500.00),
(6, 7, 1, 15000.00),
(8, 5, 1, 2500.00),
(7, 5, 3, 2500.00);
UPDATE order_items SET price_at_purchase = 2500 WHERE order_id = 9;
SELECT * FROM orders WHERE status = "Delivered";
SELECT * FROM order_items;