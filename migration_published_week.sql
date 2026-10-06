-- ============================================================
-- 마이그레이션: 회차 '공개' 여부 추가
--   - episodes.published_week (text, null 허용)
--   - null이면 미공개, 'N월M주' 라벨이 들어가면 해당 주에 보고(공개)된 것
-- Supabase 대시보드 > SQL Editor에서 실행 (idempotent)
-- ============================================================
alter table episodes add column if not exists published_week text;
