import re
import unittest

from tests.helpers import connect, ROOT

HEADER = re.compile(r"^-- (Q\d{2}) \[([^\]]+)\] (.+)$", re.M)


def split_queries():
    """머리 주석(`-- Qnn [범주] 설명`)을 기준으로 쿼리 파일을 (번호, 범주, 설명, 본문)으로 나눈다."""
    text = (ROOT / "sql" / "03_queries.sql").read_text(encoding="utf-8")
    heads = list(HEADER.finditer(text))
    out = []
    for i, m in enumerate(heads):
        end = heads[i + 1].start() if i + 1 < len(heads) else len(text)
        out.append((m.group(1), m.group(2), m.group(3), text[m.end():end].strip()))
    return out


class TestQueries(unittest.TestCase):
    def test_count_and_categories(self):
        qs = split_queries()
        cats = [c for _, c, _, _ in qs]
        self.assertGreaterEqual(len(qs), 15)
        self.assertGreaterEqual(cats.count("기본조회"), 4)
        self.assertGreaterEqual(cats.count("INNER JOIN"), 2)
        self.assertGreaterEqual(cats.count("LEFT JOIN"), 1)
        self.assertGreaterEqual(cats.count("INNER JOIN") + cats.count("LEFT JOIN"), 4)
        self.assertGreaterEqual(cats.count("집계"), 3)
        self.assertGreaterEqual(cats.count("서브쿼리"), 1)
        self.assertGreaterEqual(cats.count("수정") + cats.count("삭제"), 2)
        self.assertGreaterEqual(cats.count("인덱스"), 1)
        for _, _, desc, _ in qs:
            self.assertTrue(desc.strip())

    def test_every_query_runs_in_order_and_has_rows_or_effect(self):
        con = connect("01_schema.sql", "02_seed.sql")
        self.addCleanup(con.close)
        for qid, cat, _, body in split_queries():
            cur = con.executescript(body) if cat in ("수정", "삭제", "인덱스") else con.execute(body)
            if cat in ("기본조회", "INNER JOIN", "LEFT JOIN", "집계", "서브쿼리"):
                self.assertGreater(len(cur.fetchall()), 0, f"{qid} 결과가 비어 있음")

    def test_keyword_requirements(self):
        text = (ROOT / "sql" / "03_queries.sql").read_text(encoding="utf-8").upper()
        for kw in ["WHERE", "ORDER BY", "LIMIT", "INNER JOIN", "LEFT JOIN", "GROUP BY", "COUNT(", "SUM(", "AVG(", "UPDATE", "DELETE", "CREATE INDEX"]:
            self.assertIn(kw, text, kw)


    def test_mutating_queries_come_last(self):
        """수정·삭제·인덱스 쿼리가 읽기 쿼리 결과를 바꾸지 않도록 파일 끝쪽에 모여 있어야 한다."""
        cats = [c for _, c, _, _ in split_queries()]
        read_cats = {"기본조회", "INNER JOIN", "LEFT JOIN", "집계", "서브쿼리"}
        last_read = max(i for i, c in enumerate(cats) if c in read_cats)
        first_write = min(i for i, c in enumerate(cats) if c not in read_cats)
        self.assertLess(last_read, first_write)

    def test_query_ids_are_sequential(self):
        ids = [q for q, _, _, _ in split_queries()]
        self.assertEqual(ids, [f"Q{i:02d}" for i in range(1, len(ids) + 1)])

    def test_left_join_keeps_rows_that_inner_join_drops(self):
        """Q07(LEFT JOIN)은 예약 0건 회원까지, Q05(INNER JOIN)는 예약이 있는 행만 보여 준다."""
        con = connect("01_schema.sql", "02_seed.sql")
        self.addCleanup(con.close)
        qs = {q: body for q, _, _, body in split_queries()}
        members = con.execute("SELECT COUNT(*) FROM member").fetchone()[0]
        left_rows = con.execute(qs["Q07"]).fetchall()
        self.assertEqual(len(left_rows), members)
        self.assertGreaterEqual(sum(1 for r in left_rows if r[2] == 0), 2)
        self.assertEqual(len(con.execute(qs["Q05"]).fetchall()),
                         con.execute("SELECT COUNT(*) FROM booking").fetchone()[0])

    def test_unbooked_lessons_and_members_are_found(self):
        con = connect("01_schema.sql", "02_seed.sql")
        self.addCleanup(con.close)
        qs = {q: body for q, _, _, body in split_queries()}
        self.assertEqual(len(con.execute(qs["Q08"]).fetchall()), 3)
        self.assertEqual({r[0] for r in con.execute(qs["Q13"])}, {9, 14, 15})
        self.assertEqual(len(con.execute(qs["Q02"]).fetchall()), 5)

    def test_update_and_delete_change_data_as_described(self):
        con = connect("01_schema.sql", "02_seed.sql")
        self.addCleanup(con.close)
        qs = {q: body for q, _, _, body in split_queries()}
        stale = ("SELECT COUNT(*) FROM booking b JOIN lesson l ON l.id = b.lesson_id "
                 "WHERE b.status = 'booked' AND l.starts_at < '2026-10-01'")
        no_show = "SELECT COUNT(*) FROM booking WHERE status = 'no_show'"
        cancelled = "SELECT COUNT(*) FROM booking WHERE status = 'cancelled'"
        total = "SELECT COUNT(*) FROM booking"
        n = lambda sql: con.execute(sql).fetchone()[0]
        stale_before, no_show_before = n(stale), n(no_show)
        self.assertGreaterEqual(stale_before, 2)
        con.executescript(qs["Q14"])
        self.assertEqual(n(stale), 0)
        self.assertEqual(n(no_show), no_show_before + stale_before)
        cancelled_before, total_before = n(cancelled), n(total)
        self.assertGreater(cancelled_before, 0)
        con.executescript(qs["Q15"])
        self.assertEqual(n(cancelled), 0)
        self.assertEqual(n(total), total_before - cancelled_before)

    def test_index_is_used_after_create_index(self):
        con = connect("01_schema.sql", "02_seed.sql")
        self.addCleanup(con.close)
        qs = {q: body for q, _, _, body in split_queries()}
        con.executescript(qs["Q16"])
        plan = " ".join(str(r[3]) for r in con.execute("EXPLAIN QUERY PLAN SELECT * FROM booking WHERE lesson_id = 3"))
        self.assertIn("idx_booking_lesson_id", plan)

    def test_no_date_now_and_sqlite_only_syntax_is_marked(self):
        for path in sorted((ROOT / "sql").glob("*.sql")):
            for line in path.read_text(encoding="utf-8").splitlines():
                code = line.split("--")[0].upper()  # 주석 앞의 SQL 코드 부분만 본다
                self.assertNotIn("DATE('NOW')", code, f"{path.name}: {line}")
                if "PRAGMA" in code or "EXPLAIN QUERY PLAN" in code or "STRFTIME" in code:
                    self.assertIn("[SQLite 전용]", line, f"{path.name}: {line}")

if __name__ == "__main__":
    unittest.main()
