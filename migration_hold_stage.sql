-- ============================================================
-- 마이그레이션: 회차 '보류' 상태(stage 7) 추가
--   - 작품 드랍 / 작업자 퇴사 등으로 제작이 중단된 경우 사용
--   - 보류 회차부터 이후 모든 회차의 일정은 잠김(block) 처리
--   - episodes.stage에는 CHECK 제약이 없으므로 스키마 변경은 불필요
--   - 편의 뷰 3종만 갱신: 보류 이후(잠긴) 회차를 알림·지연 집계에서 제외
-- Supabase 대시보드 > SQL Editor에서 전체 실행 (idempotent)
-- ============================================================

-- 컨펌 필요: 영상초안(3) / 피드백(4) / 마무리(5) 단계에서 progress=100
create or replace view v_confirm_items as
  select
    e.id, e.work_id, w.title as work_title, w.worker,
    e.ep_num, e.stage, e.progress, e.start_date, e.end_date,
    case e.stage when 3 then '초안 확인' when 4 then '피드백 확인' else '최종 확인' end as confirm_label
  from episodes e
  join works w on w.id = e.work_id
  where e.stage in (3,4,5) and e.progress = 100
    and not exists (
      select 1 from episodes h
      where h.work_id = e.work_id and h.stage = 7 and h.ep_num <= e.ep_num
    );

-- 각색 필요: 미시작(0) 회차 중 직전 회차가 피드백(4) 이상 (보류 7 제외)
create or replace view v_adapt_items as
  select
    e.id, e.work_id, w.title as work_title, w.worker,
    e.ep_num, e.start_date, e.end_date
  from episodes e
  join works w on w.id = e.work_id
  where e.stage = 0
    and e.ep_num > 1
    and exists (
      select 1 from episodes p
      where p.work_id = e.work_id and p.ep_num = e.ep_num - 1
        and p.stage >= 4 and p.stage <> 7
    )
    and not exists (
      select 1 from episodes h
      where h.work_id = e.work_id and h.stage = 7 and h.ep_num <= e.ep_num
    );

-- 일정 지연: 원본 종료일 대비 현재 종료일이 늦어진 회차
create or replace view v_delayed_items as
  select
    e.id, e.work_id, w.title as work_title, w.worker,
    e.ep_num, e.original_end_date, e.end_date,
    (e.end_date - e.original_end_date) as delay_calendar_days
  from episodes e
  join works w on w.id = e.work_id
  where e.end_date > e.original_end_date
    and not exists (
      select 1 from episodes h
      where h.work_id = e.work_id and h.stage = 7 and h.ep_num <= e.ep_num
    );
