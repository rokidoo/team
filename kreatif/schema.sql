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
