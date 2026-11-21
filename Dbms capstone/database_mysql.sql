-- =====================================================================
--  database_mysql.sql  -  MySQL version (for MySQL Workbench)
--  Intelligent Library and Digital Resource Management System
--  Needs MySQL 8.0.31 or newer (for INTERSECT / EXCEPT).
--  HOW TO RUN: open this file in MySQL Workbench, click the lightning
--  bolt (Execute all). Then refresh the SCHEMAS panel on the left.
-- =====================================================================

DROP DATABASE IF EXISTS library_db;
CREATE DATABASE library_db;
USE library_db;

-- ===================== 1. DDL (tables, keys) =========================
CREATE TABLE publishers (
    publisher_id    INT AUTO_INCREMENT PRIMARY KEY,
    publisher_name  VARCHAR(100) NOT NULL UNIQUE,      -- candidate key
    city            VARCHAR(60)
);

CREATE TABLE authors (
    author_id    INT AUTO_INCREMENT PRIMARY KEY,
    author_name  VARCHAR(100) NOT NULL UNIQUE,         -- candidate key
    country      VARCHAR(60)
);

CREATE TABLE categories (
    category_id    INT AUTO_INCREMENT PRIMARY KEY,
    category_name  VARCHAR(60) NOT NULL UNIQUE         -- candidate key
);

CREATE TABLE membership_types (
    type_id       INT AUTO_INCREMENT PRIMARY KEY,
    type_name     VARCHAR(30) NOT NULL UNIQUE,         -- candidate key
    max_books     INT NOT NULL CHECK (max_books > 0),
    loan_days     INT NOT NULL CHECK (loan_days > 0),
    fine_per_day  DECIMAL(6,2) NOT NULL DEFAULT 0 CHECK (fine_per_day >= 0)
);

CREATE TABLE members (
    member_id           INT AUTO_INCREMENT PRIMARY KEY,
    member_name         VARCHAR(100) NOT NULL,
    email               VARCHAR(120) NOT NULL UNIQUE,  -- candidate key
    phone               VARCHAR(15) UNIQUE,            -- candidate key
    join_date           DATE NOT NULL DEFAULT (CURDATE()),
    status              VARCHAR(10) NOT NULL DEFAULT 'Active'
                        CHECK (status IN ('Active', 'Suspended')),
    membership_type_id  INT NOT NULL,
    FOREIGN KEY (membership_type_id) REFERENCES membership_types(type_id)
);

CREATE TABLE resources (
    resource_id       INT AUTO_INCREMENT PRIMARY KEY,
    title             VARCHAR(200) NOT NULL,
    resource_type     VARCHAR(10) NOT NULL CHECK (resource_type IN ('Physical', 'Digital')),
    isbn              VARCHAR(20) UNIQUE,              -- candidate key (can be empty)
    publication_year  INT,
    total_copies      INT NOT NULL CHECK (total_copies >= 0),
    available_copies  INT NOT NULL CHECK (available_copies >= 0),
    access_link       VARCHAR(255),
    publisher_id      INT NOT NULL,
    category_id       INT NOT NULL,
    CHECK (available_copies <= total_copies),
    FOREIGN KEY (publisher_id) REFERENCES publishers(publisher_id),
    FOREIGN KEY (category_id)  REFERENCES categories(category_id)
);

CREATE TABLE resource_authors (
    resource_id  INT NOT NULL,
    author_id    INT NOT NULL,
    PRIMARY KEY (resource_id, author_id),              -- composite primary key
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id),
    FOREIGN KEY (author_id)   REFERENCES authors(author_id)
);

CREATE TABLE transactions (
    transaction_id  INT AUTO_INCREMENT PRIMARY KEY,
    member_id       INT NOT NULL,
    resource_id     INT NOT NULL,
    issue_date      DATE NOT NULL,
    due_date        DATE NOT NULL,
    return_date     DATE,
    status          VARCHAR(10) NOT NULL DEFAULT 'Issued'
                    CHECK (status IN ('Issued', 'Returned')),
    FOREIGN KEY (member_id)   REFERENCES members(member_id),
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id)
);

CREATE TABLE reservations (
    reservation_id    INT AUTO_INCREMENT PRIMARY KEY,
    member_id         INT NOT NULL,
    resource_id       INT NOT NULL,
    reservation_date  DATE NOT NULL,
    status            VARCHAR(10) NOT NULL DEFAULT 'Active'
                      CHECK (status IN ('Active', 'Fulfilled', 'Cancelled')),
    FOREIGN KEY (member_id)   REFERENCES members(member_id),
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id)
);

CREATE TABLE penalties (
    penalty_id      INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id  INT NOT NULL UNIQUE,               -- candidate key
    days_late       INT NOT NULL CHECK (days_late > 0),
    amount          DECIMAL(8,2) NOT NULL CHECK (amount >= 0),
    penalty_date    DATE NOT NULL,
    status          VARCHAR(10) NOT NULL DEFAULT 'Unpaid'
                    CHECK (status IN ('Paid', 'Unpaid')),
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
);

-- ========================== 2. INDEXES ===============================
CREATE INDEX idx_transactions_member    ON transactions(member_id);
CREATE INDEX idx_transactions_resource  ON transactions(resource_id);
CREATE INDEX idx_transactions_due_date  ON transactions(due_date);
CREATE INDEX idx_resources_title        ON resources(title);
CREATE INDEX idx_members_name           ON members(member_name);
CREATE INDEX idx_reservations_resource  ON reservations(resource_id, status);

-- ====================== 3. DML (dummy data) ==========================
INSERT INTO publishers (publisher_name, city) VALUES
    ('McGraw Hill', 'New York'), ('Pearson', 'London'),
    ('No Starch Press', 'San Francisco'), ('OReilly Media', 'Sebastopol');

INSERT INTO authors (author_name, country) VALUES
    ('Abraham Silberschatz', 'USA'), ('Henry Korth', 'USA'), ('Ramez Elmasri', 'USA'),
    ('Eric Matthes', 'USA'), ('Thomas Cormen', 'USA'), ('Robert Martin', 'USA'),
    ('Alan Beaulieu', 'USA'), ('Miguel Grinberg', 'USA'), ('Andrew Tanenbaum', 'Netherlands');

INSERT INTO categories (category_name) VALUES
    ('Databases'), ('Programming'), ('Algorithms'), ('Systems');

INSERT INTO membership_types (type_name, max_books, loan_days, fine_per_day) VALUES
    ('Student', 3, 14, 2.0), ('Faculty', 5, 30, 1.0), ('Guest', 1, 7, 5.0);

INSERT INTO members (member_name, email, phone, join_date, status, membership_type_id) VALUES
    ('Aarav Sharma',  'aarav@college.edu', '9000000001', CURDATE() - INTERVAL 200 DAY, 'Active', 1),
    ('Diya Verma',    'diya@college.edu',  '9000000002', CURDATE() - INTERVAL 180 DAY, 'Active', 1),
    ('Dr. Mehta',     'mehta@college.edu', '9000000003', CURDATE() - INTERVAL 400 DAY, 'Active', 2),
    ('Rohan Gupta',   'rohan@college.edu', '9000000004', CURDATE() - INTERVAL 90 DAY,  'Active', 1),
    ('Sneha Iyer',    'sneha@college.edu', '9000000005', CURDATE() - INTERVAL 60 DAY,  'Active', 1),
    ('Guest Visitor', 'guest@example.com', '9000000006', CURDATE() - INTERVAL 30 DAY,  'Active', 3);

INSERT INTO resources (title, resource_type, isbn, publication_year, total_copies, available_copies, access_link, publisher_id, category_id) VALUES
    ('Database System Concepts',         'Physical', '9780078022159', 2019,   5,   3, NULL, 1, 1),
    ('Fundamentals of Database Systems', 'Physical', '9780133970777', 2016,   3,   3, NULL, 2, 1),
    ('Python Crash Course',              'Physical', '9781593279288', 2019,   4,   3, NULL, 3, 2),
    ('Introduction to Algorithms',       'Physical', '9780262033848', 2009,   2,   2, NULL, 1, 3),
    ('Clean Code',                       'Physical', '9780132350884', 2008,   3,   2, NULL, 2, 2),
    ('Operating System Concepts',        'Physical', '9781119800361', 2021,   2,   1, NULL, 1, 4),
    ('Learning SQL (E-Book)',            'Digital',  '9780596520830', 2009, 100, 100, 'https://example.com/learning-sql', 4, 1),
    ('Flask Web Development (E-Book)',   'Digital',  '9781491991732', 2018, 100,  99, 'https://example.com/flask-book',   4, 2),
    ('Computer Networks',                'Physical', '9780132126953', 2010,   2,   2, NULL, 2, 4);

INSERT INTO resource_authors (resource_id, author_id) VALUES
    (1,1), (1,2), (2,3), (3,4), (4,5), (5,6), (6,1), (6,2), (7,7), (8,8), (9,9);

INSERT INTO transactions (member_id, resource_id, issue_date, due_date, return_date, status) VALUES
    (1, 1, CURDATE() - INTERVAL 40 DAY, CURDATE() - INTERVAL 26 DAY, CURDATE() - INTERVAL 28 DAY, 'Returned'),
    (2, 2, CURDATE() - INTERVAL 35 DAY, CURDATE() - INTERVAL 21 DAY, CURDATE() - INTERVAL 15 DAY, 'Returned'),
    (3, 4, CURDATE() - INTERVAL 50 DAY, CURDATE() - INTERVAL 20 DAY, CURDATE() - INTERVAL 22 DAY, 'Returned'),
    (4, 1, CURDATE() - INTERVAL 30 DAY, CURDATE() - INTERVAL 16 DAY, CURDATE() - INTERVAL 10 DAY, 'Returned'),
    (1, 3, CURDATE() - INTERVAL 25 DAY, CURDATE() - INTERVAL 11 DAY, CURDATE() - INTERVAL 12 DAY, 'Returned'),
    (5, 7, CURDATE() - INTERVAL 20 DAY, CURDATE() - INTERVAL 6 DAY,  CURDATE() - INTERVAL 8 DAY,  'Returned'),
    (6, 1, CURDATE() - INTERVAL 45 DAY, CURDATE() - INTERVAL 38 DAY, CURDATE() - INTERVAL 38 DAY, 'Returned'),
    (1, 1, CURDATE() - INTERVAL 20 DAY, CURDATE() - INTERVAL 6 DAY,  NULL, 'Issued'),   -- OVERDUE
    (2, 5, CURDATE() - INTERVAL 18 DAY, CURDATE() - INTERVAL 4 DAY,  NULL, 'Issued'),   -- OVERDUE
    (3, 1, CURDATE() - INTERVAL 10 DAY, CURDATE() + INTERVAL 20 DAY, NULL, 'Issued'),
    (4, 3, CURDATE() - INTERVAL 5 DAY,  CURDATE() + INTERVAL 9 DAY,  NULL, 'Issued'),
    (6, 6, CURDATE() - INTERVAL 10 DAY, CURDATE() - INTERVAL 3 DAY,  NULL, 'Issued'),   -- OVERDUE
    (5, 8, CURDATE() - INTERVAL 2 DAY,  CURDATE() + INTERVAL 12 DAY, NULL, 'Issued');

INSERT INTO reservations (member_id, resource_id, reservation_date, status) VALUES
    (4, 6, CURDATE() - INTERVAL 2 DAY, 'Active'),
    (1, 6, CURDATE() - INTERVAL 1 DAY, 'Active'),
    (3, 2, CURDATE() - INTERVAL 9 DAY, 'Fulfilled'),
    (6, 4, CURDATE() - INTERVAL 3 DAY, 'Cancelled');

INSERT INTO penalties (transaction_id, days_late, amount, penalty_date, status) VALUES
    (2, 6, 12.00, CURDATE() - INTERVAL 15 DAY, 'Paid'),
    (4, 6, 12.00, CURDATE() - INTERVAL 10 DAY, 'Unpaid');

-- ========================== 4. VIEWS =================================
CREATE VIEW v_overdue_books AS
SELECT  t.transaction_id, m.member_name, r.title, t.issue_date, t.due_date,
        DATEDIFF(CURDATE(), t.due_date)                      AS days_overdue,
        DATEDIFF(CURDATE(), t.due_date) * mt.fine_per_day    AS fine_so_far
FROM    transactions t
JOIN    members m           ON m.member_id = t.member_id
JOIN    resources r         ON r.resource_id = t.resource_id
JOIN    membership_types mt ON mt.type_id = m.membership_type_id
WHERE   t.return_date IS NULL AND t.due_date < CURDATE();

CREATE VIEW v_popular_resources AS
SELECT  r.resource_id, r.title, r.resource_type,
        COUNT(t.transaction_id) AS times_borrowed
FROM    resources r
LEFT JOIN transactions t ON t.resource_id = r.resource_id
GROUP BY r.resource_id, r.title, r.resource_type;

CREATE VIEW v_member_summary AS
SELECT  m.member_id, m.member_name, mt.type_name,
        (SELECT COUNT(*) FROM transactions t WHERE t.member_id = m.member_id) AS total_borrows,
        (SELECT COUNT(*) FROM transactions t
          WHERE t.member_id = m.member_id AND t.return_date IS NULL)          AS books_out_now,
        (SELECT IFNULL(SUM(p.amount), 0)
           FROM penalties p JOIN transactions t ON t.transaction_id = p.transaction_id
          WHERE t.member_id = m.member_id AND p.status = 'Unpaid')            AS unpaid_fines
FROM    members m
JOIN    membership_types mt ON mt.type_id = m.membership_type_id;

-- ======================= 5. ANALYTICS QUERIES ========================
-- TIP: in Workbench, click inside ONE query and press Ctrl+Enter to run just that one.

-- 5.1 JOIN: every loan with member and title
SELECT t.transaction_id, m.member_name, r.title, t.issue_date, t.due_date, t.status
FROM   transactions t
JOIN   members m   ON m.member_id = t.member_id
JOIN   resources r ON r.resource_id = t.resource_id
ORDER BY t.issue_date DESC;

-- 5.2 JOIN across many tables: publisher, category, authors
SELECT r.title, p.publisher_name, c.category_name,
       GROUP_CONCAT(a.author_name SEPARATOR ', ') AS authors
FROM   resources r
JOIN   publishers p        ON p.publisher_id = r.publisher_id
JOIN   categories c        ON c.category_id  = r.category_id
JOIN   resource_authors ra ON ra.resource_id = r.resource_id
JOIN   authors a           ON a.author_id    = ra.author_id
GROUP BY r.resource_id, r.title, p.publisher_name, c.category_name;

-- 5.3 SUBQUERY: members who borrowed more than the average member
SELECT m.member_name, COUNT(*) AS borrow_count
FROM   transactions t
JOIN   members m ON m.member_id = t.member_id
GROUP BY m.member_id, m.member_name
HAVING COUNT(*) > (SELECT AVG(cnt)
                   FROM (SELECT COUNT(*) AS cnt FROM transactions GROUP BY member_id) AS counts);

-- 5.4 UNION: borrowed OR reserved
SELECT member_id FROM transactions
UNION
SELECT member_id FROM reservations;

-- 5.5 INTERSECT: borrowed AND reserved (MySQL 8.0.31+)
SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM transactions)
INTERSECT
SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM reservations);

-- 5.6 EXCEPT: resources never borrowed (MySQL 8.0.31+)
SELECT title FROM resources
EXCEPT
SELECT r.title FROM resources r JOIN transactions t ON t.resource_id = r.resource_id;

-- 5.7 WINDOW FUNCTION: rank resources inside each category
SELECT c.category_name, r.title,
       COUNT(t.transaction_id) AS times_borrowed,
       RANK() OVER (PARTITION BY c.category_name
                    ORDER BY COUNT(t.transaction_id) DESC) AS rank_in_category
FROM   resources r
JOIN   categories c ON c.category_id = r.category_id
LEFT JOIN transactions t ON t.resource_id = r.resource_id
GROUP BY r.resource_id, r.title, c.category_name;

-- 5.8 CTE: overdue books with fine
WITH overdue AS (
    SELECT t.transaction_id, t.member_id, t.resource_id, t.due_date,
           DATEDIFF(CURDATE(), t.due_date) AS days_late
    FROM   transactions t
    WHERE  t.return_date IS NULL AND t.due_date < CURDATE()
)
SELECT m.member_name, r.title, o.due_date, o.days_late,
       o.days_late * mt.fine_per_day AS fine
FROM   overdue o
JOIN   members m           ON m.member_id = o.member_id
JOIN   resources r         ON r.resource_id = o.resource_id
JOIN   membership_types mt ON mt.type_id = m.membership_type_id
ORDER BY o.days_late DESC;

-- 5.9 CTE: frequently borrowed resources (above average)
WITH borrow_counts AS (
    SELECT resource_id, COUNT(*) AS times_borrowed
    FROM   transactions
    GROUP BY resource_id
)
SELECT r.title, bc.times_borrowed
FROM   borrow_counts bc
JOIN   resources r ON r.resource_id = bc.resource_id
WHERE  bc.times_borrowed > (SELECT AVG(times_borrowed) FROM borrow_counts)
ORDER BY bc.times_borrowed DESC;

-- 5.10 Using the views
SELECT * FROM v_overdue_books;
SELECT * FROM v_popular_resources ORDER BY times_borrowed DESC;
SELECT * FROM v_member_summary;

-- ============================ 6. DCL =================================
-- Real MySQL users and permissions (needs an admin account such as root).
-- Un-comment to run:
-- CREATE USER 'librarian'@'localhost' IDENTIFIED BY 'Lib@12345';
-- CREATE USER 'student'@'localhost'   IDENTIFIED BY 'Stu@12345';
-- GRANT SELECT, INSERT, UPDATE ON library_db.transactions TO 'librarian'@'localhost';
-- GRANT SELECT ON library_db.* TO 'student'@'localhost';
-- REVOKE UPDATE ON library_db.transactions FROM 'librarian'@'localhost';
-- SHOW GRANTS FOR 'librarian'@'localhost';

-- ============================ 7. TCL =================================
-- Ends with ROLLBACK so your data stays unchanged. Use COMMIT to keep changes.
START TRANSACTION;
    INSERT INTO categories (category_name) VALUES ('Temp Category 1');
    SAVEPOINT after_first_insert;
    INSERT INTO categories (category_name) VALUES ('Temp Category 2');
    ROLLBACK TO SAVEPOINT after_first_insert;   -- undoes only Temp Category 2
ROLLBACK;                                       -- undoes everything
