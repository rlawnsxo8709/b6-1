"""테스트 공용 도우미: SQL 파일을 메모리 DB에 순서대로 실행한다."""
import pathlib
import sqlite3

ROOT = pathlib.Path(__file__).resolve().parents[1]


def connect(*sql_files):
    """FK를 켠 메모리 DB를 만들고 sql/ 아래 파일을 순서대로 실행한다.

    sqlite3 연결은 FK 강제가 기본으로 꺼져 있어서, 파일을 실행하기 전에 먼저 켠다.
    """
    con = sqlite3.connect(":memory:")
    con.execute("PRAGMA foreign_keys = ON")
    for f in sql_files:
        con.executescript((ROOT / "sql" / f).read_text(encoding="utf-8"))
    return con
