# b6-1 수행 계획 — 피트니스 수업 예약 DB (SQLite)

> 작성일: 2026-10-04 / 대상: b6-1 「정보를 깔끔하게 정리하는 디지털 서랍장 만들기」 미션

## 1. 목표와 판단 기준

백엔드 프레임워크 없이 **"데이터 모델링 → 데이터 입력 → 요구사항을 SQL로 해결"** 한 흐름을 파일과 실행 결과로 남기는 것이 목적이다.
다음 세 가지를 스키마와 결과 파일에서 바로 짚을 수 있어야 한다.

1. 테이블을 왜 이렇게 나눴고, FK가 도메인에서 어떤 관계를 뜻하는가
2. 없는 값을 참조하는 입력이 실제로 막히는가 (`PRAGMA foreign_keys = ON`이 켜진 상태에서)
3. 같은 요구를 INNER JOIN·LEFT JOIN·집계·서브쿼리로 풀면 결과가 어떻게 달라지는가

## 2. 주제 선정 이유

주제는 **피트니스 수업 예약**이다.

- "회원이 수업을 예약한다"는 흐름이 곧 **다대다(회원 ↔ 수업)** 이고, 이를 `booking` 테이블 하나로 풀어내는 과정이 FK·1:N 관계를 가장 자연스럽게 보여 준다.
- 예약 상태(`booked`, `attended`, `cancelled`, `no_show`)가 있어 `CHECK` 제약, UPDATE(출석 처리), DELETE(취소 정리)가 억지 없이 나온다.
- 예약이 없는 회원·수업이 현실에서도 흔해서 LEFT JOIN과 `NOT EXISTS`가 의미 있는 결과를 낸다.
- 트레이너별 매출, 상품별 회원 수처럼 실무형 집계 질문이 바로 나온다.

## 3. 산출물 구조

```
answers/                     ← 이 폴더가 곧 b6-1 저장소의 루트
├── sql/
│   ├── 01_schema.sql        CREATE TABLE (PK·FK·UNIQUE·NOT NULL·CHECK)
│   ├── 02_seed.sql          샘플 데이터 INSERT (부모 → 자식 순서)
│   └── 03_queries.sql       핵심 쿼리 16개 (머리 주석 + 한 줄 설명)
├── scripts/run_all.sh       새 DB를 만들고 쿼리를 하나씩 실행해 results/ 에 저장
├── results/                 Q01.txt ~ Q16.txt, fk-check.txt (실제 실행 출력)
├── tests/                   표준 unittest (스키마·시드·쿼리·실행 스크립트 검증)
├── README.md                사용 가이드 + ERD + 쿼리 표 + 체크리스트 + 검증 결과
├── EXPLAIN.md               과제 목표 6문항 + 평가 문항 답변
└── PLAN.md                  이 문서
```

## 4. 테이블 5개와 1:N 관계 4개

| 테이블 | 역할 | 핵심 컬럼 |
|---|---|---|
| `membership_plan` | 멤버십 상품(1개월권, 3개월권 …) | `name` UNIQUE, `monthly_fee`, `months` |
| `member` | 회원 | `name` NOT NULL, `email` UNIQUE, `plan_id` FK, `joined_at` |
| `trainer` | 트레이너 | `name`, `specialty`, `hired_at` |
| `lesson` | 개설된 수업 1회차 | `trainer_id` FK, `title`, `category`, `starts_at`, `capacity`, `price` |
| `booking` | 회원의 수업 예약 | `member_id` FK, `lesson_id` FK, `booked_at`, `status` CHECK |

```
membership_plan 1 ──< N member      한 상품에 여러 회원이 가입한다
member          1 ──< N booking     한 회원이 여러 수업을 예약한다
trainer         1 ──< N lesson      한 트레이너가 여러 수업을 맡는다
lesson          1 ──< N booking     한 수업에 여러 회원이 예약한다
```

`booking`은 `member`와 `lesson` 사이의 **연결 테이블**이다. 회원과 수업은 서로 다대다지만, 그 사이에 예약이라는 사실(언제 예약했고 지금 상태가 무엇인지)이 있어서 독립된 테이블로 둔다.

## 5. 타입 선택 근거

SQLite는 컬럼 선언 타입을 **친화성(type affinity)** 으로만 해석한다. 선언한 이름에서 다섯 가지 친화성(INTEGER, TEXT, REAL, NUMERIC, BLOB) 중 하나가 정해지고, 값 자체는 어떤 타입이든 들어갈 수 있다. 그래서 타입 이름은 **"사람과 다른 DB로 옮길 때를 위한 의도 표시"** 로 쓰고, 정말 지켜야 할 규칙은 `CHECK`로 따로 건다.

| 컬럼 종류 | 선언 | SQLite 친화성 | 이유 |
|---|---|---|---|
| PK, FK, 금액, 정원, 개월 수 | `INTEGER` | INTEGER | 원 단위 금액은 소수점이 없어 부동소수 오차를 피한다. `INTEGER PRIMARY KEY`는 rowid 별칭이라 자동 증가 키가 된다 |
| 이름, 이메일, 전화, 제목 | `VARCHAR(n)` | TEXT | 길이 상한은 의도 표시일 뿐 SQLite가 강제하지 않는다. 다른 DB로 옮길 때 그대로 쓸 수 있다 |
| 가입일, 입사일 | `DATE` | NUMERIC | 값은 `'2026-03-14'` 형태의 ISO-8601 **TEXT**로 저장한다 |
| 수업 시작·예약 시각 | `DATETIME` | NUMERIC | 값은 `'2026-10-02 09:00'` 형태의 ISO-8601 **TEXT**로 저장한다 |
| 예약 상태 | `VARCHAR(10)` + `CHECK IN (...)` | TEXT | 허용 값 4개를 DB가 직접 막는다 |

**날짜를 ISO-8601 TEXT로 저장하는 이유**

- SQLite에는 날짜 전용 저장 타입이 없다. TEXT·REAL·INTEGER 세 가지 방식 중 TEXT가 가장 읽기 쉽다.
- `YYYY-MM-DD HH:MM` 형식은 **문자열 비교 순서와 시간 순서가 같다.** 그래서 `ORDER BY starts_at`, `starts_at < '2026-10-01'`, `BETWEEN`이 별도 변환 없이 정확히 동작한다.
- 결과 파일을 눈으로 읽을 수 있고, 다른 DB(DATE/TIMESTAMP)로 옮길 때도 형식 그대로 들어간다.

## 6. 제약 목록

| 종류 | 위치 | 효과 |
|---|---|---|
| PK | 5개 테이블의 `id` | 행을 하나로 특정한다 |
| FK | `member.plan_id`, `lesson.trainer_id`, `booking.member_id`, `booking.lesson_id` | 없는 부모를 참조하는 입력을 막는다 |
| `ON DELETE RESTRICT` | FK 4개 전부 | 자식이 있는 부모를 지우면 오류. 예약이 고아로 남지 않는다 |
| UNIQUE | `membership_plan.name`, `member.email` | 같은 상품명·이메일 중복 금지 |
| UNIQUE (복합) | `booking(member_id, lesson_id)` | 같은 회원이 같은 수업을 두 번 예약할 수 없다 |
| NOT NULL | 전화번호를 뺀 거의 모든 컬럼 | 필수 값 누락 금지 |
| CHECK | `monthly_fee >= 0`, `months > 0`, `capacity > 0`, `price >= 0`, `status IN (...)` | 말이 안 되는 값 금지 |

`ON DELETE`를 `CASCADE`가 아니라 `RESTRICT`로 둔 이유: 회원을 지울 때 예약 이력까지 조용히 사라지면 매출 집계가 틀어진다. 지우려면 자식 행을 먼저 정리하도록 **오류로 알리는 쪽**을 택했다.

## 7. 기준일 리터럴 정책

- 쿼리와 시드 어디에서도 `date('now')`를 쓰지 않는다. 실행하는 날마다 결과가 달라지기 때문이다.
- 기준일은 **2026-10-01**로 고정하고, 쿼리에 `'2026-10-01'` 리터럴로 쓴다. (예: "기준일 이전 수업에 남은 `booked` 예약")
- 이렇게 하면 `results/` 안의 출력이 언제 실행해도 같고, 테스트가 결과를 단정할 수 있다.

## 8. 실행·검증 방식

1. `bash scripts/run_all.sh` — `fitness.db`를 지우고 새로 만든 뒤 스키마 → 시드 → 쿼리 순으로 실행한다. 쿼리마다 `PRAGMA foreign_keys = ON;`을 먼저 실행한다. `sqlite3` 기본값은 FK가 꺼져 있다.
2. `python3 -m unittest discover -s tests -t . -v` — Python 표준 `sqlite3`로 메모리 DB를 만들어 요구사항을 자동 검증한다. 테스트를 먼저 작성하고 실패를 확인한 뒤 SQL을 쓴다.
3. 결과 텍스트는 실제 실행 출력만 담는다. 생성된 `.db` 파일은 커밋하지 않는다.

## 9. 범위 밖

- 뷰·프로시저·트리거: 미션 제약 사항에 따라 쓰지 않는다.
- 보너스 과제(JOIN과 서브쿼리 비교, 정합성 깨뜨리기 기록, 미니 리포트): 하지 않는다.
- 백엔드 프레임워크, 외부 라이브러리: 쓰지 않는다. (`sqlite3` CLI, Bash, Python 표준 라이브러리)
