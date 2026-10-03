#!/usr/bin/env bash
# 피트니스 예약 DB 전체 실행.
# 새 DB 생성 -> 스키마 -> 시드 -> 쿼리를 하나씩 실행해 results/ 에 저장한다.
# 사용법: bash scripts/run_all.sh   (몇 번을 실행해도 같은 결과가 나온다)
set -euo pipefail

cd "$(dirname "$0")/.."

DB=fitness.db
RESULTS=results

# 매번 새로 만든다: 앞선 실행에서 UPDATE/DELETE 로 바뀐 데이터가 남지 않도록
rm -f "$DB"
mkdir -p "$RESULTS"
rm -f "$RESULTS"/Q*.txt "$RESULTS"/fk-check.txt

# 스키마와 시드. 오류가 나면 바로 멈춘다(-bail).
sqlite3 -bail "$DB" < sql/01_schema.sql
sqlite3 -bail "$DB" < sql/02_seed.sql

# 03_queries.sql 을 '-- Qnn [범주] 설명' 머리 주석마다 나눈다.
# 구획용 구분선('-- ----...')을 만나면 다음 머리 주석이 나올 때까지 버린다.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
awk -v dir="$tmp" '
  /^-- Q[0-9][0-9] \[/ { out = dir "/" $2 ".sql" }
  /^-- -{10,}/         { out = "" }
  out != ""            { print > out }
' sql/03_queries.sql

# 쿼리 번호(Q01~Q16) 순서대로 실행한다. 데이터를 바꾸는 Q14, Q15 가 뒤쪽이라 앞 결과에 영향이 없다.
for qfile in "$tmp"/Q*.sql; do
  id="$(basename "$qfile" .sql)"
  body="$(cat "$qfile")"
  {
    printf '%s\n\n' "$body"
    printf -- '-- 실행 결과 (sqlite3 CLI, foreign_keys=ON, .headers on, .mode column)\n'
    # sqlite3 는 연결마다 FK 가 꺼진 채 시작하므로 쿼리마다 먼저 켠다.
    printf 'PRAGMA foreign_keys = ON;\n.headers on\n.mode column\n%s\n' "$body" | sqlite3 -bail "$DB"
  } > "$RESULTS/$id.txt"
done

# FK 차단 확인. 없는 부모를 참조하는 입력이 실패해야 정상이므로 || true 로 받는다.
fk_run() {
  # $1: 설명, $2: SQL. 실패 메시지(stderr)까지 함께 기록한다.
  printf -- '-- %s\n%s\n' "$1" "$2"
  printf 'PRAGMA foreign_keys = ON;\n%s\n' "$2" | sqlite3 "$DB" 2>&1 || true
  printf '\n'
}
{
  printf -- '-- FK 차단 확인 (PRAGMA foreign_keys = ON 상태) -- [SQLite 전용]\n'
  printf -- '-- 아래 입력은 모두 실패해야 정상이다. 실패 메시지는 sqlite3 가 출력한 그대로다.\n\n'
  fk_run '[1] 존재하지 않는 member_id(999)로 예약 INSERT' \
    "INSERT INTO booking (member_id, lesson_id, booked_at, status) VALUES (999, 1, '2026-10-01 10:00', 'booked');"
  fk_run '[2] 존재하지 않는 lesson_id(999)로 예약 INSERT' \
    "INSERT INTO booking (member_id, lesson_id, booked_at, status) VALUES (1, 999, '2026-10-01 10:00', 'booked');"
  fk_run '[3] 예약이 있는 회원(id=1) 삭제 시도 (ON DELETE RESTRICT)' \
    "DELETE FROM member WHERE id = 1;"
  printf -- '-- [4] 실패한 입력이 아무 흔적도 남기지 않았는지 확인 -- [SQLite 전용] 출력이 없으면 FK 위반 행이 0건이다\n'
  printf 'PRAGMA foreign_key_check;\n'
  printf 'PRAGMA foreign_key_check;\n' | sqlite3 "$DB" 2>&1 || true
  printf -- '-- (끝)\n'
} > "$RESULTS/fk-check.txt"

count="$(ls "$RESULTS"/Q*.txt | wc -l | tr -d ' ')"
echo "완료: 쿼리 결과 ${count}개 + fk-check.txt 를 $RESULTS/ 에 저장했습니다."
