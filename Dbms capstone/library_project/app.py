# =====================================================================
#  app.py  -  Intelligent Library and Digital Resource Management System
#  The WHOLE backend is in this one file.
#
#  How it works (simple version):
#   1. The browser asks for a URL (like /books).
#   2. Flask finds the @app.route("/books") function below.
#   3. That function runs SQL on the SQLite database.
#   4. The result is sent to an HTML page (in the templates folder).
# =====================================================================

import os
import sqlite3
from datetime import date, timedelta

from flask import Flask, render_template, request, redirect, url_for, flash

app = Flask(__name__)
app.secret_key = "change-me-any-text"   # needed by Flask for flash() messages

# ---------------------------------------------------------------------
# DATABASE HELPERS
# ---------------------------------------------------------------------
BASE_FOLDER = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(BASE_FOLDER, "library.db")       # created automatically
SQL_FILE = os.path.join(BASE_FOLDER, "database.sql")    # our tables + data


def get_db():
    """Open a connection to the SQLite database file."""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row            # lets us use row["column_name"]
    conn.execute("PRAGMA foreign_keys = ON")  # make SQLite enforce foreign keys
    return conn


def init_db():
    """If library.db does not exist yet, build it by running database.sql."""
    if os.path.exists(DB_FILE):
        return
    conn = sqlite3.connect(DB_FILE)
    with open(SQL_FILE, encoding="utf-8") as f:
        conn.executescript(f.read())
    conn.close()
    print("Database created from database.sql")


def run_query(sql, params=()):
    """Run a SELECT and return all rows."""
    conn = get_db()
    rows = conn.execute(sql, params).fetchall()
    conn.close()
    return rows


def get_or_create(conn, table, id_column, name_column, name):
    """Find a row by name (e.g. an author). If missing, insert it. Return its id."""
    row = conn.execute(
        f"SELECT {id_column} FROM {table} WHERE {name_column} = ?", (name,)
    ).fetchone()
    if row:
        return row[0]
    cur = conn.execute(f"INSERT INTO {table} ({name_column}) VALUES (?)", (name,))
    return cur.lastrowid


# ---------------------------------------------------------------------
# HOME / DASHBOARD
# ---------------------------------------------------------------------
@app.route("/")
def home():
    stats = {
        "resources": run_query("SELECT COUNT(*) FROM resources")[0][0],
        "members": run_query("SELECT COUNT(*) FROM members")[0][0],
        "issued": run_query("SELECT COUNT(*) FROM transactions WHERE return_date IS NULL")[0][0],
        "overdue": run_query("SELECT COUNT(*) FROM v_overdue_books")[0][0],
        "unpaid": run_query("SELECT IFNULL(SUM(amount), 0) FROM penalties WHERE status = 'Unpaid'")[0][0],
        "reservations": run_query("SELECT COUNT(*) FROM reservations WHERE status = 'Active'")[0][0],
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
                  (SELECT GROUP_CONCAT(a.author_name, ', ')
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
    isbn = request.form["isbn"].strip() or None          # empty -> NULL
    year = request.form["year"].strip() or None
    copies = int(request.form["copies"])
    link = request.form["access_link"].strip() or None
    publisher = request.form["publisher"].strip()
    author = request.form["author"].strip()
    category_id = int(request.form["category_id"])

    conn = get_db()
    try:
        publisher_id = get_or_create(conn, "publishers", "publisher_id", "publisher_name", publisher)
        author_id = get_or_create(conn, "authors", "author_id", "author_name", author)
        cur = conn.execute(
            """INSERT INTO resources
               (title, resource_type, isbn, publication_year, total_copies,
                available_copies, access_link, publisher_id, category_id)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (title, resource_type, isbn, year, copies, copies, link, publisher_id, category_id),
        )
        conn.execute(
            "INSERT INTO resource_authors (resource_id, author_id) VALUES (?, ?)",
            (cur.lastrowid, author_id),
        )
        conn.commit()
        flash("Resource added successfully.", "success")
    except sqlite3.IntegrityError as error:
        conn.rollback()                                   # undo half-finished work
        flash(f"Could not add resource: {error}", "error")
    finally:
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
    try:
        conn.execute(
            """INSERT INTO members (member_name, email, phone, membership_type_id)
               VALUES (?, ?, ?, ?)""",
            (
                request.form["name"].strip(),
                request.form["email"].strip(),
                request.form["phone"].strip() or None,
                int(request.form["type_id"]),
            ),
        )
        conn.commit()
        flash("Member added successfully.", "success")
    except sqlite3.IntegrityError as error:
        flash(f"Could not add member (email/phone may already exist): {error}", "error")
    finally:
        conn.close()
    return redirect(url_for("members"))


# ---------------------------------------------------------------------
# BORROW AND RETURN (CIRCULATION)
# ---------------------------------------------------------------------
@app.route("/circulation")
def circulation():
    members_list = run_query("SELECT member_id, member_name FROM members WHERE status = 'Active'")
    resources = run_query("SELECT resource_id, title, available_copies FROM resources ORDER BY title")

    # Items currently borrowed. We also work out days late + fine so far.
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
        days_late = max(0, (today - date.fromisoformat(loan["due_date"])).days)
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

    member = conn.execute(
        """SELECT m.status, mt.max_books, mt.loan_days
           FROM members m JOIN membership_types mt ON mt.type_id = m.membership_type_id
           WHERE m.member_id = ?""", (member_id,)).fetchone()
    resource = conn.execute(
        "SELECT title, available_copies FROM resources WHERE resource_id = ?",
        (resource_id,)).fetchone()
    books_out = conn.execute(
        "SELECT COUNT(*) FROM transactions WHERE member_id = ? AND return_date IS NULL",
        (member_id,)).fetchone()[0]
    unpaid = conn.execute(
        """SELECT IFNULL(SUM(p.amount), 0)
           FROM penalties p JOIN transactions t ON t.transaction_id = p.transaction_id
           WHERE t.member_id = ? AND p.status = 'Unpaid'""", (member_id,)).fetchone()[0]

    # ---- Business rules: stop the borrow if any rule fails ----
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
        conn.execute(
            """INSERT INTO transactions (member_id, resource_id, issue_date, due_date, status)
               VALUES (?, ?, ?, ?, 'Issued')""",
            (member_id, resource_id, issue_date.isoformat(), due_date.isoformat()))
        conn.execute(
            "UPDATE resources SET available_copies = available_copies - 1 WHERE resource_id = ?",
            (resource_id,))
        # If this member had reserved it, the reservation is now fulfilled
        conn.execute(
            """UPDATE reservations SET status = 'Fulfilled'
               WHERE member_id = ? AND resource_id = ? AND status = 'Active'""",
            (member_id, resource_id))
        conn.commit()
        flash(f"Issued '{resource['title']}'. Due date: {due_date}.", "success")
    conn.close()
    return redirect(url_for("circulation"))


@app.route("/return/<int:transaction_id>", methods=["POST"])
def return_book(transaction_id):
    conn = get_db()
    loan = conn.execute(
        """SELECT t.due_date, t.return_date, mt.fine_per_day, t.resource_id
           FROM transactions t
           JOIN members m           ON m.member_id = t.member_id
           JOIN membership_types mt ON mt.type_id = m.membership_type_id
           WHERE t.transaction_id = ?""", (transaction_id,)).fetchone()

    if loan is None or loan["return_date"] is not None:
        flash("This loan was not found or is already returned.", "error")
    else:
        today = date.today()
        # ---- LATE PENALTY CALCULATION ----
        days_late = (today - date.fromisoformat(loan["due_date"])).days
        if days_late < 0:
            days_late = 0                        # returned early or on time
        fine = days_late * loan["fine_per_day"]  # days late x fine per day

        conn.execute(
            "UPDATE transactions SET return_date = ?, status = 'Returned' WHERE transaction_id = ?",
            (today.isoformat(), transaction_id))
        conn.execute(
            "UPDATE resources SET available_copies = available_copies + 1 WHERE resource_id = ?",
            (loan["resource_id"],))
        if days_late > 0:
            conn.execute(
                """INSERT INTO penalties (transaction_id, days_late, amount, penalty_date, status)
                   VALUES (?, ?, ?, ?, 'Unpaid')""",
                (transaction_id, days_late, fine, today.isoformat()))
            flash(f"Returned {days_late} day(s) late. Penalty: Rs. {fine}.", "error")
        else:
            flash("Returned on time. No penalty.", "success")
        conn.commit()
    conn.close()
    return redirect(url_for("circulation"))


@app.route("/reserve", methods=["POST"])
def reserve():
    conn = get_db()
    conn.execute(
        """INSERT INTO reservations (member_id, resource_id, reservation_date, status)
           VALUES (?, ?, ?, 'Active')""",
        (int(request.form["member_id"]), int(request.form["resource_id"]),
         date.today().isoformat()))
    conn.commit()
    conn.close()
    flash("Reservation saved.", "success")
    return redirect(url_for("circulation"))


@app.route("/penalty/pay/<int:penalty_id>", methods=["POST"])
def pay_penalty(penalty_id):
    conn = get_db()
    conn.execute("UPDATE penalties SET status = 'Paid' WHERE penalty_id = ?", (penalty_id,))
    conn.commit()
    conn.close()
    flash("Penalty marked as paid.", "success")
    return redirect(url_for("reports"))


# ---------------------------------------------------------------------
# REPORTS  (every query here is also in database.sql, section 5)
# ---------------------------------------------------------------------
@app.route("/reports")
def reports():
    data = {}

    # --- Results straight from the VIEWS ---
    data["overdue_view"] = run_query("SELECT * FROM v_overdue_books ORDER BY days_overdue DESC")
    data["popular_view"] = run_query("SELECT * FROM v_popular_resources ORDER BY times_borrowed DESC")
    data["member_view"] = run_query("SELECT * FROM v_member_summary")

    # --- CTE: frequently borrowed resources (more than the average) ---
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

    # --- Window function: rank inside each category ---
    data["ranking"] = run_query(
        """SELECT c.category_name, r.title,
                  COUNT(t.transaction_id) AS times_borrowed,
                  RANK() OVER (PARTITION BY c.category_name
                               ORDER BY COUNT(t.transaction_id) DESC) AS rank_in_category
           FROM resources r
           JOIN categories c ON c.category_id = r.category_id
           LEFT JOIN transactions t ON t.resource_id = r.resource_id
           GROUP BY r.resource_id
           ORDER BY c.category_name, rank_in_category"""
    )

    # --- Set operations ---
    data["never_borrowed"] = run_query(      # EXCEPT
        """SELECT title FROM resources
           EXCEPT
           SELECT r.title FROM resources r JOIN transactions t ON t.resource_id = r.resource_id"""
    )
    data["borrowed_and_reserved"] = run_query(   # INTERSECT
        """SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM transactions)
           INTERSECT
           SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM reservations)"""
    )
    data["active_members"] = run_query(      # UNION
        """SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM transactions)
           UNION
           SELECT member_name FROM members WHERE member_id IN (SELECT member_id FROM reservations)"""
    )

    # --- Penalties (JOIN) ---
    data["penalties"] = run_query(
        """SELECT p.penalty_id, m.member_name, r.title, p.days_late, p.amount, p.status
           FROM penalties p
           JOIN transactions t ON t.transaction_id = p.transaction_id
           JOIN members m      ON m.member_id = t.member_id
           JOIN resources r    ON r.resource_id = t.resource_id
           ORDER BY p.penalty_id"""
    )
    return render_template("reports.html", d=data)


# ---------------------------------------------------------------------
# START THE APP
# ---------------------------------------------------------------------
if __name__ == "__main__":
    init_db()                 # create database the first time
    app.run(debug=True)       # open http://127.0.0.1:5000 in your browser
