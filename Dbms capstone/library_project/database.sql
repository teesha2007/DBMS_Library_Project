-- =====================================================================
--  database.sql  -  Intelligent Library and Digital Resource Management
--  Database: SQLite
-- =====================================================================
--  SECTIONS
--   1. DDL  (CREATE TABLE, with PK / FK / Candidate keys)
--   2. Indexes
--   3. DML  (INSERT dummy data)
--   4. Views
--   5. Analytics queries (Joins, Subqueries, Set operations, Window, CTE)
--   6. DCL  (GRANT / REVOKE - shown as comments, SQLite has no users)
--   7. TCL  (BEGIN / SAVEPOINT / ROLLBACK / COMMIT)
-- =====================================================================
--  NORMALIZATION NOTES (explain these in your viva)
--   1NF : every column holds ONE value. Authors are NOT stored as
--         "Ali, Sara" inside the books table - they live in their own
--         table (authors) linked through resource_authors.
--   2NF : in resource_authors the key is (resource_id, author_id) and
--         there are no extra columns depending on only part of it.
--   3NF : publisher name/city are stored once in publishers, category
--         name once in categories, and loan rules (max books, days,
--         fine per day) once in membership_types, instead of being
--         repeated in every book / member row.
--   BCNF: in every table the only determinants are candidate keys
--         (e.g. members: member_id, email and phone each determine the
--         rest of the row, and each is a candidate key).
-- =====================================================================

PRAGMA foreign_keys = ON;

-- Drop old tables so this file can be re-run safely
DROP VIEW  IF EXISTS v_overdue_books;
DROP VIEW  IF EXISTS v_popular_resources;
DROP VIEW  IF EXISTS v_member_summary;
DROP TABLE IF EXISTS penalties;
DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS transactions;
DROP TABLE IF EXISTS resource_authors;
DROP TABLE IF EXISTS resources;
DROP TABLE IF EXISTS members;
DROP TABLE IF EXISTS membership_types;
DROP TABLE IF EXISTS categories;
DROP TABLE IF EXISTS authors;
DROP TABLE IF EXISTS publishers;

-- =====================================================================
-- 1. DDL  -  CREATE TABLE
-- PRIMARY KEY   = main unique id of the row
-- UNIQUE        = a CANDIDATE KEY (another column that could identify the row)
-- FOREIGN KEY   = points to the primary key of another table
-- =====================================================================

CREATE TABLE publishers (
    publisher_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    publisher_name  TEXT NOT NULL UNIQUE,          -- candidate key
    city            TEXT
);

CREATE TABLE authors (
    author_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    author_name  TEXT NOT NULL UNIQUE,             -- candidate key
    country      TEXT
);

CREATE TABLE categories (
    category_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    category_name  TEXT NOT NULL UNIQUE            -- candidate key
);

-- Loan rules depend on the membership TYPE, not on the member (3NF)
CREATE TABLE membership_types (
    type_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    type_name     TEXT NOT NULL UNIQUE,            -- candidate key
    max_books     INTEGER NOT NULL CHECK (max_books > 0),
    loan_days     INTEGER NOT NULL CHECK (loan_days > 0),
    fine_per_day  REAL NOT NULL DEFAULT 0 CHECK (fine_per_day >= 0)
);

CREATE TABLE members (
    member_id           INTEGER PRIMARY KEY AUTOINCREMENT,
    member_name         TEXT NOT NULL,
    email               TEXT NOT NULL UNIQUE,      -- candidate key
    phone               TEXT UNIQUE,               -- candidate key
    join_date           TEXT NOT NULL DEFAULT (date('now')),
    status              TEXT NOT NULL DEFAULT 'Active'
                        CHECK (status IN ('Active', 'Suspended')),
    membership_type_id  INTEGER NOT NULL,
    FOREIGN KEY (membership_type_id) REFERENCES membership_types(type_id)
);

-- One table for BOTH physical books and digital resources.
-- resource_type tells them apart. Digital items use "copies" as licences.
CREATE TABLE resources (
    resource_id       INTEGER PRIMARY KEY AUTOINCREMENT,
    title             TEXT NOT NULL,
    resource_type     TEXT NOT NULL CHECK (resource_type IN ('Physical', 'Digital')),
    isbn              TEXT UNIQUE,                 -- candidate key (can be empty)
    publication_year  INTEGER,
    total_copies      INTEGER NOT NULL CHECK (total_copies >= 0),
    available_copies  INTEGER NOT NULL CHECK (available_copies >= 0),
    access_link       TEXT,                        -- only used by digital items
    publisher_id      INTEGER NOT NULL,
    category_id       INTEGER NOT NULL,
    CHECK (available_copies <= total_copies),
    FOREIGN KEY (publisher_id) REFERENCES publishers(publisher_id),
    FOREIGN KEY (category_id)  REFERENCES categories(category_id)
);

-- Many-to-many link: a resource can have many authors, an author many resources
CREATE TABLE resource_authors (
    resource_id  INTEGER NOT NULL,
    author_id    INTEGER NOT NULL,
    PRIMARY KEY (resource_id, author_id),          -- composite primary key
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id),
    FOREIGN KEY (author_id)   REFERENCES authors(author_id)
);

-- Borrow / return history. return_date is NULL while the item is still out.
CREATE TABLE transactions (
    transaction_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id       INTEGER NOT NULL,
    resource_id     INTEGER NOT NULL,
    issue_date      TEXT NOT NULL,
    due_date        TEXT NOT NULL,
    return_date     TEXT,
    status          TEXT NOT NULL DEFAULT 'Issued'
                    CHECK (status IN ('Issued', 'Returned')),
    FOREIGN KEY (member_id)   REFERENCES members(member_id),
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id)
);

CREATE TABLE reservations (
    reservation_id    INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id         INTEGER NOT NULL,
    resource_id       INTEGER NOT NULL,
    reservation_date  TEXT NOT NULL,
    status            TEXT NOT NULL DEFAULT 'Active'
                      CHECK (status IN ('Active', 'Fulfilled', 'Cancelled')),
    FOREIGN KEY (member_id)   REFERENCES members(member_id),
    FOREIGN KEY (resource_id) REFERENCES resources(resource_id)
);

-- One penalty per late-returned transaction
CREATE TABLE penalties (
    penalty_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id  INTEGER NOT NULL UNIQUE,       -- candidate key (1 penalty per loan)
    days_late       INTEGER NOT NULL CHECK (days_late > 0),
    amount          REAL NOT NULL CHECK (amount >= 0),
    penalty_date    TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'Unpaid'
                    CHECK (status IN ('Paid', 'Unpaid')),
    FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
);

-- =====================================================================
-- 2. INDEXES  (make searching and joining faster)
-- =====================================================================
CREATE INDEX idx_transactions_member    ON transactions(member_id);
CREATE INDEX idx_transactions_resource  ON transactions(resource_id);
CREATE INDEX idx_transactions_due_date  ON transactions(due_date);
CREATE INDEX idx_resources_title        ON resources(title);
CREATE INDEX idx_members_name           ON members(member_name);
CREATE INDEX idx_reservations_resource  ON reservations(resource_id, status);

-- =====================================================================
-- 3. DML  -  INSERT dummy data
-- (dates use date('now', '-N days') so overdue data is always fresh)
-- =====================================================================
INSERT INTO publishers (publisher_name, city) VALUES
    ('McGraw Hill',       'New York'),
    ('Pearson',           'London'),
    ('No Starch Press',   'San Francisco'),
    ('OReilly Media',     'Sebastopol');

INSERT INTO authors (author_name, country) VALUES
    ('Abraham Silberschatz', 'USA'),
    ('Henry Korth',          'USA'),
    ('Ramez Elmasri',        'USA'),
    ('Eric Matthes',         'USA'),
    ('Thomas Cormen',        'USA'),
    ('Robert Martin',        'USA'),
    ('Alan Beaulieu',        'USA'),
    ('Miguel Grinberg',      'USA'),
    ('Andrew Tanenbaum',     'Netherlands');

INSERT INTO categories (category_name) VALUES
    ('Databases'), ('Programming'), ('Algorithms'), ('Systems');

INSERT INTO membership_types (type_name, max_books, loan_days, fine_per_day) VALUES
    ('Student', 3, 14, 2.0),
    ('Faculty', 5, 30, 1.0),
    ('Guest',   1,  7, 5.0);

INSERT INTO members (member_name, email, phone, join_date, status, membership_type_id) VALUES
    ('Aarav Sharma', 'aarav@college.edu', '9000000001', date('now','-200 days'), 'Active', 1),
    ('Diya Verma',   'diya@college.edu',  '9000000002', date('now','-180 days'), 'Active', 1),
    ('Dr. Mehta',    'mehta@college.edu', '9000000003', date('now','-400 days'), 'Active', 2),
    ('Rohan Gupta',  'rohan@college.edu', '9000000004', date('now','-90 days'),  'Active', 1),
    ('Sneha Iyer',   'sneha@college.edu', '9000000005', date('now','-60 days'),  'Active', 1),
    ('Guest Visitor','guest@example.com', '9000000006', date('now','-30 days'),  'Active', 3);

INSERT INTO resources (title, resource_type, isbn, publication_year, total_copies, available_copies, access_link, publisher_id, category_id) VALUES
    ('Database System Concepts',          'Physical', '9780078022159', 2019,   5,   3,  NULL, 1, 1),  -- id 1
    ('Fundamentals of Database Systems',  'Physical', '9780133970777', 2016,   3,   3,  NULL, 2, 1),  -- id 2
    ('Python Crash Course',               'Physical', '9781593279288', 2019,   4,   3,  NULL, 3, 2),  -- id 3
    ('Introduction to Algorithms',        'Physical', '9780262033848', 2009,   2,   2,  NULL, 1, 3),  -- id 4
    ('Clean Code',                        'Physical', '9780132350884', 2008,   3,   2,  NULL, 2, 2),  -- id 5
    ('Operating System Concepts',         'Physical', '9781119800361', 2021,   2,   1,  NULL, 1, 4),  -- id 6
    ('Learning SQL (E-Book)',             'Digital',  '9780596520830', 2009, 100,  100, 'https://example.com/learning-sql', 4, 1),  -- id 7
    ('Flask Web Development (E-Book)',    'Digital',  '9781491991732', 2018, 100,   99, 'https://example.com/flask-book',   4, 2),  -- id 8
    ('Computer Networks',                 'Physical', '9780132126953', 2010,   2,   2,  NULL, 2, 4);  -- id 9 (never borrowed)

INSERT INTO resource_authors (resource_id, author_id) VALUES
    (1,1), (1,2), (2,3), (3,4), (4,5), (5,6), (6,1), (6,2), (7,7), (8,8), (9,9);

-- Borrow history. Rows with NULL return_date are still borrowed.
INSERT INTO transactions (member_id, resource_id, issue_date, due_date, return_date, status) VALUES
    (1, 1, date('now','-40 days'), date('now','-26 days'), date('now','-28 days'), 'Returned'),  -- on time
    (2, 2, date('now','-35 days'), date('now','-21 days'), date('now','-15 days'), 'Returned'),  -- 6 days late
    (3, 4, date('now','-50 days'), date('now','-20 days'), date('now','-22 days'), 'Returned'),  -- on time
    (4, 1, date('now','-30 days'), date('now','-16 days'), date('now','-10 days'), 'Returned'),  -- 6 days late
    (1, 3, date('now','-25 days'), date('now','-11 days'), date('now','-12 days'), 'Returned'),  -- on time
    (5, 7, date('now','-20 days'), date('now','-6 days'),  date('now','-8 days'),  'Returned'),  -- digital
    (6, 1, date('now','-45 days'), date('now','-38 days'), date('now','-38 days'), 'Returned'),  -- on time
    (1, 1, date('now','-20 days'), date('now','-6 days'),  NULL, 'Issued'),                      -- OVERDUE
    (2, 5, date('now','-18 days'), date('now','-4 days'),  NULL, 'Issued'),                      -- OVERDUE
    (3, 1, date('now','-10 days'), date('now','20 days'),  NULL, 'Issued'),
    (4, 3, date('now','-5 days'),  date('now','9 days'),   NULL, 'Issued'),
    (6, 6, date('now','-10 days'), date('now','-3 days'),  NULL, 'Issued'),                      -- OVERDUE
    (5, 8, date('now','-2 days'),  date('now','12 days'),  NULL, 'Issued');

INSERT INTO reservations (member_id, resource_id, reservation_date, status) VALUES
    (4, 6, date('now','-2 days'), 'Active'),
    (1, 6, date('now','-1 days'), 'Active'),
    (3, 2, date('now','-9 days'), 'Fulfilled'),
    (6, 4, date('now','-3 days'), 'Cancelled');

-- Penalties for the two late returns (6 days x Rs.2 per day = Rs.12)
INSERT INTO penalties (transaction_id, days_late, amount, penalty_date, status) VALUES
    (2, 6, 12.0, date('now','-15 days'), 'Paid'),
    (4, 6, 12.0, date('now','-10 days'), 'Unpaid');

-- =====================================================================
-- 4. VIEWS  (saved queries that behave like tables)
-- =====================================================================

-- View 1: items not yet returned whose due date has passed
CREATE VIEW v_overdue_books AS
SELECT  t.transaction_id,
        m.member_name,
        r.title,
        t.issue_date,
        t.due_date,
        CAST(julianday(date('now')) - julianday(t.due_date) AS INTEGER)                    AS days_overdue,
        CAST(julianday(date('now')) - julianday(t.due_date) AS INTEGER) * mt.fine_per_day  AS fine_so_far
FROM    transactions t
JOIN    members m            ON m.member_id = t.member_id
JOIN    resources r          ON r.resource_id = t.resource_id
JOIN    membership_types mt  ON mt.type_id = m.membership_type_id
WHERE   t.return_date IS NULL
  AND   t.due_date < date('now');

-- View 2: how many times each resource was borrowed
CREATE VIEW v_popular_resources AS
SELECT  r.resource_id,
        r.title,
        r.resource_type,
        COUNT(t.transaction_id) AS times_borrowed
FROM    resources r
LEFT JOIN transactions t ON t.resource_id = r.resource_id
GROUP BY r.resource_id, r.title, r.resource_type;

-- View 3: one summary line per member (uses subqueries)
CREATE VIEW v_member_summary AS
SELECT  m.member_id,
        m.member_name,
        mt.type_name,
        (SELECT COUNT(*) FROM transactions t WHERE t.member_id = m.member_id)                          AS total_borrows,
        (SELECT COUNT(*) FROM transactions t WHERE t.member_id = m.member_id AND t.return_date IS NULL) AS books_out_now,
        (SELECT IFNULL(SUM(p.amount), 0)
           FROM penalties p JOIN transactions t ON t.transaction_id = p.transaction_id
          WHERE t.member_id = m.member_id AND p.status = 'Unpaid')                                      AS unpaid_fines
FROM    members m
JOIN    membership_types mt ON mt.type_id = m.membership_type_id;

-- =====================================================================
-- 5. ANALYTICS QUERIES
-- (the Reports page of the website runs these same queries)
-- =====================================================================

-- 5.1 JOIN: every loan with member name and book title
SELECT t.transaction_id, m.member_name, r.title, t.issue_date, t.due_date, t.status
FROM   transactions t
JOIN   members m   ON m.member_id = t.member_id
JOIN   resources r ON r.resource_id = t.resource_id
ORDER BY t.issue_date DESC;

-- 5.2 JOIN across many tables: books with publisher, category and authors
SELECT r.title, p.publisher_name, c.category_name, GROUP_CONCAT(a.author_name, ', ') AS authors
FROM   resources r
JOIN   publishers p        ON p.publisher_id = r.publisher_id
JOIN   categories c        ON c.category_id  = r.category_id
JOIN   resource_authors ra ON ra.resource_id = r.resource_id
JOIN   authors a           ON a.author_id    = ra.author_id
GROUP BY r.resource_id;

-- 5.3 SUBQUERY: members who borrowed MORE than the average member
SELECT m.member_name, COUNT(*) AS borrow_count
FROM   transactions t
JOIN   members m ON m.member_id = t.member_id
GROUP BY m.member_id
HAVING COUNT(*) > (SELECT AVG(cnt)
                   FROM (SELECT COUNT(*) AS cnt FROM transactions GROUP BY member_id));

-- 5.4 SET OPERATION - UNION: members who borrowed OR reserved something
SELECT member_id FROM transactions
UNION
SELECT member_id FROM reservations;

-- 5.5 SET OPERATION - INTERSECT: members who borrowed AND reserved
SELECT m.member_name FROM members m WHERE m.member_id IN (SELECT member_id FROM transactions)
INTERSECT
SELECT m.member_name FROM members m WHERE m.member_id IN (SELECT member_id FROM reservations);

-- 5.6 SET OPERATION - EXCEPT: resources that were NEVER borrowed
SELECT title FROM resources
EXCEPT
SELECT r.title FROM resources r JOIN transactions t ON t.resource_id = r.resource_id;

-- 5.7 WINDOW FUNCTION: rank resources inside each category by popularity
SELECT c.category_name,
       r.title,
       COUNT(t.transaction_id) AS times_borrowed,
       RANK() OVER (PARTITION BY c.category_name
                    ORDER BY COUNT(t.transaction_id) DESC) AS rank_in_category
FROM   resources r
JOIN   categories c ON c.category_id = r.category_id
LEFT JOIN transactions t ON t.resource_id = r.resource_id
GROUP BY r.resource_id;

-- 5.8 CTE: OVERDUE books with fine (CTE = a temporary named result)
WITH overdue AS (
    SELECT t.transaction_id, t.member_id, t.resource_id, t.due_date,
           CAST(julianday(date('now')) - julianday(t.due_date) AS INTEGER) AS days_late
    FROM   transactions t
    WHERE  t.return_date IS NULL AND t.due_date < date('now')
)
SELECT m.member_name, r.title, o.due_date, o.days_late,
       o.days_late * mt.fine_per_day AS fine
FROM   overdue o
JOIN   members m           ON m.member_id = o.member_id
JOIN   resources r         ON r.resource_id = o.resource_id
JOIN   membership_types mt ON mt.type_id = m.membership_type_id
ORDER BY o.days_late DESC;

-- 5.9 CTE: FREQUENTLY BORROWED resources (borrowed more than average)
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

-- =====================================================================
-- 6. DCL  -  Data Control Language
-- SQLite has no users/permissions, so these are COMMENTS that show the
-- syntax you would run in MySQL / PostgreSQL / Oracle.
-- =====================================================================
-- CREATE USER 'librarian'@'localhost' IDENTIFIED BY 'lib123';
-- GRANT SELECT, INSERT, UPDATE ON library.transactions TO 'librarian'@'localhost';
-- GRANT SELECT ON library.* TO 'student'@'localhost';
-- REVOKE UPDATE ON library.transactions FROM 'librarian'@'localhost';

-- =====================================================================
-- 7. TCL  -  Transaction Control Language
-- This demo is wrapped in BEGIN ... ROLLBACK so it leaves the data
-- unchanged. Change the last ROLLBACK to COMMIT to make changes permanent.
-- =====================================================================
BEGIN TRANSACTION;
    INSERT INTO categories (category_name) VALUES ('Temp Category 1');
    SAVEPOINT after_first_insert;
    INSERT INTO categories (category_name) VALUES ('Temp Category 2');
    ROLLBACK TO after_first_insert;   -- undoes only Temp Category 2
ROLLBACK;                             -- undoes everything (use COMMIT to keep)
