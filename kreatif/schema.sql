-- ============================================================
-- uzbionik Kreatif Performans Merkezi · Supabase Şeması + RLS
-- Supabase Dashboard → SQL Editor → bu dosyanın tamamını yapıştır → Run
-- ============================================================

-- ---------- PROFİLLER ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  name       text not null,
  initial    text,                          -- C / İ / E / M (kreatif ekip için)
  role       text not null default 'creative',  -- admin | partner | creative
  created_at timestamptz default now()
);

-- ---------- KREATİFLER ----------
create table if not exists public.creatives (
  id               uuid primary key default gen_random_uuid(),
  code             text unique not null,    -- UZB_C_CF012_VIDEO_HK023_VAR_V01_20260813
  owner_initial    text not null,           -- C / İ / E / M
  family           text,                    -- CF012
  format           text default 'video',    -- video | gorsel | carousel
  hook_code        text,
  hook_text        text,
  tur              text default 'YENI',     -- YENI | VAR | ITER
  parent_code      text,
  changed_element  text,                    -- tek değişken
  attribution      text default 'belirsiz', -- dogrulanmis | belirsiz
  attribution_note text,
  status           text not null default 'yeni',
  status_reason    text,
  thumb_url        text,
  first_week       date,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

-- ---------- HAFTALIK SONUÇLAR (finansal OLMAYAN — herkes görür) ----------
create table if not exists public.weekly_results (
  id             uuid primary key default gen_random_uuid(),
  creative_code  text not null references public.creatives(code) on delete cascade,
  week           date not null,             -- haftanın pazartesi tarihi
  sales          integer default 0,
  impressions    bigint,
  video_3s       bigint,
  thruplay       bigint,
  link_clicks    bigint,
  hook_rate      numeric,                   -- video_3s / impressions
  hold_rate      numeric,                   -- thruplay / video_3s
  ctr            numeric,                   -- link_clicks / impressions
  status_at_week text,
  unique (creative_code, week)
);

-- ---------- HAFTALIK FİNANSALLAR (SADECE admin + partner) ----------
create table if not exists public.weekly_financials (
  id            uuid primary key default gen_random_uuid(),
  creative_code text not null references public.creatives(code) on delete cascade,
  week          date not null,
  spend         numeric default 0,
  revenue       numeric default 0,
  roas          numeric,
  cpr           numeric,
  gpt           numeric,                    -- CPR x (ROAS - 1)
  rel_gpt       numeric,                    -- gpt / harcama-ağırlıklı hesap ort. gpt
  unique (creative_code, week)
);

-- ---------- HOOK BANKASI ----------
create table if not exists public.hooks (
  id            uuid primary key default gen_random_uuid(),
  code          text unique not null,       -- HK023
  text          text not null,
  owner_initial text,
  status        text not null default 'testte', -- tutan | negatif | yeniden_test | testte
  note          text,
  first_week    date,
  updated_at    timestamptz default now()
);

-- ---------- HAFTALAR ----------
create table if not exists public.weeks (
  week       date primary key,
  note       text,
  updated_at timestamptz default now()
);

create index if not exists wr_week_idx on public.weekly_results(week);
create index if not exists wf_week_idx on public.weekly_financials(week);

-- ============================================================
-- RLS
-- ============================================================
alter table public.profiles          enable row level security;
alter table public.creatives         enable row level security;
alter table public.weekly_results    enable row level security;
alter table public.weekly_financials enable row level security;
alter table public.hooks             enable row level security;
alter table public.weeks             enable row level security;

-- Yardımcı fonksiyonlar (security definer => RLS döngüsüne girmez)
create or replace function public.my_role()
returns text language sql security definer stable
set search_path = public
as $$ select role from public.profiles where id = auth.uid() $$;

create or replace function public.is_admin()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() = 'admin', false) $$;

create or replace function public.can_finance()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() in ('admin','partner'), false) $$;

-- profiles: herkes kendi satırını görür/oluşturur; admin hepsini görür ve düzenler
create policy "profiles_select" on public.profiles for select
  using (id = auth.uid() or public.is_admin());
create policy "profiles_insert" on public.profiles for insert
  with check (id = auth.uid());
create policy "profiles_update_admin" on public.profiles for update
  using (public.is_admin());

-- Not: role sütununu kullanıcı kendisi değiştiremesin diye insert'te role kontrolü
-- yapılmıyor çünkü default 'creative'. Yükseltme sadece SQL veya admin ile yapılır.

-- Herkese açık (giriş yapmış) tablolar: creatives, weekly_results, hooks, weeks
create policy "creatives_select" on public.creatives for select using (auth.uid() is not null);
create policy "creatives_write"  on public.creatives for all
  using (public.is_admin()) with check (public.is_admin());

create policy "results_select" on public.weekly_results for select using (auth.uid() is not null);
create policy "results_write"  on public.weekly_results for all
  using (public.is_admin()) with check (public.is_admin());

create policy "hooks_select" on public.hooks for select using (auth.uid() is not null);
create policy "hooks_write"  on public.hooks for all
  using (public.is_admin()) with check (public.is_admin());

create policy "weeks_select" on public.weeks for select using (auth.uid() is not null);
create policy "weeks_write"  on public.weeks for all
  using (public.is_admin()) with check (public.is_admin());

-- FİNANSALLAR: sadece admin + partner okur, sadece admin yazar
create policy "fin_select" on public.weekly_financials for select using (public.can_finance());
create policy "fin_write"  on public.weekly_financials for all
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- KURULUM SONRASI (bir kez, kendi hesabını admin yap):
--   update public.profiles set role = 'admin'
--   where id = (select id from auth.users where email = 'satin.yasin1999@gmail.com');
--
-- Ortak için:
--   update public.profiles set role = 'partner'
--   where id = (select id from auth.users where email = 'ORTAK_EMAIL');
-- ============================================================

-- ============================================================
-- EKİP ÜYELERİ (v1.1 eklentisi — yönetici düzenler, herkes okur)
-- ============================================================
create table if not exists public.team_members (
  initial text primary key,
  name    text not null,
  color   text default '#FFC53D',
  sort    integer default 0
);
alter table public.team_members enable row level security;
create policy "tm_select" on public.team_members for select using (auth.uid() is not null);
create policy "tm_write"  on public.team_members for all
  using (public.is_admin()) with check (public.is_admin());
insert into public.team_members (initial, name, color, sort) values
  ('C','Çağdaş','#FFC53D',1), ('İ','İnka','#2F5DFF',2),
  ('E','Erdem','#A855F7',3), ('M','Mustafa','#22C55E',4)
on conflict (initial) do nothing;

-- v1.2: hook formatı (görsel/video filtresi için)
alter table public.hooks add column if not exists format text;

-- ============================================================
-- v1.3: Facebook linki + Üretim Akışı + Varyasyon/İterasyon Havuzu
-- ============================================================
alter table public.creatives add column if not exists link text;

-- Üretim akışı kartları (HERKES yazabilir — ortak çalışma alanı)
create table if not exists public.pipeline_cards (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  note          text,
  stage         text not null default 'fikirler',
  format        text,                 -- video | gorsel
  owner_initial text,
  created_by    uuid references auth.users on delete set null,
  created_name  text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

-- Varyasyon / iterasyon fikir havuzu (HERKES yazabilir)
create table if not exists public.idea_pool (
  id            uuid primary key default gen_random_uuid(),
  parent_code   text not null,        -- hangi video/görsel için
  tur           text not null default 'VAR',  -- VAR | ITER
  hooks         jsonb default '[]',   -- 1-5 yeni hook
  note          text,
  created_by    uuid references auth.users on delete set null,
  created_name  text,
  created_at    timestamptz default now(),
  updated_at    timestamptz default now()
);

alter table public.pipeline_cards enable row level security;
alter table public.idea_pool      enable row level security;

create policy "pc_select" on public.pipeline_cards for select using (auth.uid() is not null);
create policy "pc_insert" on public.pipeline_cards for insert with check (auth.uid() = created_by);
create policy "pc_update" on public.pipeline_cards for update using (auth.uid() is not null);
create policy "pc_delete" on public.pipeline_cards for delete
  using (public.is_admin() or auth.uid() = created_by);

create policy "ip_select" on public.idea_pool for select using (auth.uid() is not null);
create policy "ip_insert" on public.idea_pool for insert with check (auth.uid() = created_by);
create policy "ip_update" on public.idea_pool for update
  using (public.is_admin() or auth.uid() = created_by);
create policy "ip_delete" on public.idea_pool for delete
  using (public.is_admin() or auth.uid() = created_by);

-- v1.4: havuz kayıtlarında "yapıldı" işareti
alter table public.idea_pool add column if not exists done      boolean default false;
alter table public.idea_pool add column if not exists done_name text;
alter table public.idea_pool add column if not exists done_at   timestamptz;

-- v1.5: ortak sahip (ör. 'uz video 502-İ VE K' -> İ + M)
alter table public.creatives add column if not exists co_owner text;

-- ============================================================
-- v1.6: LİNK KÜTÜPHANESİ (WhatsApp + elle) — herkes ekler, herkes görür
-- ============================================================
create table if not exists public.links (
  id           uuid primary key default gen_random_uuid(),
  url          text not null,
  url_key      text unique,              -- tekrar kontrolu icin normalize link
  description  text,
  category     text default 'diger',     -- rakip | ilham | trend | bizim | rakip_lp | arac | diger
  platform     text,
  status       text default 'yeni',      -- yeni | incelendi | kullanildi | arsiv
  shared_by    text,
  shared_at    timestamptz,
  source       text default 'manuel',    -- manuel | whatsapp
  created_by   uuid references auth.users on delete set null,
  created_name text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);
alter table public.links enable row level security;
create policy "ln_select" on public.links for select using (auth.uid() is not null);
create policy "ln_insert" on public.links for insert with check (auth.uid() = created_by);
create policy "ln_update" on public.links for update using (auth.uid() is not null);
create policy "ln_delete" on public.links for delete using (public.is_admin() or auth.uid() = created_by);

-- v1.6b: WhatsApp aktarma kaydi — "sadece yeniler" siniri linklerden bagimsiz tutulur
create table if not exists public.link_imports (
  id              uuid primary key default gen_random_uuid(),
  last_message_at timestamptz not null,   -- aktarilan sohbet dosyasindaki en yeni mesaj
  link_count      integer default 0,
  imported_by     uuid references auth.users on delete set null,
  imported_name   text,
  created_at      timestamptz default now()
);
alter table public.link_imports enable row level security;
create policy "li_select" on public.link_imports for select using (auth.uid() is not null);
create policy "li_insert" on public.link_imports for insert with check (auth.uid() = imported_by);

-- ============================================================
-- v1.7: KREATİF EKİP GÜNLÜĞÜ (Günüm) + gizli puan + talepler
-- Kişi anahtarı = profiles.initial (C / İ / E / M / R)
-- ============================================================
create or replace function public.my_initial()
returns text language sql security definer stable
set search_path = public
as $$ select initial from public.profiles where id = auth.uid() $$;

create or replace function public.is_kre_admin()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() in ('admin','partner'), false) $$;

create table if not exists public.kre_daily (
  id         uuid primary key default gen_random_uuid(),
  initial    text not null,
  day        date not null,
  in_time    text, out_time text,
  leave_min  integer, ot_min integer,
  new_video  integer, new_image integer, var_video integer, var_image integer,
  note       text, wish text,
  updated_at timestamptz default now(),
  unique (initial, day)
);
create table if not exists public.kre_scores (
  id         uuid primary key default gen_random_uuid(),
  day        date not null,
  rater      text not null,
  ratee      text not null,
  score      integer check (score is null or (score between 0 and 10)),
  comment    text,
  updated_at timestamptz default now(),
  unique (day, rater, ratee)
);
create table if not exists public.kre_requests (
  id         uuid primary key default gen_random_uuid(),
  day        date not null default current_date,
  kind       text not null default 'talep',   -- talep | alisveris
  text       text not null,
  amount     numeric,
  by_initial text, by_name text,
  done       boolean default false,
  done_note  text,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz default now()
);
alter table public.kre_daily    enable row level security;
alter table public.kre_scores   enable row level security;
alter table public.kre_requests enable row level security;

-- günlük: kreatif ekip + yönetici/ortak okur; herkes sadece kendi harfini yazar
create policy "kd_select" on public.kre_daily for select using (auth.uid() is not null and public.my_role() <> 'ops');
create policy "kd_insert" on public.kre_daily for insert with check (public.is_kre_admin() or initial = public.my_initial());
create policy "kd_update" on public.kre_daily for update using (public.is_kre_admin() or initial = public.my_initial());
create policy "kd_delete" on public.kre_daily for delete using (public.is_kre_admin());
-- puan: veren kendi verdiklerini görür, alan asla görmez, yönetici/ortak hepsini görür
create policy "ks_select" on public.kre_scores for select using (public.is_kre_admin() or rater = public.my_initial());
create policy "ks_insert" on public.kre_scores for insert with check (public.is_kre_admin() or rater = public.my_initial());
create policy "ks_update" on public.kre_scores for update using (public.is_kre_admin() or rater = public.my_initial());
create policy "ks_delete" on public.kre_scores for delete using (public.is_kre_admin());
-- talepler: herkes ekler ve görür, yönetici/ortak kapatır
create policy "kr_select" on public.kre_requests for select using (auth.uid() is not null and public.my_role() <> 'ops');
create policy "kr_insert" on public.kre_requests for insert with check (auth.uid() = created_by);
create policy "kr_update" on public.kre_requests for update using (public.is_kre_admin() or auth.uid() = created_by);
create policy "kr_delete" on public.kre_requests for delete using (public.is_kre_admin() or auth.uid() = created_by);

-- ============================================================
-- v1.8: İ = İmkan düzeltmesi, hesap-harf bağı, talep sorumlusu
-- ============================================================
update public.team_members set name = 'İmkan' where initial = 'İ' and name = 'İnka';
-- İmkan'ın hesabına harfini yaz (e-posta biliniyor)
update public.profiles set initial = 'İ'
  where id = (select id from auth.users where email = 'imkan.kilicay33@gmail.com');

create table if not exists public.kre_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz default now()
);
alter table public.kre_settings enable row level security;
create policy "kset_select" on public.kre_settings for select using (auth.uid() is not null and public.my_role() <> 'ops');
create policy "kset_write"  on public.kre_settings for all using (public.is_kre_admin()) with check (public.is_kre_admin());
insert into public.kre_settings (key, value) values ('roles', '{"talep":"İ"}') on conflict (key) do nothing;

-- talepler: yalnızca yönetici/ortak, talep sorumlusu ve kaydı ekleyen görür
drop policy if exists "kr_select" on public.kre_requests;
create policy "kr_select" on public.kre_requests for select using (
  public.is_kre_admin() or by_initial = public.my_initial()
  or public.my_initial() = (select value->>'talep' from public.kre_settings where key = 'roles')
);

-- v1.9: taleplerde onay tiki (yönetici/ortak onaylar)
alter table public.kre_requests add column if not exists approved    boolean default false;
alter table public.kre_requests add column if not exists approved_by text;
alter table public.kre_requests add column if not exists approved_at timestamptz;

-- ============================================================
-- v1.8 GÜN KİLİDİ (operasyon + kreatif, tek seferde çalıştır)
-- Ekip üyeleri günlük kaydı, puanları, kontrol tiklerini ve kargo
-- toplamlarını YALNIZCA o gün (Türkiye saati, 23:59'a kadar) girip
-- değiştirebilir. Ertesi gün kayıt kilitlenir.
-- Yönetici ve ortaklar (admin/partner) her günü düzeltebilir.
-- ============================================================

create or replace function public.tr_today()
returns date language sql stable
as $$ select (now() at time zone 'Europe/Istanbul')::date $$;

-- ---------- OPERASYON · günlük ----------
drop policy if exists "od_insert" on public.ops_daily;
drop policy if exists "od_update" on public.ops_daily;
create policy "od_insert" on public.ops_daily for insert
  with check (public.is_ops_admin() or (member_id = public.my_member() and day = public.tr_today()));
create policy "od_update" on public.ops_daily for update
  using      (public.is_ops_admin() or (member_id = public.my_member() and day = public.tr_today()))
  with check (public.is_ops_admin() or (member_id = public.my_member() and day = public.tr_today()));

-- ---------- OPERASYON · puan ----------
drop policy if exists "os_insert" on public.ops_scores;
drop policy if exists "os_update" on public.ops_scores;
create policy "os_insert" on public.ops_scores for insert
  with check (public.is_ops_admin() or (rater_id = public.my_member() and day = public.tr_today()));
create policy "os_update" on public.ops_scores for update
  using      (public.is_ops_admin() or (rater_id = public.my_member() and day = public.tr_today()))
  with check (public.is_ops_admin() or (rater_id = public.my_member() and day = public.tr_today()));

-- ---------- OPERASYON · kontrol / denetim tikleri ----------
drop policy if exists "oc_insert" on public.ops_checks;
drop policy if exists "oc_update" on public.ops_checks;
drop policy if exists "oc_delete" on public.ops_checks;
create policy "oc_insert" on public.ops_checks for insert
  with check (public.is_ops_admin() or (done_by = public.my_member() and day = public.tr_today()));
create policy "oc_update" on public.ops_checks for update
  using      (public.is_ops_admin() or (done_by = public.my_member() and day = public.tr_today()))
  with check (public.is_ops_admin() or (done_by = public.my_member() and day = public.tr_today()));
create policy "oc_delete" on public.ops_checks for delete
  using (public.is_ops_admin() or (done_by = public.my_member() and day = public.tr_today()));

-- ---------- OPERASYON · kargo & mesaj toplamları ----------
drop policy if exists "otd_all"    on public.ops_team_daily;
drop policy if exists "otd_select" on public.ops_team_daily;
drop policy if exists "otd_insert" on public.ops_team_daily;
drop policy if exists "otd_update" on public.ops_team_daily;
drop policy if exists "otd_delete" on public.ops_team_daily;
create policy "otd_select" on public.ops_team_daily for select using (public.is_ops());
create policy "otd_insert" on public.ops_team_daily for insert
  with check (public.is_ops_admin() or (public.is_ops() and day = public.tr_today()));
create policy "otd_update" on public.ops_team_daily for update
  using      (public.is_ops_admin() or (public.is_ops() and day = public.tr_today()))
  with check (public.is_ops_admin() or (public.is_ops() and day = public.tr_today()));
create policy "otd_delete" on public.ops_team_daily for delete using (public.is_ops_admin());

-- ---------- KREATİF · günlük ----------
drop policy if exists "kd_insert" on public.kre_daily;
drop policy if exists "kd_update" on public.kre_daily;
create policy "kd_insert" on public.kre_daily for insert
  with check (public.is_kre_admin() or (initial = public.my_initial() and day = public.tr_today()));
create policy "kd_update" on public.kre_daily for update
  using      (public.is_kre_admin() or (initial = public.my_initial() and day = public.tr_today()))
  with check (public.is_kre_admin() or (initial = public.my_initial() and day = public.tr_today()));

-- ---------- KREATİF · puan ----------
drop policy if exists "ks_insert" on public.kre_scores;
drop policy if exists "ks_update" on public.kre_scores;
create policy "ks_insert" on public.kre_scores for insert
  with check (public.is_kre_admin() or (rater = public.my_initial() and day = public.tr_today()));
create policy "ks_update" on public.kre_scores for update
  using      (public.is_kre_admin() or (rater = public.my_initial() and day = public.tr_today()))
  with check (public.is_kre_admin() or (rater = public.my_initial() and day = public.tr_today()));

-- kontrol: bugünün Türkiye tarihi
select public.tr_today() as turkiye_bugun;

-- ============================================================
-- v1.9 MESAİ ÜCRETLERİ (operasyon + kreatif, tek seferde çalıştır)
-- Kişi başı saatlik mesai ücreti. Sadece yönetici + ortaklar görür/yazar;
-- ekip üyeleri bu tabloyu hiç okuyamaz (sadece kendi saatlerini görür).
-- person: 'ops:<ops_members.id>' ya da 'kre:<harf>'
-- month : ücretin geçerli olmaya başladığı ayın 1'i
-- ============================================================
create table if not exists public.pay_rates (
  person     text not null,
  month      date not null,
  hourly     numeric not null check (hourly >= 0),
  updated_by uuid references auth.users on delete set null,
  updated_at timestamptz default now(),
  primary key (person, month)
);
alter table public.pay_rates enable row level security;
drop policy if exists "pay_rates_admin" on public.pay_rates;
create policy "pay_rates_admin" on public.pay_rates for all
  using      (coalesce(public.my_role() in ('admin','partner'), false))
  with check (coalesce(public.my_role() in ('admin','partner'), false));

select 'pay_rates hazir' as durum;

-- ============================================================
-- v2.2 (tek seferde çalıştır)
-- 1) Operasyon günlüğü: "teslim edilmeyen arama · bakmadı" alanı
-- 2) Stok sorumluluğu Uğur abiye → Stok sekmesini sadece o (ve yöneticiler) görür
-- 3) Kreatif: Çağdaş ve Erdem puanlanamaz, kendileri puan verebilir
-- ============================================================
alter table public.ops_daily add column if not exists undel_nolook integer;

insert into public.ops_assignments(role_key, member_id, updated_at)
select 'stok', id, now() from public.ops_members where name ilike 'u_ur%' order by active desc limit 1
on conflict (role_key) do update set member_id = excluded.member_id, updated_at = now();

update public.kre_settings
set value = value || jsonb_build_object('unrated',
      (select coalesce(jsonb_agg(initial), '[]'::jsonb) from public.team_members
        where name ilike '_a_da_%' or name ilike 'erdem%')),
    updated_at = now()
where key = 'roles';

create or replace function public.kre_unrated(p text)
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce((select (value->'unrated') ? p from public.kre_settings where key = 'roles'), false) $$;

drop policy if exists "ks_insert" on public.kre_scores;
drop policy if exists "ks_update" on public.kre_scores;
create policy "ks_insert" on public.kre_scores for insert
  with check (not public.kre_unrated(ratee)
              and (public.is_kre_admin() or (rater = public.my_initial() and day = public.tr_today())));
create policy "ks_update" on public.kre_scores for update
  using      (public.is_kre_admin() or (rater = public.my_initial() and day = public.tr_today()))
  with check (not public.kre_unrated(ratee)
              and (public.is_kre_admin() or (rater = public.my_initial() and day = public.tr_today())));

-- kontrol: puanlanmayan harfler · stok sorumlusu · yeni alan (1 olmalı)
select (select value->'unrated' from public.kre_settings where key = 'roles') as puanlanamaz,
       (select m.name from public.ops_assignments a join public.ops_members m on m.id = a.member_id where a.role_key = 'stok') as stok_sorumlusu,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'ops_daily' and column_name = 'undel_nolook') as yeni_alan;

-- ============================================================
-- v2.3
-- 1) Günlük kayıtlara "yönetici girdi" izi (kaç kez, kim, ne zaman)
--    Yönetici başkasının ya da kapanmış bir günün kaydını doldurduğunda panel otomatik yazar.
-- 2) Anıl · 18.09.2026 çıkış 18:10 (yönetici girişi olarak işaretli)
-- ============================================================
alter table public.ops_daily add column if not exists admin_edits   integer default 0;
alter table public.ops_daily add column if not exists admin_by      uuid references auth.users on delete set null;
alter table public.ops_daily add column if not exists admin_by_name text;
alter table public.ops_daily add column if not exists admin_at      timestamptz;

alter table public.kre_daily add column if not exists admin_edits   integer default 0;
alter table public.kre_daily add column if not exists admin_by      uuid references auth.users on delete set null;
alter table public.kre_daily add column if not exists admin_by_name text;
alter table public.kre_daily add column if not exists admin_at      timestamptz;

-- Anıl'ın dünkü çıkışı
insert into public.ops_daily (member_id, day, out_time, admin_edits, admin_at, updated_at)
select id, date '2026-09-18', '18:10', 1, now(), now()
from public.ops_members where name ilike 'an_l%' limit 1
on conflict (member_id, day) do update
  set out_time    = excluded.out_time,
      admin_edits = coalesce(public.ops_daily.admin_edits, 0) + 1,
      admin_at    = now(),
      updated_at  = now();

-- kontrol
select m.name, d.day, d.in_time, d.out_time, d.admin_edits
from public.ops_daily d join public.ops_members m on m.id = d.member_id
where d.day = date '2026-09-18' order by m.name;
