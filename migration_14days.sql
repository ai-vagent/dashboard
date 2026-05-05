-- ============================================================
-- 마이그레이션 (안전 버전): 회차 일정을 5 영업일 → 14 영업일 기준으로 변경
--
-- ✅ 보존:  stage / progress / memo / ack_kind / ack_label
-- 🔄 변경:  start_date / end_date / original_start_date / original_end_date
--
-- 사용법: Supabase 대시보드 > SQL Editor에 전체 복사 → Run
-- ============================================================

-- 1) 영업일(월~금) 더하기 헬퍼 함수
create or replace function add_business_days(d date, n int) returns date as $$
declare
  r date := d;
  i int := 0;
begin
  while i < n loop
    r := r + 1;
    if extract(dow from r) not in (0, 6) then
      i := i + 1;
    end if;
  end loop;
  return r;
end;
$$ language plpgsql immutable;

-- 2) 새 work 추가 시 사용될 트리거 함수를 14 영업일 기준으로 갱신
create or replace function generate_episodes_for_work(p_work_id int) returns void as $$
declare
  w           record;
  i           int;
  base_wk     int;
  cursor_d    date;
  start_d     date;
  end_d       date;
  ep_days int := 14;
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
    end_d   := add_business_days(start_d, ep_days - 1);
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

-- 3) 기존 회차들의 날짜 컬럼만 새 14 영업일 기준으로 재계산
--    (stage / progress / memo / ack는 update에서 제외 — 절대 건드리지 않음)
do $$
declare
  w        record;
  ep_rec   record;
  base_wk  int;
  cursor_d date;
  start_d  date;
  end_d    date;
  ep_days int := 14;
begin
  for w in select id, start_month from works order by id loop
    base_wk := case w.start_month
      when 5  then 0  when 6  then 4  when 7  then 9  when 8  then 13
      when 9  then 18 when 10 then 22 when 11 then 26 when 12 then 31
      else 0 end;
    cursor_d := date '2026-05-04' + (base_wk * 7);

    for ep_rec in select id from episodes where work_id = w.id order by ep_num loop
      start_d := cursor_d;
      end_d   := add_business_days(start_d, ep_days - 1);
      update episodes
        set start_date          = start_d,
            end_date            = end_d,
            original_start_date = start_d,
            original_end_date   = end_d
        where id = ep_rec.id;
      cursor_d := add_business_days(end_d, 1);
    end loop;
  end loop;
end $$;

-- 4) 변경 결과 확인용 쿼리 (실행 후 자동으로 결과 표시)
select
  w.title,
  e.ep_num as 회차,
  e.start_date as 시작,
  e.end_date as 종료,
  (e.end_date - e.start_date + 1) as 캘린더일수,
  e.stage,
  e.progress,
  case when e.memo <> '' then '✓' else '' end as 메모
from works w
join episodes e on e.work_id = w.id
order by w.id, e.ep_num
limit 30;
