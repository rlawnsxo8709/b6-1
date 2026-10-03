-- ============================================================
-- 피트니스 수업 예약 DB — 스키마 (SQLite)
-- 실행 순서: 01_schema.sql -> 02_seed.sql -> 03_queries.sql
-- 관계: membership_plan 1:N member, member 1:N booking,
--       trainer 1:N lesson,        lesson 1:N booking
-- ============================================================

PRAGMA foreign_keys = ON;  -- [SQLite 전용] FK 강제는 연결마다 켜야 한다 (기본값 OFF)

-- 다시 실행해도 깨지지 않도록 자식 테이블부터 지운다.
DROP TABLE IF EXISTS booking;
DROP TABLE IF EXISTS lesson;
DROP TABLE IF EXISTS member;
DROP TABLE IF EXISTS trainer;
DROP TABLE IF EXISTS membership_plan;

-- 멤버십 상품: 회원이 가입하는 이용권
CREATE TABLE membership_plan (
  id          INTEGER PRIMARY KEY,                       -- [SQLite 전용] INTEGER PRIMARY KEY는 rowid 별칭(자동 증가 키)
  name        VARCHAR(30) NOT NULL UNIQUE,
  monthly_fee INTEGER NOT NULL CHECK (monthly_fee >= 0), -- 원 단위
  months      INTEGER NOT NULL CHECK (months > 0)        -- 이용 기간(개월)
);

-- 회원: 반드시 하나의 멤버십 상품에 속한다 (membership_plan 1:N member)
CREATE TABLE member (
  id        INTEGER PRIMARY KEY,
  name      VARCHAR(30)  NOT NULL,
  email     VARCHAR(100) NOT NULL UNIQUE,
  phone     VARCHAR(20),                                  -- 선택 입력이라 NULL 허용
  plan_id   INTEGER NOT NULL REFERENCES membership_plan(id) ON DELETE RESTRICT,
  joined_at DATE NOT NULL                                 -- 'YYYY-MM-DD' (ISO-8601 TEXT로 저장)
);

-- 트레이너
CREATE TABLE trainer (
  id        INTEGER PRIMARY KEY,
  name      VARCHAR(30) NOT NULL,
  specialty VARCHAR(30) NOT NULL,
  hired_at  DATE NOT NULL
);

-- 수업: 한 트레이너가 맡는 개별 회차 (trainer 1:N lesson)
CREATE TABLE lesson (
  id         INTEGER PRIMARY KEY,
  trainer_id INTEGER NOT NULL REFERENCES trainer(id) ON DELETE RESTRICT,
  title      VARCHAR(50) NOT NULL,
  category   VARCHAR(20) NOT NULL,
  starts_at  DATETIME NOT NULL,                           -- 'YYYY-MM-DD HH:MM' (ISO-8601 TEXT로 저장)
  capacity   INTEGER NOT NULL CHECK (capacity > 0),
  price      INTEGER NOT NULL CHECK (price >= 0)          -- 원 단위, 1회 수강료
);

-- 예약: 회원과 수업을 잇는 연결 테이블 (member 1:N booking, lesson 1:N booking)
CREATE TABLE booking (
  id        INTEGER PRIMARY KEY,
  member_id INTEGER NOT NULL REFERENCES member(id) ON DELETE RESTRICT,
  lesson_id INTEGER NOT NULL REFERENCES lesson(id) ON DELETE RESTRICT,
  booked_at DATETIME NOT NULL,
  status    VARCHAR(10) NOT NULL
            CHECK (status IN ('booked', 'attended', 'cancelled', 'no_show')),
  UNIQUE (member_id, lesson_id)                           -- 같은 회원이 같은 수업을 두 번 예약할 수 없다
);
