-- ============================================================
-- 마이그레이션: 회차당 작업일 기본값 14 → 5 영업일
--
-- 대시보드 코드의 디폴트는 이미 5일로 변경됨.
-- 이 파일은 DB 컬럼 기본값도 맞춰두는 선택적 마이그레이션.
-- (앱이 작품 추가 시 ep_days를 항상 명시하므로 실행하지 않아도 동작에는 지장 없음)
--
-- 사용법: Supabase 대시보드 > SQL Editor에 전체 복사 → Run
-- ============================================================

alter table works alter column ep_days set default 5;

-- 변경 확인
select column_name, column_default
from information_schema.columns
where table_name = 'works' and column_name = 'ep_days';
