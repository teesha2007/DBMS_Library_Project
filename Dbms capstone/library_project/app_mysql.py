# =====================================================================
#  app_mysql.py  -  SAME website, but it uses MySQL (library_db)
#  instead of SQLite, so MySQL Workbench shows the SAME live data.
#
#  BEFORE RUNNING:
#   1. pip install flask mysql-connector-python
#   2. Run database_mysql.sql in MySQL Workbench (creates library_db)
#   3. Put YOUR MySQL root password in DB_PASSWORD below
#   4. python app_mysql.py
#
#  It uses the same templates folder as app.py (no HTML changes needed).
# =====================================================================

from datetime import date, timedelta

import mysql.connector
from flask import Flask, render_template, request, redirect, url_for, flash

app = Flask(__name__)
app.secret_key = "change-me-any-text"

# ---------------------------------------------------------------------
# DATABASE SETTINGS  -  EDIT DB_PASSWORD (the password you set for root)
# ---------------------------------------------------------------------
DB_HOST = "localhost"
DB_USER = "root"
DB_PASSWORD = "RakshitRathour@0916"
DB_NAME = "library_db"


def get_db():
    """Open a connection to MySQL."""
    return mysql.connector.connect(
        host=DB_HOST, user=DB_USER, password=DB_PASSWORD, database=DB_NAME
    )


def run_query(sql, params=()):
    """Run a SELECT and return all rows as dictionaries (row["title"])."""
    conn = get_db()
    cur = conn.cursor(dictionary=True)
    cur.execute(sql, params)
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return rows


def scalar(sql, params=()):
    """Run a SELECT that returns ONE value (like a COUNT) and give that value."""
    conn = get_db()
    cur = conn.cursor()
    cur.execute(sql, params)
    value = cur.fetchone()[0]
    cur.close()
    conn.close()
    return value


def fetch_one(cur, sql, params=()):
    """Run a SELECT on an existing cursor and return the first row (or None)."""
    cur.execute(sql, params)
    return cur.fetchone()


def get_or_create(cur, table, id_column, name_column, name):
    """Find a row by name (e.g. an author). If missing, insert it. Return its id."""
    cur.execute(f"SELECT {id_column} FROM {table} WHERE {name_column} = %s", (name,))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute(f"INSERT INTO {table} ({name_column}) VALUES (%s)", (name,))
    return cur.lastrowid


# ---------------------------------------------------------------------
# HOME / DASHBOARD
# ---------------------------------------------------------------------
@app.route("/")
def home():
    stats = {
        "resources": scalar("SELECT COUNT(*) FROM resources"),
        "physical_available": scalar("SELECT IFNULL(SUM(available_copies), 0) FROM resources WHERE resource_type = 'Physical'"),
        "physical_total": scalar("SELECT IFNULL(SUM(total_copies), 0) FROM resources WHERE resource_type = 'Physical'"),
        "digital": scalar("SELECT COUNT(*) FROM resources WHERE resource_type = 'Digital'"),
        "members": scalar("SELECT COUNT(*) FROM members"),
        "issued": scalar("SELECT COUNT(*) FROM transactions WHERE return_date IS NULL"),
        "overdue": scalar("SELECT COUNT(*) FROM v_overdue_books"),
        "unpaid": scalar("SELECT IFNULL(SUM(amount), 0) FROM penalties WHERE status = 'Unpaid'"),
        "reservations": scalar("SELECT COUNT(*) FROM reservations WHERE status = 'Active'"),
    }
    recent = run_query(
        """SELECT m.member_name, r.title, t.issue_date, t.status
           FROM transactions t
           JOIN members m   ON m.member_id = t.member_id
           JOIN resources r ON r.resource_id = t.resource_id
           ORDER BY t.transaction_id DESC LIMIT 5"""
    )
    return render_template("index.html", stats=stats, recent=recent)


# ---------------------------------------------------------------------
# BOOKS AND DIGITAL RESOURCES
# ---------------------------------------------------------------------
@app.route("/books")
def books():
    resources = run_query(
        """SELECT r.resource_id, r.title, r.resource_type, r.isbn,
                  r.publication_year, r.total_copies, r.available_copies,
                  r.access_link, p.publisher_name, c.category_name,
                  (SELECT GROUP_CONCAT(a.author_name SEPARATOR ', ')
                     FROM resource_authors ra
                     JOIN authors a ON a.author_id = ra.author_id
                    WHERE ra.resource_id = r.resource_id) AS authors
           FROM resources r
           JOIN publishers p ON p.publisher_id = r.publisher_id
           JOIN categories c ON c.category_id  = r.category_id
           ORDER BY r.title"""
    )
    categories = run_query("SELECT * FROM categories ORDER BY category_name")
    return render_template("books.html", resources=resources, categories=categories)


@app.route("/books/add", methods=["POST"])
def add_book():
    title = request.form["title"].strip()
    resource_type = request.form["resource_type"]
    isbn = request.form["isbn"].strip() or None
    year = request.form["year"].strip() or None
    copies = int(request.form["copies"])
    link = request.form["access_link"].strip() or None
    publisher = request.form["publisher"].strip()
    author = request.form["author"].strip()
    category_id = int(request.form["category_id"])

    conn = get_db()
    cur = conn.cursor()
    try:
        publisher_id = get_or_create(cur, "publishers", "publisher_id", "publisher_name", publisher)
        author_id = get_or_create(cur, "authors", "author_id", "author_name", author)
        cur.execute(
            """INSERT INTO resources
               (title, resource_type, isbn, publication_year, total_copies,
                available_copies, access_link, publisher_id, category_id)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)""",
            (title, resource_type, isbn, year, copies, copies, link, publisher_id, category_id),
        )
        cur.execute(
            "INSERT INTO resource_authors (resource_id, author_id) VALUES (%s, %s)",
            (cur.lastrowid, author_id),
        )
        conn.commit()
        flash("Resource added successfully.", "success")
    except mysql.connector.Error as error:
        conn.rollback()
        flash(f"Could not add resource: {error}", "error")
    finally:
        cur.close()
        conn.close()
    return redirect(url_for("books"))


# ---------------------------------------------------------------------
# MEMBERS
# ---------------------------------------------------------------------
@app.route("/members")
def members():
    members_list = run_query("SELECT * FROM v_member_summary ORDER BY member_id")
    types = run_query("SELECT * FROM membership_types")
    return render_template("members.html", members=members_list, types=types)


@app.route("/members/add", methods=["POST"])
def add_member():
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.execute(
            """INSERT INTO members (member_name, email, phone, membership_type_id)
               VALUES (%s, %s, %s, %s)""",
            (
                request.form["name"].strip(),
                request.form["email"].strip(),
                request.form["phone"].strip() or None,
                int(request.form["type_id"]),
            ),
        )
        conn.commit()
        flash("Member added successfully.", "success")
    except mysql.connector.Error as error:
        conn.rollback()
        flash(f"Could not add member (email/phone may already exist): {error}", "error")
    finally:
        cur.close()
        conn.close()
    return redirect(url_for("members"))


# ---------------------------------------------------------------------
# BORROW AND RETURN (CIRCULATION)
# ---------------------------------------------------------------------
@app.route("/circulation")
def circulation():
    members_list = run_query("SELECT member_id, member_name FROM members WHERE status = 'Active'")
    resources = run_query("SELECT resource_id, title, available_copies FROM resources ORDER BY title")

    loans = run_query(
        """SELECT t.transaction_id, m.member_name, r.title, t.issue_date, t.due_date,
                  mt.fine_per_day
           FROM transactions t
           JOIN members m           ON m.member_id = t.member_id
           JOIN resources r         ON r.resource_id = t.resource_id
           JOIN membership_types mt ON mt.type_id = m.membership_type_id
           WHERE t.return_date IS NULL
           ORDER BY t.due_date"""
    )
    today = date.today()
    loan_rows = []
    for loan in loans:
        # MySQL gives real date objects, so we can subtract them directly
        days_late = max(0, (today - loan["due_date"]).days)
        loan_rows.append({
            "transaction_id": loan["transaction_id"],
            "member_name": loan["member_name"],
            "title": loan["title"],
            "issue_date": loan["issue_date"],
            "due_date": loan["due_date"],
            "days_late": days_late,
            "fine": days_late * loan["fine_per_day"],
        })
    return render_template("circulation.html", members=members_list,
                           resources=resources, loans=loan_rows)


@app.route("/borrow", methods=["POST"])
def borrow():
    member_id = int(request.form["member_id"])
    resource_id = int(request.form["resource_id"])
    conn = get_db()
    cur = conn.cursor(dictionary=True)

    member = fetch_one(cur,
        """SELECT m.status, mt.max_books, mt.loan_days
           FROM members m JOIN membership_types mt ON mt.type_id = m.membership_type_id
           WHERE m.member_id = %s""", (member_id,))
    resource = fetch_one(cur,
        "SELECT title, available_copies FROM resources WHERE resource_id = %s", (resource_id,))
    books_out = fetch_one(cur,
        """SELECT COUNT(*) AS n FROM transactions
           WHERE member_id = %s AND return_date IS NULL""", (member_id,))["n"]
    unpaid = fetch_one(cur,
        """SELECT IFNULL(SUM(p.amount), 0) AS total
           FROM penalties p JOIN transactions t ON t.transaction_id = p.transaction_id
           WHERE t.member_id = %s AND p.status = 'Unpaid'""", (member_id,))["total"]

    # ---- Business rules ----
    if member["status"] != "Active":
        flash("This member is suspended.", "error")
    elif resource["available_copies"] < 1:
        flash(f"'{resource['title']}' has no copies left. Please reserve it instead.", "error")
    elif books_out >= member["max_books"]:
        flash(f"Borrow limit reached ({member['max_books']} items for this membership).", "error")
    elif unpaid > 0:
        flash(f"Member has unpaid fines of Rs. {unpaid}. Clear them first.", "error")
    else:
        issue_date = date.today()
        due_date = issue_date + timedelta(days=member["loan_days"])
        cur.execute(
            """INSERT INTO transactions (member_id, resource_id, issue_date, due_date, status)
               VALUES (%s, %s, %s, %s, 'Issued')""",
            (member_id, resource_id, issue_date, due_date))
        cur.execute(
            "UPDATE resources SET available_copies = available_copies - 1 WHERE resource_id = %s",
            (resource_id,))
        cur.execute(
            """UPDATE reservations SET status = 'Fulfilled'
               WHERE member_id = %s AND resource_id = %s AND status = 'Active'""",
            (member_id, resource_id))
        conn.commit()
        flash(f"Issued '{resource['title']}'. Due date: {due_date}.", "success")
    cur.close()
    conn.close()
    return redirect(url_for("circulation"))


@app.route("/return/<int:transaction_id>", methods=["POST"])
def return_book(transaction_id):
    conn = get_db()
    cur = conn.cursor(dictionary=True)
    loan = fetch_one(cur,
        """SELECT t.due_date, t.return_date, mt.fine_per_day, t.resource_id
           FROM transactions t
           JOIN members m           ON m.member_id = t.member_id
           JOIN membership_types mt ON mt.type_id = m.membership_type_id
           WHERE t.transaction_id = %s""", (transaction_id,))

    if loan is None or loan["return_date"] is not None:
        flash("This loan was not found or is already returned.", "error")
    else:
        today = date.today()
        # ---- LATE PENALTY CALCULATION ----
        days_late = (today - loan["due_date"]).days
        if days_late < 0:
            days_late = 0
        fine = days_late * loan["fine_per_day"]   # days late x fine per day

        cur.execute(
            "UPDATE transactions SET return_date = %s, status = 'Returned' WHERE transaction_id = %s",
            (today, transaction_id))
        cur.execute(
            "UPDATE resources SET available_copies = available_copies + 1 WHERE resource_id = %s",
            (loan["resource_id"],))
        if days_late > 0:
            cur.execute(
                """INSERT INTO penalties (transaction_id, days_late, amount, penalty_date, status)
                   VALUES (%s, %s, %s, %s, 'Unpaid')""",
                (transaction_id, days_late, fine, today))
            flash(f"Returned {days_late} day(s) late. Penalty: Rs. {fine}.", "error")
        else:
            flash("Returned on time. No penalty.", "success")
        conn.commit()
    cur.close()
    conn.close()
    return redirect(url_for("circulation"))


@app.route("/reserve", methods=["POST"])
def reserve():
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        """INSERT INTO reservations (member_id, resource_id, reservation_date, status)
           VALUES (%s, %s, %s, 'Active')""",
        (int(request.form["member_id"]), int(request.form["resource_id"]), date.today()))
    conn.commit()
    cur.close()
    conn.close()
    flash("Reservation saved.", "success")
    return redirect(url_for("circulation"))


@app.route("/penalty/pay/<int:penalty_id>", methods=["POST"])
def pay_penalty(penalty_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("UPDATE penalties SET status = 'Paid' WHERE penalty_id = %s", (penalty_id,))
    conn.commit()
    cur.close()
    conn.close()
    flash("Penalty marked as paid.", "success")
    return redirect(url_for("reports"))


# ---------------------------------------------------------------------
# REPORTS  (same queries as section 5 of database_mysql.sql)
# ---------------------------------------------------------------------
@app.route("/reports")
def reports():
    data = {}

    # --- Views ---
    data["overdue_view"] = run_query("SELECT * FROM v_overdue_books ORDER BY days_overdue DESC")
    data["popular_view"] = run_query("SELECT * FROM v_popular_resources ORDER BY times_borrowed DESC")
    data["member_view"] = run_query("SELECT * FROM v_member_summary")

    # --- CTE: frequently borrowed ---
    data["frequent_cte"] = run_query(
        """WITH borrow_counts AS (
               SELECT resource_id, COUNT(*) AS times_borrowed
               FROM transactions GROUP BY resource_id
           )
           SELECT r.title, bc.times_borrowed
           FROM borrow_counts bc
           JOIN resources r ON r.resource_id = bc.resource_id
           WHERE bc.times_borrowed > (SELECT AVG(times_borrowed) FROM borrow_counts)
           ORDER BY bc.times_borrowed DESC"""
    )

    # --- Window function ---
    data["ranking"] = run_query(
        """SELECT c.category_name, r.title,
                  COUNT(t.transaction_id) AS times_borrowed,
                  RANK() OVER (PARTITION BY c.category_name
                               ORDER BY COUNT(t.transaction_id) DESC) AS rank_in_category
           FROM resources r
           JOIN categories c ON c.category_id = r.category_id
           LEFT JOIN transactions t ON t.resource_id = r.resource_id
           GROUP BY r.resource_id, r.title, c.category_name
           ORDER BY c.category_name, rank_in_category"""
    )

    # --- Set operations (INTERSECT / EXCEPT need MySQL 8.0.31+) ---
    data["never_borrowed"] = run_query(
        """SELECT title FROM resources
           EXCEPT
           SELECT r.title FROM resources r JOIN transactions t ON t.resource_id = r.resource_id"""
    )
    data["borrowed_and_reserved"] = run_query(
        """SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM transactions)
           INTERSECT
           SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM reservations)"""
    )
    data["active_members"] = run_query(
        """SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM transactions)
           UNION
           SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM reservations)"""
    )

    # --- Penalties ---
    data["penalties"] = run_query(
        """SELECT p.penalty_id, m.member_name, r.title, p.days_late, p.amount, p.status
           FROM penalties p
           JOIN transactions t ON t.transaction_id = p.transaction_id
           JOIN members m      ON m.member_id = t.member_id
           JOIN resources r    ON r.resource_id = t.resource_id
           ORDER BY p.penalty_id"""
    )
    return render_template("reports.html", d=data)


if __name__ == "__main__":
    app.run(debug=True)
