-- ============================================================
-- 핵심 쿼리 16개 (SQLite)
-- 실행 순서: 01_schema.sql -> 02_seed.sql -> 03_queries.sql (번호 순서대로)
--
-- 기준일: 2026-10-01 (date('now') 대신 리터럴을 써서 결과를 재현할 수 있게 한다)
-- 머리 주석 형식: -- Qnn [범주] 한 줄 설명  (scripts/run_all.sh 와 tests 가 이 형식으로 쿼리를 나눈다)
-- 데이터를 바꾸는 쿼리(Q14, Q15)와 인덱스(Q16)는 앞 쿼리 결과가 달라지지 않도록 맨 끝에 둔다.
-- SQLite 전용 문법은 해당 쿼리에 [SQLite 전용] 주석으로 표시한다.
-- ============================================================

-- ------------------------------------------------------------
-- 기본 조회 (WHERE / ORDER BY / LIMIT)
-- ------------------------------------------------------------

-- Q01 [기본조회] 요가 카테고리 수업을 시작 시각 순으로 조회한다
SELECT id, title, category, starts_at, capacity, price
FROM lesson
WHERE category = '요가'
ORDER BY starts_at;

-- Q02 [기본조회] 수강료가 높은 상위 5개 수업을 조회한다 (같은 가격이면 빠른 수업 먼저)
-- LIMIT 은 SQLite·MySQL·PostgreSQL 이 공통으로 지원하는 문법이다.
SELECT id, title, category, price
FROM lesson
ORDER BY price DESC, starts_at
LIMIT 5;

-- Q03 [기본조회] 2026년에 가입한 회원을 가입일 순으로 조회한다
SELECT id, name, email, joined_at
FROM member
WHERE joined_at >= '2026-01-01' AND joined_at < '2027-01-01'
ORDER BY joined_at;

-- Q04 [기본조회] 정원 15명 이상이면서 수강료 2만 원 이하인 부담 없는 수업을 조회한다
SELECT id, title, category, capacity, price
FROM lesson
WHERE capacity >= 15 AND price <= 20000
ORDER BY price, capacity DESC;

-- ------------------------------------------------------------
-- 조인 (INNER JOIN / LEFT JOIN)
-- ------------------------------------------------------------

-- Q05 [INNER JOIN] 예약 목록을 회원명·수업명·시작 시각·상태와 함께 조회한다 (booking, member, lesson 3테이블)
SELECT b.id AS booking_id, m.name AS member_name, l.title AS lesson_title, l.starts_at, b.status
FROM booking b
INNER JOIN member m ON m.id = b.member_id
INNER JOIN lesson l ON l.id = b.lesson_id
ORDER BY l.starts_at, b.id;

-- Q06 [INNER JOIN] 수업별 담당 트레이너와 그 전문 분야를 조회한다
SELECT l.id AS lesson_id, l.title, l.category, t.name AS trainer_name, t.specialty
FROM lesson l
INNER JOIN trainer t ON t.id = l.trainer_id
ORDER BY l.id;

-- Q07 [LEFT JOIN] 회원별 예약 수를 조회한다 (예약이 없는 회원도 0건으로 포함)
SELECT m.id AS member_id, m.name, COUNT(b.id) AS booking_count
FROM member m
LEFT JOIN booking b ON b.member_id = m.id
GROUP BY m.id, m.name
ORDER BY booking_count DESC, m.id;

-- Q08 [LEFT JOIN] 예약이 한 건도 없는 수업을 찾는다 (IS NULL 로 짝이 없는 행만 남김)
SELECT l.id AS lesson_id, l.title, l.starts_at
FROM lesson l
LEFT JOIN booking b ON b.lesson_id = l.id
WHERE b.id IS NULL
ORDER BY l.starts_at;

-- ------------------------------------------------------------
-- 집계 (COUNT / SUM / AVG + GROUP BY)
-- ------------------------------------------------------------

-- Q09 [집계] 취소를 제외한 예약 인원이 3명 이상인 수업을 인원 순으로 조회한다 (COUNT + GROUP BY + HAVING)
SELECT l.id AS lesson_id, l.title, l.capacity,
       COUNT(b.id) AS booked_count,
       ROUND(COUNT(b.id) * 100.0 / l.capacity, 1) AS fill_rate_pct
FROM lesson l
INNER JOIN booking b ON b.lesson_id = l.id
WHERE b.status <> 'cancelled'
GROUP BY l.id, l.title, l.capacity
HAVING COUNT(b.id) >= 3
ORDER BY booked_count DESC, l.id;

-- Q10 [집계] 트레이너별 매출을 구한다 (출석·예약 상태의 예약만 합산, SUM(price))
SELECT t.id AS trainer_id, t.name AS trainer_name, t.specialty,
       COUNT(b.id) AS paid_bookings,
       SUM(l.price) AS revenue
FROM trainer t
INNER JOIN lesson l ON l.trainer_id = t.id
INNER JOIN booking b ON b.lesson_id = l.id
WHERE b.status IN ('attended', 'booked')
GROUP BY t.id, t.name, t.specialty
ORDER BY revenue DESC, t.id;

-- Q11 [집계] 멤버십 이용 기간별 가입 회원 수와 회원이 내는 평균 월회비를 구한다 (COUNT + AVG)
SELECT p.months,
       COUNT(m.id) AS member_count,
       ROUND(AVG(p.monthly_fee), 0) AS avg_monthly_fee
FROM membership_plan p
INNER JOIN member m ON m.plan_id = p.id
GROUP BY p.months
ORDER BY p.months;

-- ------------------------------------------------------------
-- 서브쿼리
-- ------------------------------------------------------------

-- Q12 [서브쿼리] 전체 수업 평균 수강료보다 비싼 수업을 조회한다 (스칼라 서브쿼리)
SELECT id, title, category, price
FROM lesson
WHERE price > (SELECT AVG(price) FROM lesson)
ORDER BY price DESC, id;

-- Q13 [서브쿼리] 예약 기록이 한 건도 없는 회원을 찾는다 (NOT EXISTS)
SELECT m.id, m.name, m.email, m.joined_at
FROM member m
WHERE NOT EXISTS (SELECT 1 FROM booking b WHERE b.member_id = m.id)
ORDER BY m.id;

-- ------------------------------------------------------------
-- 데이터 수정·삭제 (앞 쿼리 결과를 바꾸지 않도록 맨 끝에 둔다)
-- ------------------------------------------------------------

-- Q14 [수정] 기준일(2026-10-01) 이전 수업에 booked 로 남은 예약을 no_show 로 바꾼다 (전후 SELECT 포함)
-- 변경 전: 이미 지난 수업인데 booked 상태인 예약
SELECT '변경 전' AS stage, b.id AS booking_id, m.name AS member_name, l.title AS lesson_title, l.starts_at, b.status
FROM booking b
INNER JOIN member m ON m.id = b.member_id
INNER JOIN lesson l ON l.id = b.lesson_id
WHERE b.status = 'booked' AND l.starts_at < '2026-10-01'
ORDER BY b.id;

UPDATE booking
SET status = 'no_show'
WHERE status = 'booked'
  AND lesson_id IN (SELECT id FROM lesson WHERE starts_at < '2026-10-01');

-- 변경 후: no_show 예약 전체 (원래 2건 + 방금 바꾼 3건)
SELECT '변경 후' AS stage, b.id AS booking_id, m.name AS member_name, l.title AS lesson_title, l.starts_at, b.status
FROM booking b
INNER JOIN member m ON m.id = b.member_id
INNER JOIN lesson l ON l.id = b.lesson_id
WHERE b.status = 'no_show'
ORDER BY b.id;

-- 변경 후 확인: 지난 수업에 booked 로 남은 예약은 0건이어야 한다
SELECT '변경 후 확인' AS stage, COUNT(*) AS stale_booked
FROM booking b
INNER JOIN lesson l ON l.id = b.lesson_id
WHERE b.status = 'booked' AND l.starts_at < '2026-10-01';

-- Q15 [삭제] cancelled 상태의 예약을 삭제한다 (전후 COUNT 포함)
-- 삭제 전
SELECT '삭제 전' AS stage, COUNT(*) AS total_bookings,
       SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_bookings
FROM booking;

DELETE FROM booking WHERE status = 'cancelled';

-- 삭제 후
SELECT '삭제 후' AS stage, COUNT(*) AS total_bookings,
       SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_bookings
FROM booking;

-- ------------------------------------------------------------
-- 인덱스
-- ------------------------------------------------------------

-- Q16 [인덱스] booking.lesson_id 에 인덱스를 만들고 실행 계획으로 사용 여부를 확인한다
-- 적용 이유: 수업별 예약을 lesson_id 로 찾는 조회(Q09 집계, Q08 JOIN)가 있는데, UNIQUE(member_id, lesson_id) 의 자동 인덱스는 member_id 가 앞이라 lesson_id 단독 검색에는 쓰이지 않는다.
-- 인덱스 생성 전 실행 계획
SELECT '인덱스 생성 전' AS stage;
EXPLAIN QUERY PLAN  -- [SQLite 전용] 실행 계획을 보여 주는 명령
SELECT * FROM booking WHERE lesson_id = 3;

CREATE INDEX idx_booking_lesson_id ON booking(lesson_id);

-- 인덱스 생성 후 실행 계획
SELECT '인덱스 생성 후' AS stage;
EXPLAIN QUERY PLAN  -- [SQLite 전용]
SELECT * FROM booking WHERE lesson_id = 3;
