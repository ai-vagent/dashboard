-- ============================================================
-- 마이그레이션: works.title 에 UNIQUE 제약 추가
--
-- 목적: 같은 제목의 작품이 중복 생성되는 것을 DB 레벨에서 원천 차단.
--   (앱의 시드 자동 삽입이 일시적 조회 실패로 오작동하면
--    두비서·스캔들·천뮤생·엘그린·맞불결혼·장롱괴물 6개가 중복 생성되던 문제)
--   코드에도 방어 로직을 넣었지만, UNIQUE 제약은 코드가 어떤 이유로
--   오작동해도 중복 INSERT 자체를 실패시키는 최종 안전장치다.
--
-- 사용법: Supabase 대시보드 > SQL Editor에 전체 복사 → Run
-- 주의: 실행 전 동일 제목 작품이 이미 있으면 제약 추가가 실패한다.
--       아래 1) 중복 확인 쿼리로 먼저 점검할 것.
-- ============================================================

-- 1) 중복 제목 사전 점검 (결과가 0행이어야 제약 추가 가능)
select title, count(*) as cnt
from works
group by title
having count(*) > 1;

-- 2) UNIQUE 제약 추가 (이미 있으면 에러 없이 건너뜀)
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'works_title_unique'
  ) then
    alter table works add constraint works_title_unique unique (title);
  end if;
end $$;

-- 3) 적용 확인
select conname, contype
from pg_constraint
where conrelid = 'works'::regclass and conname = 'works_title_unique';
