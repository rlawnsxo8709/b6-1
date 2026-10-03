import unittest

from tests.helpers import connect


class TestSeed(unittest.TestCase):
    def setUp(self):
        self.addCleanup(lambda: self.con.close())
        self.con = connect("01_schema.sql", "02_seed.sql")

    def q(self, sql):
        return self.con.execute(sql).fetchone()[0]

    def test_min_rows(self):
        for t in ["membership_plan", "member", "trainer", "lesson", "booking"]:
            self.assertGreaterEqual(self.q(f"SELECT COUNT(*) FROM {t}"), 10, t)

    def test_fk_integrity(self):
        self.assertEqual(self.con.execute("PRAGMA foreign_key_check").fetchall(), [])

    def test_data_supports_queries(self):
        self.assertGreaterEqual(self.q("SELECT COUNT(*) FROM member m WHERE NOT EXISTS (SELECT 1 FROM booking b WHERE b.member_id = m.id)"), 2)
        self.assertGreaterEqual(self.q("SELECT COUNT(*) FROM lesson l WHERE NOT EXISTS (SELECT 1 FROM booking b WHERE b.lesson_id = l.id)"), 2)
        self.assertEqual(self.q("SELECT COUNT(DISTINCT status) FROM booking"), 4)
        self.assertGreaterEqual(self.q("SELECT COUNT(*) FROM booking b JOIN lesson l ON l.id = b.lesson_id WHERE b.status = 'booked' AND l.starts_at < '2026-10-01'"), 2)


if __name__ == "__main__":
    unittest.main()
