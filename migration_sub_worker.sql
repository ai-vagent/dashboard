-- ============================================================
-- 마이그레이션: works 테이블에 서브 작업자(sub_worker) 컬럼 추가
-- 실행: Supabase 대시보드 → SQL Editor → 아래 전체 실행
-- (대시보드의 서브 작업자 기능 배포 전에 먼저 실행해야 저장 오류가 없습니다)
-- ============================================================

alter table works
  add column if not exists sub_worker text references workers(id) on delete set null;  -- null = 서브 작업자 미정

create index if not exists works_sub_worker_idx on works (sub_worker);
