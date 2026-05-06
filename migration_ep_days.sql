-- ============================================================
-- 마이그레이션: 작품별 회차 작업일 설정 (ep_days)
--
-- 기존 works 테이블에 ep_days 컬럼을 추가하고,
-- generate_episodes_for_work 함수가 w.ep_days를 사용하도록 수정.
--
-- 사용법: Supabase 대시보드 > SQL Editor에 전체 복사 → Run
-- ============================================================

-- 1) works 테이블에 ep_days 컬럼 추가 (기본값 14 영업일)
alter table works
  add column if not exists ep_days int not null default 14;

-- 2) generate_episodes_for_work 함수를 w.ep_days 사용하도록 교체
create or replace function generate_episodes_for_work(p_work_id int) returns void as $$
declare
  w           record;
  i           int;
  base_wk     int;
  cursor_d    date;
  start_d     date;
  end_d       date;
begin
  select * into w from works where id = p_work_id;
  if not found then return; end if;

  base_wk := case w.start_month
    when 5  then 0  when 6  then 4  when 7  then 9  when 8  then 13
    when 9  then 18 when 10 then 22 when 11 then 26 when 12 then 31
    else 0 end;

  cursor_d := date '2026-05-04' + (base_wk * 7);

  for i in 1..w.total_ep loop
    start_d := cursor_d;
    end_d   := add_business_days(start_d, w.ep_days - 1);  -- 작품별 영업일 사용
    insert into episodes (
      work_id, ep_num, start_date, end_date,
      original_start_date, original_end_date,
      stage, progress, memo
    )
    values (p_work_id, i, start_d, end_d, start_d, end_d, 0, 0, '')
    on conflict (work_id, ep_num) do nothing;
    cursor_d := add_business_days(end_d, 1);
  end loop;
end;
$$ language plpgsql;

-- 3) 변경 확인
select id, title, ep_days from works order by id;
