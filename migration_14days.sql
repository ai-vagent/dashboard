-- ============================================================
-- 마이그레이션: 회차 기본 일정을 5 영업일(월~금) → 14 영업일로 변경
-- Supabase 대시보드 > SQL Editor에 복사해서 실행
-- ============================================================

-- 1) 영업일 더하기 헬퍼 함수
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

-- 2) 회차 자동 생성 함수를 14 영업일 기준으로 재정의
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

-- ============================================================
-- 3) 기존 회차들을 새 14일 기준으로 재생성
--    ⚠️ 모든 회차의 stage / progress / memo / ack 데이터가 초기화됩니다.
--    실제 진행 데이터가 있다면 아래 블록을 주석 처리하고 수동으로 일정만 조정하세요.
-- ============================================================
delete from episodes;
do $$
declare w record;
begin
  for w in select id from works loop
    perform generate_episodes_for_work(w.id);
  end loop;
end $$;
