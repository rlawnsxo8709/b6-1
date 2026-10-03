import subprocess
import unittest

from tests.helpers import ROOT


def run_script():
    return subprocess.run(["bash", "scripts/run_all.sh"], cwd=ROOT, capture_output=True, text=True, timeout=60)


class TestRunAll(unittest.TestCase):
    def test_script_generates_results_twice(self):
        for _ in range(2):  # 재실행해도 깨지지 않음
            p = run_script()
            self.assertEqual(p.returncode, 0, p.stderr)
        files = list((ROOT / "results").glob("Q*.txt"))
        self.assertGreaterEqual(len(files), 15)
        self.assertIn("FOREIGN KEY constraint failed", (ROOT / "results" / "fk-check.txt").read_text(encoding="utf-8"))
        q14 = (ROOT / "results" / "Q14.txt").read_text(encoding="utf-8")
        self.assertIn("no_show", q14)

    def test_each_result_file_has_query_text_and_output(self):
        self.assertEqual(run_script().returncode, 0)
        for i in range(1, 17):
            text = (ROOT / "results" / f"Q{i:02d}.txt").read_text(encoding="utf-8")
            self.assertTrue(text.startswith(f"-- Q{i:02d} ["), f"Q{i:02d} 머리 주석으로 시작하지 않음")
            self.assertIn("-- 실행 결과", text)
            output = text.split("-- 실행 결과", 1)[1]
            self.assertTrue(output.split("\n", 1)[1].strip(), f"Q{i:02d} 출력이 비어 있음")

    def test_results_are_reproducible(self):
        """기준일 리터럴만 쓰므로 두 번 실행한 결과 파일의 내용이 같아야 한다."""
        self.assertEqual(run_script().returncode, 0)
        first = {p.name: p.read_text(encoding="utf-8") for p in (ROOT / "results").glob("*.txt")}
        self.assertEqual(run_script().returncode, 0)
        second = {p.name: p.read_text(encoding="utf-8") for p in (ROOT / "results").glob("*.txt")}
        self.assertEqual(first, second)

    def test_fk_check_records_blocked_inserts_with_fk_on(self):
        """sqlite3 CLI 는 FK 가 기본으로 꺼져 있다. 스크립트가 켜고 실행했다면 실패 메시지가 남는다."""
        self.assertEqual(run_script().returncode, 0)
        text = (ROOT / "results" / "fk-check.txt").read_text(encoding="utf-8")
        self.assertGreaterEqual(text.count("FOREIGN KEY constraint failed"), 2)


if __name__ == "__main__":
    unittest.main()
