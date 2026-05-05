-- ============================================================
-- 애니메이션 제작 대시보드 — Supabase 초기 설정
-- Supabase 대시보드 > SQL Editor에서 전체 실행 (idempotent)
-- ============================================================

-- 0) 기존 객체 정리 (재실행 가능하도록)
--    테이블을 cascade로 먼저 떨어뜨리면 위에 달린 트리거 / FK / 뷰 / 시퀀스가 함께 정리됨
drop view  if exists v_confirm_items;
drop view  if exists v_adapt_items;
drop view  if exists v_delayed_items;
drop table if exists episodes cascade;
drop table if exists works    cascade;
drop table if exists workers  cascade;
drop function if exists generate_episodes_for_work(int) cascade;
drop function if exists work_default_episodes()         cascade;
drop function if exists set_updated_at()                cascade;

-- ============================================================
-- 1) workers 테이블 (작업자 / 감독)
-- ============================================================
create table workers (
  id         text primary key,           -- 'LCE', 'BJI', 'WKA' …
  name       text not null,
  color      text not null default '#888',
  is_sup     boolean not null default false,
  subrole    text not null default '',
  sort_order int  not null default 100,
  created_at timestamptz default now()
);

-- 작업자 정렬: 감독(is_sup=true) 먼저, 같은 그룹 안에서는 sort_order 오름차순
create index workers_sort_idx on workers (is_sup desc, sort_order, name);

-- ============================================================
-- 2) works 테이블 (작품)
-- ============================================================
create table works (
  id          serial primary key,
  title       text  not null,
  worker      text  references workers(id) on delete set null,  -- null = 담당자 미정
  start_month int   not null,
  total_ep    int   not null default 12,
  pre_phase   int   not null default 0,                          -- 0:작품선정 1:아트스타일 2:주요인물 3:연재중
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

create index works_pre_phase_idx on works (pre_phase);
create index works_worker_idx    on works (worker);

-- ============================================================
-- 3) episodes 테이블 (회차)
-- ============================================================
create table episodes (
  id                    serial primary key,
  work_id               int  not null references works(id) on delete cascade,
  ep_num                int  not null,
  start_date            date not null,
  end_date              date not null,
  original_start_date   date not null,                  -- 일정 지연 측정 기준
  original_end_date     date not null,
  stage                 int  not null default 0,        -- 0:미시작 1:각색완료 2:이미지추출 3:영상초안 4:피드백 5:마무리 6:완료
  progress              int  not null default 0,
  memo                  text not null default '',
  ack_kind              text,                           -- 'confirm' | 'adapt' | null
  ack_label             text,                           -- '영상초안작업 컨펌 완료' 등
  updated_at            timestamptz default now(),
  unique (work_id, ep_num)
);

create index episodes_work_idx     on episodes (work_id, ep_num);
create index episodes_stage_idx    on episodes (stage);
create index episodes_dates_idx    on episodes (start_date, end_date);

-- ============================================================
-- 4) RLS (팀 내부 전용 — anon 키로 풀 접근 허용)
--   외부 공개가 필요해지면 정책을 좁힐 것
-- ============================================================
alter table workers  enable row level security;
alter table works    enable row level security;
alter table episodes enable row level security;

create policy "allow_all_workers"  on workers  for all using (true) with check (true);
create policy "allow_all_works"    on works    for all using (true) with check (true);
create policy "allow_all_episodes" on episodes for all using (true) with check (true);

-- ============================================================
-- 5) Realtime (대시보드 동시 편집 동기화)
-- ============================================================
alter publication supabase_realtime add table workers;
alter publication supabase_realtime add table works;
alter publication supabase_realtime add table episodes;

-- ============================================================
-- 6) 회차 자동 생성 함수 + 트리거
--   - WEEK_ORIGIN = 2026-05-04 (월요일)
--   - 회차 i (1-indexed) = WEEK_ORIGIN + (base_wk + i - 1) * 7일 (월~금)
--   - base_wk: start_month별 첫 주 인덱스 (대시보드 JS와 일치)
-- ============================================================
create or replace function generate_episodes_for_work(p_work_id int) returns void as $$
declare
  w        record;
  i        int;
  base_wk  int;
  mon      date;
  fri      date;
begin
  select * into w from works where id = p_work_id;
  if not found then return; end if;

  base_wk := case w.start_month
    when 5  then 0  when 6  then 4  when 7  then 9  when 8  then 13
    when 9  then 18 when 10 then 22 when 11 then 26 when 12 then 31
    else 0 end;

  for i in 1..w.total_ep loop
    mon := date '2026-05-04' + ((base_wk + i - 1) * 7);
    fri := mon + 4;
    insert into episodes (
      work_id, ep_num, start_date, end_date,
      original_start_date, original_end_date,
      stage, progress, memo
    )
    values (p_work_id, i, mon, fri, mon, fri, 0, 0, '')
    on conflict (work_id, ep_num) do nothing;
  end loop;
end;
$$ language plpgsql;

-- 새 work 추가 시 자동으로 회차 생성
create or replace function work_default_episodes() returns trigger as $$
begin
  perform generate_episodes_for_work(new.id);
  return new;
end;
$$ language plpgsql;

create trigger trg_works_after_insert
  after insert on works
  for each row execute function work_default_episodes();

-- ============================================================
-- 7) updated_at 자동 갱신
-- ============================================================
create or replace function set_updated_at() returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_works_updated_at
  before update on works
  for each row execute function set_updated_at();

create trigger trg_episodes_updated_at
  before update on episodes
  for each row execute function set_updated_at();

-- ============================================================
-- 8) 시드 데이터 — 작업자
-- ============================================================
insert into workers (id, name, color, is_sup, subrole, sort_order) values
  ('LCE', '이채은',   '#ffd166', true,  '각색및총괄', 1),
  ('BJI', '배종일',   '#4ecdc4', true,  '영상총괄',   2),
  ('KYE', '김여은',   '#888',    false, '',           10),
  ('JJY', '정지윤',   '#888',    false, '',           11),
  ('CHS', '추해수',   '#888',    false, '',           12),
  ('WKA', '작업자 A', '#888',    false, '',           20),
  ('WKB', '작업자 B', '#888',    false, '',           21),
  ('WKC', '작업자 C', '#888',    false, '',           22);

-- ============================================================
-- 9) 시드 데이터 — 작품
--    트리거가 자동으로 회차를 생성합니다 (월~금 기본 5일 일정)
-- ============================================================
insert into works (id, title, worker, start_month, total_ep, pre_phase) values
  (1, '두비서',   'KYE', 5, 12, 0),
  (2, '스캔들',   'KYE', 6, 12, 0),
  (3, '천뮤생',   'JJY', 5, 12, 0),
  (4, '엘그린',   'JJY', 7, 12, 0),
  (5, '맞불결혼', 'LCE', 6, 12, 0),
  (6, '장롱괴물', 'BJI', 5, 12, 0);

-- serial 시퀀스를 seed 데이터 이후 값으로 조정
select setval('works_id_seq', 6);

-- ============================================================
-- 10) 편의 뷰 (선택) — 컨펌 / 각색 / 지연 항목
-- ============================================================

-- 컨펌 필요: 영상초안(3) / 피드백(4) / 마무리(5) 단계에서 progress=100
create or replace view v_confirm_items as
  select
    e.id, e.work_id, w.title as work_title, w.worker,
    e.ep_num, e.stage, e.progress, e.start_date, e.end_date,
    case e.stage when 3 then '초안 확인' when 4 then '피드백 확인' else '최종 확인' end as confirm_label
  from episodes e
  join works w on w.id = e.work_id
  where e.stage in (3,4,5) and e.progress = 100;

-- 각색 필요: 미시작(0) 회차 중 직전 회차가 피드백(4) 이상
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
      where p.work_id = e.work_id and p.ep_num = e.ep_num - 1 and p.stage >= 4
    );

-- 일정 지연: 원본 종료일 대비 현재 종료일이 늦어진 회차
create or replace view v_delayed_items as
  select
    e.id, e.work_id, w.title as work_title, w.worker,
    e.ep_num, e.original_end_date, e.end_date,
    (e.end_date - e.original_end_date) as delay_calendar_days
  from episodes e
  join works w on w.id = e.work_id
  where e.end_date > e.original_end_date;
