import sqlite3
import unittest

from tests.helpers import connect

TABLES = ["membership_plan", "member", "trainer", "lesson", "booking"]


class TestSchema(unittest.TestCase):
    def setUp(self):
        self.addCleanup(lambda: self.con.close())
        self.con = connect("01_schema.sql")

    def test_tables_have_pk(self):
        for t in TABLES:
            cols = self.con.execute(f"PRAGMA table_info({t})").fetchall()
            self.assertTrue(any(c[5] == 1 for c in cols), t)

    def test_at_least_four_fk_relations(self):
        fks = [(t, r[2]) for t in TABLES for r in self.con.execute(f"PRAGMA foreign_key_list({t})")]
        self.assertGreaterEqual(len(fks), 4)

    def test_fk_blocks_missing_parent(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.con.execute("INSERT INTO member VALUES (1,'a','a@x.com',NULL,999,'2026-01-01')")

    def test_unique_and_not_null_and_check(self):
        c = self.con
        c.execute("INSERT INTO membership_plan VALUES (1,'기본',50000,1)")
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("INSERT INTO membership_plan VALUES (2,'기본',1,1)")
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("INSERT INTO member VALUES (1,NULL,'n@x.com',NULL,1,'2026-01-01')")
        c.execute("INSERT INTO trainer VALUES (1,'t','요가','2025-01-01')")
        c.execute("INSERT INTO lesson VALUES (1,1,'L','요가','2026-10-02 09:00',10,10000)")
        c.execute("INSERT INTO member VALUES (1,'m','m@x.com',NULL,1,'2026-01-01')")
        c.execute("INSERT INTO booking VALUES (1,1,1,'2026-09-30 10:00','booked')")
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("INSERT INTO booking VALUES (2,1,1,'2026-09-30 11:00','booked')")
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("INSERT INTO booking VALUES (3,1,1,'2026-09-30 11:00','unknown')")

    def test_restrict_delete_parent_with_children(self):
        c = self.con
        c.execute("INSERT INTO membership_plan VALUES (1,'기본',50000,1)")
        c.execute("INSERT INTO member VALUES (1,'m','m@x.com',NULL,1,'2026-01-01')")
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("DELETE FROM membership_plan WHERE id = 1")


    def test_all_fks_use_on_delete_restrict(self):
        for t in TABLES:
            for r in self.con.execute(f"PRAGMA foreign_key_list({t})"):
                self.assertEqual(r[6], "RESTRICT", f"{t}.{r[3]}")

    def test_cannot_delete_member_or_lesson_with_bookings(self):
        c = self.con
        c.execute("INSERT INTO membership_plan VALUES (1,'기본',50000,1)")
        c.execute("INSERT INTO trainer VALUES (1,'t','요가','2025-01-01')")
        c.execute("INSERT INTO lesson VALUES (1,1,'L','요가','2026-10-02 09:00',10,10000)")
        c.execute("INSERT INTO member VALUES (1,'m','m@x.com',NULL,1,'2026-01-01')")
        c.execute("INSERT INTO booking VALUES (1,1,1,'2026-09-30 10:00','booked')")
        for sql in ("DELETE FROM member WHERE id = 1", "DELETE FROM lesson WHERE id = 1", "DELETE FROM trainer WHERE id = 1"):
            with self.assertRaises(sqlite3.IntegrityError, msg=sql):
                c.execute(sql)
        c.execute("DELETE FROM booking WHERE id = 1")
        c.execute("DELETE FROM member WHERE id = 1")  # 자식이 없으면 지워진다

    def test_booking_requires_existing_member_and_lesson(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.con.execute("INSERT INTO booking VALUES (1,999,999,'2026-09-30 10:00','booked')")

    def test_check_constraints_reject_bad_values(self):
        c = self.con
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("INSERT INTO membership_plan VALUES (1,'음수',-1,1)")
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("INSERT INTO membership_plan VALUES (1,'0개월',1000,0)")
        c.execute("INSERT INTO trainer VALUES (1,'t','요가','2025-01-01')")
        with self.assertRaises(sqlite3.IntegrityError):
            c.execute("INSERT INTO lesson VALUES (1,1,'L','요가','2026-10-02 09:00',0,10000)")


if __name__ == "__main__":
    unittest.main()
