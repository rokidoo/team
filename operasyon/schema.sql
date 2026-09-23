-- ============================================================
-- uzbionik Operasyon Paneli · Supabase Şeması + RLS  (v1.0)
-- Aynı Supabase projesi (kreatif panelle ortak giriş).
-- Supabase Dashboard → SQL Editor → tamamını yapıştır → Run
-- ============================================================

-- ---------- ROL ----------
-- profiles.role değerleri: admin | partner | creative | ops
-- Operasyon ekibi 'ops' rolüyle kayıt olur. Kayıt sırasında sadece
-- 'creative' veya 'ops' seçilebilir; admin/partner yalnızca SQL ile verilir.
drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles for insert
  with check (id = auth.uid() and coalesce(role,'creative') in ('creative','ops'));

create or replace function public.is_ops()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() in ('ops','admin'), false) $$;

-- ---------- EKİP ----------
create table if not exists public.ops_members (
  id       uuid primary key default gen_random_uuid(),
  key      text unique not null,          -- sait | halil | melek | rabia | furkan | anil
  name     text not null,
  color    text default '#FFC53D',
  active   boolean default true,
  sort     integer default 0,
  tasks    text,                          -- görev tanımı (serbest metin)
  user_id  uuid unique references auth.users on delete set null
);

-- giriş yapan kullanıcının ekip kaydı
create or replace function public.my_member()
returns uuid language sql security definer stable
set search_path = public
as $$ select id from public.ops_members where user_id = auth.uid() limit 1 $$;

-- ---------- GÜNLÜK KİŞİSEL KAYIT ----------
create table if not exists public.ops_daily (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid not null references public.ops_members(id) on delete cascade,
  day         date not null,
  in_time     text,                       -- "09:05"
  out_time    text,
  leave_min   integer,                    -- izin (dk)
  ot_min      integer,                    -- mesai (dk)
  cargo       integer,
  call_total  integer, call_send integer, call_nolook integer,
  wp_msg      integer, wp_order integer,
  ig_msg      integer, ig_order integer,
  mail_msg    integer, mail_order integer,
  note        text,                       -- bugün ne yaptım
  wish        text,                       -- yapılmasını istediğim iş
  updated_at  timestamptz default now(),
  unique (member_id, day)
);

-- ---------- EKİP PUANI (gizli: sadece admin + puanı veren görür) ----------
create table if not exists public.ops_scores (
  id         uuid primary key default gen_random_uuid(),
  day        date not null,
  rater_id   uuid not null references public.ops_members(id) on delete cascade,
  ratee_id   uuid not null references public.ops_members(id) on delete cascade,
  score      integer check (score is null or (score between 0 and 10)),
  comment    text,
  updated_at timestamptz default now(),
  unique (day, rater_id, ratee_id)
);

-- ---------- KONTROL LİSTESİ (mesaj kanalı, temizlik, kapanış) ----------
create table if not exists public.ops_checks (
  id       uuid primary key default gen_random_uuid(),
  day      date not null,
  item     text not null,
  done_by  uuid references public.ops_members(id) on delete set null,
  done_at  timestamptz default now(),
  unique (day, item)
);

-- ---------- NÖBET ----------
create table if not exists public.ops_duty (
  day        date primary key,
  a_id       uuid references public.ops_members(id) on delete set null,
  b_id       uuid references public.ops_members(id) on delete set null,
  updated_at timestamptz default now()
);

-- ---------- EKİP GÜNLÜĞÜ: kargo + mesaj kanalı toplamları ----------
create table if not exists public.ops_team_daily (
  day         date primary key,
  hepsijet    integer, yurtici integer, dhl integer, cargo_total integer,
  failed      integer,                    -- teslimat başarısız
  returns     integer, cancels integer,   -- iade / iptal
  wp_total    integer, ig_total integer, mail_total integer,
  note        text,
  updated_by  uuid references public.ops_members(id) on delete set null,
  updated_at  timestamptz default now()
);

-- ---------- MÜŞTERİ SESİ ----------
create table if not exists public.ops_voice (
  id         uuid primary key default gen_random_uuid(),
  day        date not null,
  kind       text not null default 'sikayet',  -- sikayet | soru | geri_donus | haftalik | ekip_mesaj | istek_mesaj
  brand      text,                             -- dogal_denge | ozvenia | best | uzbionik | liarina
  tags       text[] default '{}',              -- erimis | eksik | yanlis | gec | iade | iptal | kullanim | icerik | fiyat | ekitap | diger
  text       text not null,
  by_id      uuid references public.ops_members(id) on delete set null,
  created_at timestamptz default now()
);

-- ---------- STOK ----------
create table if not exists public.ops_products (
  key     text primary key,
  name    text not null,
  sort    integer default 0,
  active  boolean default true,
  min_qty integer default 0
);
create table if not exists public.ops_stock (
  id      uuid primary key default gen_random_uuid(),
  day     date not null,
  product text not null references public.ops_products(key) on delete cascade,
  qty     integer not null,
  by_id   uuid references public.ops_members(id) on delete set null,
  unique (day, product)
);

create index if not exists ops_daily_day_idx  on public.ops_daily(day);
create index if not exists ops_scores_day_idx on public.ops_scores(day);
create index if not exists ops_checks_day_idx on public.ops_checks(day);
create index if not exists ops_voice_day_idx  on public.ops_voice(day);

-- ============================================================
-- RLS
-- ============================================================
alter table public.ops_members    enable row level security;
alter table public.ops_daily      enable row level security;
alter table public.ops_scores     enable row level security;
alter table public.ops_checks     enable row level security;
alter table public.ops_duty       enable row level security;
alter table public.ops_team_daily enable row level security;
alter table public.ops_voice      enable row level security;
alter table public.ops_products   enable row level security;
alter table public.ops_stock      enable row level security;

-- ekip: herkes görür; kişi boş bir kaydı kendine bağlayabilir; admin her şeyi
create policy "om_select" on public.ops_members for select using (public.is_ops());
create policy "om_claim"  on public.ops_members for update
  using (public.is_admin() or (user_id is null and public.is_ops()))
  with check (public.is_admin() or user_id = auth.uid());
create policy "om_admin_ins" on public.ops_members for insert with check (public.is_admin());
create policy "om_admin_del" on public.ops_members for delete using (public.is_admin());

-- günlük kayıt: herkes okur, herkes sadece kendi satırını yazar
create policy "od_select" on public.ops_daily for select using (public.is_ops());
create policy "od_insert" on public.ops_daily for insert
  with check (public.is_admin() or member_id = public.my_member());
create policy "od_update" on public.ops_daily for update
  using (public.is_admin() or member_id = public.my_member());
create policy "od_delete" on public.ops_daily for delete using (public.is_admin());

-- puan: puanı veren kendi verdiklerini görür, puanlanan asla görmez, admin hepsini görür
create policy "os_select" on public.ops_scores for select
  using (public.is_admin() or rater_id = public.my_member());
create policy "os_insert" on public.ops_scores for insert
  with check (public.is_admin() or rater_id = public.my_member());
create policy "os_update" on public.ops_scores for update
  using (public.is_admin() or rater_id = public.my_member());
create policy "os_delete" on public.ops_scores for delete using (public.is_admin());

-- kontrol listesi: herkes tikler, kendi tikini kaldırır
create policy "oc_select" on public.ops_checks for select using (public.is_ops());
create policy "oc_insert" on public.ops_checks for insert
  with check (public.is_admin() or done_by = public.my_member());
create policy "oc_delete" on public.ops_checks for delete
  using (public.is_admin() or done_by = public.my_member());

-- nöbet, ekip günlüğü, stok: ekipten herkes yazar
create policy "odt_all" on public.ops_duty       for all using (public.is_ops()) with check (public.is_ops());
create policy "otd_all" on public.ops_team_daily for all using (public.is_ops()) with check (public.is_ops());
create policy "ost_all" on public.ops_stock      for all using (public.is_ops()) with check (public.is_ops());

-- müşteri sesi: herkes ekler, kendi kaydını düzenler
create policy "ov_select" on public.ops_voice for select using (public.is_ops());
create policy "ov_insert" on public.ops_voice for insert
  with check (public.is_admin() or by_id = public.my_member());
create policy "ov_update" on public.ops_voice for update
  using (public.is_admin() or by_id = public.my_member());
create policy "ov_delete" on public.ops_voice for delete
  using (public.is_admin() or by_id = public.my_member());

-- ürünler: herkes okur, admin düzenler
create policy "op_select" on public.ops_products for select using (public.is_ops());
create policy "op_write"  on public.ops_products for all
  using (public.is_admin()) with check (public.is_admin());

-- ============================================================
-- BAŞLANGIÇ VERİSİ
-- ============================================================
insert into public.ops_members (key, name, color, active, sort, tasks) values
  ('sait',  'Sait',          '#2F5DFF', true, 1, 'Planlama, görev dağılımı, barkod, stok'),
  ('halil', 'Halil İbrahim', '#FF8A00', true, 2, 'Kargo süreçleri, iade-iptal, teslim edilemeyen aramaları'),
  ('melek', 'Melek',         '#EC4899', true, 3, 'Instagram + Mail mesajları, sipariş girişi, müşteri sesi'),
  ('rabia', 'Rabia',         '#A855F7', true, 4, 'Arama, WhatsApp, temizlik ve nöbet düzeni'),
  ('furkan','Furkan',        '#22C55E', true, 5, 'Arama, bakmadı takibi'),
  ('anil',  'Anıl',          '#FFC53D', true, 6, 'Anlık aramalar'),
  ('efkan', 'Efkan',         '#9AA0A6', false, 7, null),
  ('umut',  'Umut',          '#9AA0A6', false, 8, null)
on conflict (key) do nothing;

insert into public.ops_products (key, name, sort) values
  ('dogal_shilajit','Doğal Shilajit',1), ('bestside_gummy','Bestside Gummy',2), ('nioli','Nioli',3),
  ('agiz_sprey','Ağız Sprey',4), ('esans','Esans',5), ('uz_cilek','Uz Çilek',6), ('uz_ananas','Uz Ananas',7),
  ('kolajen_maske','Kolajen Maske',8), ('hidro_maske','Hidro Maske',9), ('soyulabilir','Soyulabilir',10),
  ('niasinamid','Niasinamid',11), ('ozvenia','Ozvenia',12), ('senlina','Senlina',13)
on conflict (key) do nothing;

-- ============================================================
-- İSTEĞE BAĞLI: operasyon ekibi kreatif panelin verisini görmesin.
-- (Şu an kreatif tabloları "giriş yapmış herkes" okuyabiliyor.)
-- Çalıştırmak istersen aşağıdaki bloğun yorumunu kaldır.
-- ============================================================
-- drop policy if exists "creatives_select" on public.creatives;
-- create policy "creatives_select" on public.creatives for select using (auth.uid() is not null and public.my_role() <> 'ops');
-- drop policy if exists "results_select" on public.weekly_results;
-- create policy "results_select" on public.weekly_results for select using (auth.uid() is not null and public.my_role() <> 'ops');
-- drop policy if exists "hooks_select" on public.hooks;
-- create policy "hooks_select" on public.hooks for select using (auth.uid() is not null and public.my_role() <> 'ops');
-- drop policy if exists "ln_select" on public.links;
-- create policy "ln_select" on public.links for select using (auth.uid() is not null and public.my_role() <> 'ops');
-- drop policy if exists "pc_select" on public.pipeline_cards;
-- create policy "pc_select" on public.pipeline_cards for select using (auth.uid() is not null and public.my_role() <> 'ops');
-- drop policy if exists "ip_select" on public.idea_pool;
-- create policy "ip_select" on public.idea_pool for select using (auth.uid() is not null and public.my_role() <> 'ops');

-- ============================================================
-- v1.1: HAFTANIN / AYIN BİRİNCİSİ
-- Puanlar gizli kaldığı için sıralama sunucuda hesaplanır:
-- ekip sadece kazananın adını görür, yönetici tam tabloyu görür.
-- ============================================================
create table if not exists public.ops_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz default now()
);
create table if not exists public.ops_awards (          -- elle atanan birinci (isteğe bağlı)
  kind         text not null,                            -- hafta | ay
  period_start date not null,
  member_id    uuid references public.ops_members(id) on delete cascade,
  note         text,
  updated_at   timestamptz default now(),
  primary key (kind, period_start)
);
alter table public.ops_settings enable row level security;
alter table public.ops_awards   enable row level security;
create policy "oset_select" on public.ops_settings for select using (public.is_ops());
create policy "oset_write"  on public.ops_settings for all using (public.is_admin()) with check (public.is_admin());
create policy "oaw_select"  on public.ops_awards for select using (public.is_ops());
create policy "oaw_write"   on public.ops_awards for all using (public.is_admin()) with check (public.is_admin());

insert into public.ops_settings (key, value) values
  ('rank_weights', '{"puan":40,"disiplin":20,"devam":15,"kontrol":10,"hacim":15}')
on conflict (key) do nothing;

-- Sıralama: p_full=true sadece yönetici (tüm bileşenler), aksi halde sadece lider (ad).
create or replace function public.ops_ranking(p_from date, p_to date, p_full boolean default false)
returns table(member_id uuid, name text, puan numeric, n_puan integer, disiplin numeric,
              devam numeric, kontrol numeric, hacim numeric, total numeric)
language plpgsql security definer
set search_path = public
as $$
declare w jsonb; wdays integer;
begin
  if p_full and not public.is_admin() then raise exception 'sadece yönetici'; end if;
  if not public.is_ops() then raise exception 'yetki yok'; end if;
  select value into w from public.ops_settings where key = 'rank_weights';
  w := coalesce(w, '{"puan":40,"disiplin":20,"devam":15,"kontrol":10,"hacim":15}'::jsonb);
  select count(*) into wdays
    from generate_series(p_from, least(p_to, current_date), interval '1 day') d
    where extract(dow from d) <> 0;
  return query
  with m as (select id, ops_members.name from public.ops_members where active),
  d as (select od.member_id, count(*)::numeric filled,
               count(*) filter (where in_time is not null)::numeric n_in,
               count(*) filter (where in_time is not null and in_time <= '09:10')::numeric ontime,
               sum(coalesce(call_total,0)+coalesce(wp_msg,0)+coalesce(ig_msg,0)+coalesce(mail_msg,0)+coalesce(cargo,0))::numeric vol
        from public.ops_daily od where day between p_from and p_to group by od.member_id),
  s as (select ratee_id, avg(score)::numeric sc, count(score)::integer n
        from public.ops_scores where day between p_from and p_to and score is not null group by ratee_id),
  c as (select done_by, count(*)::numeric ticks from public.ops_checks where day between p_from and p_to group by done_by),
  base as (select m.id, m.name,
             coalesce(s.sc,0)*10 puan, coalesce(s.n,0) n_puan,
             least(100, coalesce(d.filled,0)/greatest(wdays,1)*100) disiplin,
             case when coalesce(d.n_in,0) > 0 then d.ontime/d.n_in*100 else 0 end devam,
             coalesce(c.ticks,0) ticks,
             coalesce(d.vol,0)/greatest(coalesce(d.filled,1),1) volpd
           from m left join d on d.member_id = m.id left join s on s.ratee_id = m.id left join c on c.done_by = m.id),
  mx as (select greatest(max(ticks),1) mt, greatest(max(volpd),1) mv from base),
  r as (select b.id, b.name, b.puan, b.n_puan, b.disiplin, b.devam,
               b.ticks/mx.mt*100 kontrol, b.volpd/mx.mv*100 hacim,
               (b.puan*(w->>'puan')::numeric + b.disiplin*(w->>'disiplin')::numeric + b.devam*(w->>'devam')::numeric
                + b.ticks/mx.mt*100*(w->>'kontrol')::numeric + b.volpd/mx.mv*100*(w->>'hacim')::numeric)/100 total
        from base b, mx)
  select r.id, r.name,
         case when p_full then round(r.puan,1) end, case when p_full then r.n_puan end,
         case when p_full then round(r.disiplin,1) end, case when p_full then round(r.devam,1) end,
         case when p_full then round(r.kontrol,1) end, case when p_full then round(r.hacim,1) end,
         case when p_full then round(r.total,1) end
  from r where r.total > 0
  order by r.total desc, r.puan desc
  limit case when p_full then 100 else 1 end;
end $$;

-- ============================================================
-- v1.2: SORUMLULUKLAR + GÖREV ATAMA + DENETİM NOTU
-- ============================================================
create table if not exists public.ops_assignments (      -- sabit sorumluluk -> tek kişi
  role_key   text primary key,                           -- stok | kargo | mesaj_kontrol | temizlik_kontrol
  member_id  uuid references public.ops_members(id) on delete set null,
  note       text,
  updated_at timestamptz default now()
);
create table if not exists public.ops_tasks (            -- yöneticinin verdiği tek seferlik işler
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  detail      text,
  member_id   uuid not null references public.ops_members(id) on delete cascade,
  due         date,
  created_by  uuid references auth.users on delete set null,
  created_at  timestamptz default now(),
  done        boolean default false,
  done_at     timestamptz,
  done_note   text
);
alter table public.ops_checks add column if not exists note text;

alter table public.ops_assignments enable row level security;
alter table public.ops_tasks       enable row level security;
create policy "oas_select" on public.ops_assignments for select using (public.is_ops());
create policy "oas_write"  on public.ops_assignments for all using (public.is_admin()) with check (public.is_admin());
create policy "otk_select" on public.ops_tasks for select using (public.is_admin() or member_id = public.my_member());
create policy "otk_insert" on public.ops_tasks for insert with check (public.is_admin());
create policy "otk_update" on public.ops_tasks for update using (public.is_admin() or member_id = public.my_member());
create policy "otk_delete" on public.ops_tasks for delete using (public.is_admin());

insert into public.ops_assignments (role_key, member_id) values
  ('stok',             (select id from public.ops_members where key='sait')),
  ('kargo',            (select id from public.ops_members where key='halil')),
  ('mesaj_kontrol',    (select id from public.ops_members where key='melek')),
  ('temizlik_kontrol', (select id from public.ops_members where key='rabia'))
on conflict (role_key) do nothing;

-- ============================================================
-- v1.4: MARKALAR + ÜRÜN-MARKA BAĞI + diğer markaların temizliği
-- ============================================================
create table if not exists public.ops_brands (
  key    text primary key,
  name   text not null,
  sort   integer default 0,
  active boolean default true
);
alter table public.ops_brands enable row level security;
create policy "ob_select" on public.ops_brands for select using (public.is_ops());
create policy "ob_write"  on public.ops_brands for all using (public.is_admin()) with check (public.is_admin());
alter table public.ops_products add column if not exists brand text references public.ops_brands(key) on delete set null;

insert into public.ops_brands (key, name, sort) values ('uzbionik', 'uzbionik', 1) on conflict (key) do nothing;

-- sadece uzbionik kalsın: diğer markaların müşteri notları, ürünleri ve stokları silinir
delete from public.ops_voice    where brand is not null and brand <> 'uzbionik';
delete from public.ops_products where key not in ('uz_cilek','uz_ananas');   -- stoklar cascade ile silinir
update public.ops_products set brand = 'uzbionik',
  name = case key when 'uz_cilek' then 'uzbionik Çilek' else 'uzbionik Ananaslı' end,
  sort = case key when 'uz_cilek' then 1 else 2 end
  where key in ('uz_cilek','uz_ananas');

-- v1.5: mesaj kanalı temizleme sorumluluğu (Kontrol listesindeki sabah/akşam mesaj maddeleri)
insert into public.ops_assignments (role_key, member_id) values
  ('mesaj_kanali', (select id from public.ops_members where key='melek'))
on conflict (role_key) do nothing;

-- ============================================================
-- v1.6: KONTROL LİSTESİ MADDELERİ (yönetici ekler/değiştirir)
-- ============================================================
create table if not exists public.ops_check_items (
  key       text primary key,
  group_key text not null,      -- mesaj_sabah | mesaj_aksam | temizlik_sabah | temizlik_aksam | kapanis
  label     text not null,
  sort      integer default 0,
  active    boolean default true
);
alter table public.ops_check_items enable row level security;
create policy "oci_select" on public.ops_check_items for select using (public.is_ops());
create policy "oci_write"  on public.ops_check_items for all using (public.is_admin()) with check (public.is_admin());
insert into public.ops_check_items (key, group_key, label, sort) values
  ('wp_sabah','mesaj_sabah','WhatsApp temizlendi',1), ('ig_sabah','mesaj_sabah','Instagram temizlendi',2), ('mail_sabah','mesaj_sabah','Mail temizlendi',3),
  ('wp_aksam','mesaj_aksam','WhatsApp temizlendi',1), ('ig_aksam','mesaj_aksam','Instagram temizlendi',2), ('mail_aksam','mesaj_aksam','Mail temizlendi',3),
  ('masa_sabah','temizlik_sabah','Masa ve içerinin temizliği',1), ('bulasik_sabah','temizlik_sabah','Bulaşık',2), ('cop_sabah','temizlik_sabah','Çöpler toplandı ve atıldı',3),
  ('masa_aksam','temizlik_aksam','Masa ve içerinin temizliği',1), ('bulasik_aksam','temizlik_aksam','Bulaşık',2), ('cop_aksam','temizlik_aksam','Çöpler toplandı ve atıldı',3),
  ('fis','kapanis','Fişler çekildi',1), ('klima','kapanis','Klima kapatıldı',2), ('alan','kapanis','Herkes kendi alanını topladı',3), ('tuvalet','kapanis','Tuvalet temizliği',4)
on conflict (key) do nothing;

-- ============================================================
-- v1.7: ORTAKLAR (partner) operasyonda tam yetkili
-- ============================================================
create or replace function public.is_ops()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() in ('ops','admin','partner'), false) $$;

create or replace function public.is_ops_admin()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() in ('admin','partner'), false) $$;

-- ortaklar profil listesini görebilsin (üye-hesap bağlama için)
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select
  using (id = auth.uid() or public.is_ops_admin());

-- ops tablolarındaki yönetici koşullarını ops_admin'e çevir
do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies where schemaname='public' and tablename like 'ops\_%' loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

create policy "om_select" on public.ops_members for select using (public.is_ops());
create policy "om_claim"  on public.ops_members for update
  using (public.is_ops_admin() or (user_id is null and public.is_ops()))
  with check (public.is_ops_admin() or user_id = auth.uid());
create policy "om_admin_ins" on public.ops_members for insert with check (public.is_ops_admin());
create policy "om_admin_del" on public.ops_members for delete using (public.is_ops_admin());
create policy "od_select" on public.ops_daily for select using (public.is_ops());
create policy "od_insert" on public.ops_daily for insert with check (public.is_ops_admin() or member_id = public.my_member());
create policy "od_update" on public.ops_daily for update using (public.is_ops_admin() or member_id = public.my_member());
create policy "od_delete" on public.ops_daily for delete using (public.is_ops_admin());
create policy "os_select" on public.ops_scores for select using (public.is_ops_admin() or rater_id = public.my_member());
create policy "os_insert" on public.ops_scores for insert with check (public.is_ops_admin() or rater_id = public.my_member());
create policy "os_update" on public.ops_scores for update using (public.is_ops_admin() or rater_id = public.my_member());
create policy "os_delete" on public.ops_scores for delete using (public.is_ops_admin());
create policy "oc_select" on public.ops_checks for select using (public.is_ops());
create policy "oc_insert" on public.ops_checks for insert with check (public.is_ops_admin() or done_by = public.my_member());
create policy "oc_update" on public.ops_checks for update using (public.is_ops_admin() or done_by = public.my_member());
create policy "oc_delete" on public.ops_checks for delete using (public.is_ops_admin() or done_by = public.my_member());
create policy "odt_all" on public.ops_duty       for all using (public.is_ops()) with check (public.is_ops());
create policy "otd_all" on public.ops_team_daily for all using (public.is_ops()) with check (public.is_ops());
create policy "ost_all" on public.ops_stock      for all using (public.is_ops()) with check (public.is_ops());
create policy "ov_select" on public.ops_voice for select using (public.is_ops());
create policy "ov_insert" on public.ops_voice for insert with check (public.is_ops_admin() or by_id = public.my_member());
create policy "ov_update" on public.ops_voice for update using (public.is_ops_admin() or by_id = public.my_member());
create policy "ov_delete" on public.ops_voice for delete using (public.is_ops_admin() or by_id = public.my_member());
create policy "op_select" on public.ops_products for select using (public.is_ops());
create policy "op_write"  on public.ops_products for all using (public.is_ops_admin()) with check (public.is_ops_admin());
create policy "oset_select" on public.ops_settings for select using (public.is_ops());
create policy "oset_write"  on public.ops_settings for all using (public.is_ops_admin()) with check (public.is_ops_admin());
create policy "oaw_select"  on public.ops_awards for select using (public.is_ops());
create policy "oaw_write"   on public.ops_awards for all using (public.is_ops_admin()) with check (public.is_ops_admin());
create policy "oas_select" on public.ops_assignments for select using (public.is_ops());
create policy "oas_write"  on public.ops_assignments for all using (public.is_ops_admin()) with check (public.is_ops_admin());
create policy "otk_select" on public.ops_tasks for select using (public.is_ops_admin() or member_id = public.my_member());
create policy "otk_insert" on public.ops_tasks for insert with check (public.is_ops_admin());
create policy "otk_update" on public.ops_tasks for update using (public.is_ops_admin() or member_id = public.my_member());
create policy "otk_delete" on public.ops_tasks for delete using (public.is_ops_admin());
create policy "ob_select" on public.ops_brands for select using (public.is_ops());
create policy "ob_write"  on public.ops_brands for all using (public.is_ops_admin()) with check (public.is_ops_admin());
create policy "oci_select" on public.ops_check_items for select using (public.is_ops());
create policy "oci_write"  on public.ops_check_items for all using (public.is_ops_admin()) with check (public.is_ops_admin());

-- sıralama fonksiyonu: tam tablo ortaklara da açık
create or replace function public.ops_ranking(p_from date, p_to date, p_full boolean default false)
returns table(member_id uuid, name text, puan numeric, n_puan integer, disiplin numeric,
              devam numeric, kontrol numeric, hacim numeric, total numeric)
language plpgsql security definer
set search_path = public
as $$
declare w jsonb; wdays integer;
begin
  if p_full and not public.is_ops_admin() then raise exception 'sadece yönetici'; end if;
  if not public.is_ops() then raise exception 'yetki yok'; end if;
  select value into w from public.ops_settings where key = 'rank_weights';
  w := coalesce(w, '{"puan":40,"disiplin":20,"devam":15,"kontrol":10,"hacim":15}'::jsonb);
  select count(*) into wdays
    from generate_series(p_from, least(p_to, current_date), interval '1 day') d
    where extract(dow from d) <> 0;
  return query
  with m as (select id, ops_members.name from public.ops_members where active),
  d as (select od.member_id, count(*)::numeric filled,
               count(*) filter (where in_time is not null)::numeric n_in,
               count(*) filter (where in_time is not null and in_time <= '09:10')::numeric ontime,
               sum(coalesce(call_total,0)+coalesce(wp_msg,0)+coalesce(ig_msg,0)+coalesce(mail_msg,0)+coalesce(cargo,0))::numeric vol
        from public.ops_daily od where day between p_from and p_to group by od.member_id),
  s as (select ratee_id, avg(score)::numeric sc, count(score)::integer n
        from public.ops_scores where day between p_from and p_to and score is not null group by ratee_id),
  c as (select done_by, count(*)::numeric ticks from public.ops_checks where day between p_from and p_to group by done_by),
  base as (select m.id, m.name,
             coalesce(s.sc,0)*10 puan, coalesce(s.n,0) n_puan,
             least(100, coalesce(d.filled,0)/greatest(wdays,1)*100) disiplin,
             case when coalesce(d.n_in,0) > 0 then d.ontime/d.n_in*100 else 0 end devam,
             coalesce(c.ticks,0) ticks,
             coalesce(d.vol,0)/greatest(coalesce(d.filled,1),1) volpd
           from m left join d on d.member_id = m.id left join s on s.ratee_id = m.id left join c on c.done_by = m.id),
  mx as (select greatest(max(ticks),1) mt, greatest(max(volpd),1) mv from base),
  r as (select b.id, b.name, b.puan, b.n_puan, b.disiplin, b.devam,
               b.ticks/mx.mt*100 kontrol, b.volpd/mx.mv*100 hacim,
               (b.puan*(w->>'puan')::numeric + b.disiplin*(w->>'disiplin')::numeric + b.devam*(w->>'devam')::numeric
                + b.ticks/mx.mt*100*(w->>'kontrol')::numeric + b.volpd/mx.mv*100*(w->>'hacim')::numeric)/100 total
        from base b, mx)
  select r.id, r.name,
         case when p_full then round(r.puan,1) end, case when p_full then r.n_puan end,
         case when p_full then round(r.disiplin,1) end, case when p_full then round(r.devam,1) end,
         case when p_full then round(r.kontrol,1) end, case when p_full then round(r.hacim,1) end,
         case when p_full then round(r.total,1) end
  from r where r.total > 0
  order by r.total desc, r.puan desc
  limit case when p_full then 100 else 1 end;
end $$;

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
-- v2.0 ANALİZ DOSYALARI (yönetim → 📈 Verimlilik)
-- Claude'un haftalık/aylık analiz dosyaları burada saklanır.
-- Sadece yönetici + ortaklar görür/ekler; silmeyi yönetici yapar.
-- ============================================================
create table if not exists public.analyses (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null default 'haftalik',   -- haftalik | aylik
  period_start date not null,
  period_end   date not null,
  title        text not null,
  body         jsonb not null,
  created_by   uuid references auth.users on delete set null,
  created_at   timestamptz default now(),
  unique (kind, period_start)
);
alter table public.analyses enable row level security;
drop policy if exists "an_select" on public.analyses;
drop policy if exists "an_insert" on public.analyses;
drop policy if exists "an_update" on public.analyses;
drop policy if exists "an_delete" on public.analyses;
create policy "an_select" on public.analyses for select using (coalesce(public.my_role() in ('admin','partner'), false));
create policy "an_insert" on public.analyses for insert with check (coalesce(public.my_role() in ('admin','partner'), false));
create policy "an_update" on public.analyses for update
  using (coalesce(public.my_role() in ('admin','partner'), false)) with check (coalesce(public.my_role() in ('admin','partner'), false));
create policy "an_delete" on public.analyses for delete using (coalesce(public.my_role() = 'admin', false));

select 'analyses hazir' as durum;

-- ============================================================
-- v2.1 PUAN + STOK YETKİLİSİ (ör. Uğur abi)
-- • ops_members.kind: 'ekip' (normal) | 'puanci' (herkese puan verir, stok girer;
--   günlüğü, nöbeti, sıralaması yok; kimse ona puan veremez)
-- • Adı "Uğur" ile başlayan üye 'puanci' yapılır
-- ============================================================
alter table public.ops_members add column if not exists kind text not null default 'ekip';
alter table public.ops_members drop constraint if exists ops_members_kind_chk;
alter table public.ops_members add constraint ops_members_kind_chk check (kind in ('ekip','puanci'));

create or replace function public.is_puanci(p_member uuid)
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce((select kind='puanci' from public.ops_members where id = p_member), false) $$;

-- puan: kimse puan+stok yetkilisine puan veremez (gün kilidi aynen devam)
drop policy if exists "os_insert" on public.ops_scores;
drop policy if exists "os_update" on public.ops_scores;
create policy "os_insert" on public.ops_scores for insert
  with check (not public.is_puanci(ratee_id)
              and (public.is_ops_admin() or (rater_id = public.my_member() and day = public.tr_today())));
create policy "os_update" on public.ops_scores for update
  using      (public.is_ops_admin() or (rater_id = public.my_member() and day = public.tr_today()))
  with check (not public.is_puanci(ratee_id)
              and (public.is_ops_admin() or (rater_id = public.my_member() and day = public.tr_today())));

-- günlük: puan+stok yetkilisinin günlüğü yok
drop policy if exists "od_insert" on public.ops_daily;
create policy "od_insert" on public.ops_daily for insert
  with check (public.is_ops_admin()
              or (member_id = public.my_member() and day = public.tr_today() and not public.is_puanci(member_id)));

-- sıralama (Birinci / Özet): sadece ekip üyeleri
create or replace function public.ops_ranking(p_from date, p_to date, p_full boolean default false)
returns table(member_id uuid, name text, puan numeric, n_puan integer, disiplin numeric,
              devam numeric, kontrol numeric, hacim numeric, total numeric)
language plpgsql security definer
set search_path = public
as $$
declare w jsonb; wdays integer;
begin
  if p_full and not public.is_ops_admin() then raise exception 'sadece yönetici'; end if;
  if not public.is_ops() then raise exception 'yetki yok'; end if;
  select value into w from public.ops_settings where key = 'rank_weights';
  w := coalesce(w, '{"puan":40,"disiplin":20,"devam":15,"kontrol":10,"hacim":15}'::jsonb);
  select count(*) into wdays
    from generate_series(p_from, least(p_to, current_date), interval '1 day') d
    where extract(dow from d) <> 0;
  return query
  with m as (select id, ops_members.name from public.ops_members where active and coalesce(kind,'ekip')='ekip'),
  d as (select od.member_id, count(*)::numeric filled,
               count(*) filter (where in_time is not null)::numeric n_in,
               count(*) filter (where in_time is not null and in_time <= '09:10')::numeric ontime,
               sum(coalesce(call_total,0)+coalesce(wp_msg,0)+coalesce(ig_msg,0)+coalesce(mail_msg,0)+coalesce(cargo,0))::numeric vol
        from public.ops_daily od where day between p_from and p_to group by od.member_id),
  s as (select ratee_id, avg(score)::numeric sc, count(score)::integer n
        from public.ops_scores where day between p_from and p_to and score is not null group by ratee_id),
  c as (select done_by, count(*)::numeric ticks from public.ops_checks where day between p_from and p_to group by done_by),
  base as (select m.id, m.name,
             coalesce(s.sc,0)*10 puan, coalesce(s.n,0) n_puan,
             least(100, coalesce(d.filled,0)/greatest(wdays,1)*100) disiplin,
             case when coalesce(d.n_in,0) > 0 then d.ontime/d.n_in*100 else 0 end devam,
             coalesce(c.ticks,0) ticks,
             coalesce(d.vol,0)/greatest(coalesce(d.filled,1),1) volpd
           from m left join d on d.member_id = m.id left join s on s.ratee_id = m.id left join c on c.done_by = m.id),
  mx as (select greatest(max(ticks),1) mt, greatest(max(volpd),1) mv from base),
  r as (select b.id, b.name, b.puan, b.n_puan, b.disiplin, b.devam,
               b.ticks/mx.mt*100 kontrol, b.volpd/mx.mv*100 hacim,
               (b.puan*(w->>'puan')::numeric + b.disiplin*(w->>'disiplin')::numeric + b.devam*(w->>'devam')::numeric
                + b.ticks/mx.mt*100*(w->>'kontrol')::numeric + b.volpd/mx.mv*100*(w->>'hacim')::numeric)/100 total
        from base b, mx)
  select r.id, r.name,
         case when p_full then round(r.puan,1) end, case when p_full then r.n_puan end,
         case when p_full then round(r.disiplin,1) end, case when p_full then round(r.devam,1) end,
         case when p_full then round(r.kontrol,1) end, case when p_full then round(r.hacim,1) end,
         case when p_full then round(r.total,1) end
  from r where r.total > 0
  order by r.total desc, r.puan desc
  limit case when p_full then 100 else 1 end;
end $$;

-- Uğur'u puan + stok yetkilisi yap
update public.ops_members set kind = 'puanci' where name ilike 'u_ur%';

-- kontrol
select name, kind, active, (user_id is not null) as hesap_bagli from public.ops_members order by kind desc, sort;

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

-- ============================================================
-- v2.4 Puan notu zorunlu (en az 30 karakter)
-- Ekip üyeleri puan verirken not yazmak zorunda; yönetici/ortak muaf
-- (eski aktarımlar ve yönetici düzeltmeleri bozulmasın diye).
-- Puan silme zaten yöneticiye açık (mevcut politika).
-- ============================================================
create or replace function public.score_note_min()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  if coalesce(public.my_role(), '') in ('admin','partner') then return new; end if;
  if new.score is not null and coalesce(length(btrim(new.comment)), 0) < 30 then
    raise exception 'Puan notu en az 30 karakter olmalı (şu an %). Kişinin gün içindeki durumunu yaz.', coalesce(length(btrim(new.comment)), 0);
  end if;
  return new;
end $$;

drop trigger if exists ops_scores_note_min on public.ops_scores;
create trigger ops_scores_note_min before insert or update on public.ops_scores
  for each row execute function public.score_note_min();

drop trigger if exists kre_scores_note_min on public.kre_scores;
create trigger kre_scores_note_min before insert or update on public.kre_scores
  for each row execute function public.score_note_min();

select 'puan notu kurali hazir' as durum;

-- ============================================================
-- v2.5 Kreatifte puanlanmayacaklar listesine REMAKS eklenir.
-- Liste: Çağdaş, Erdem, Remaks (mevcut liste korunur, üzerine eklenir).
-- Bu kişilere/hesaplara kimse puan veremez; kendileri puan verebilir.
-- ============================================================
update public.kre_settings
set value = value || jsonb_build_object('unrated', (
      select coalesce(jsonb_agg(distinct x), '[]'::jsonb) from (
        select jsonb_array_elements_text(coalesce(value->'unrated', '[]'::jsonb)) as x
          from public.kre_settings where key = 'roles'
        union
        select initial from public.team_members
         where name ilike '_a_da_%' or name ilike 'erdem%' or name ilike 'remaks%'
      ) s)),
    updated_at = now()
where key = 'roles';

-- kontrol: puanlanamayanlar (harf + ad)
select t.initial, t.name
from public.team_members t
where (select value->'unrated' from public.kre_settings where key='roles') ? t.initial
order by t.name;


-- ============================================================
-- v2.6 (tek seferde çalıştır)
-- 1) Kreatifte REMAKS de puanlanamaz (Çağdaş + Erdem'e eklenir)
-- 2) Anıl kreatife geçti: operasyonda pasif, hesabı kreatif ekibine taşınır
--    (operasyondaki geçmiş günlük/puan kayıtları AYNEN kalır)
-- 3) Temizlik listesi 21.09–19.10 arası Anıl'sız, dengeli şekilde yenilenir
--    (17–19 Eylül aynen kalır)
-- ============================================================

-- 1) puanlanamayanlar
update public.kre_settings
set value = value || jsonb_build_object('unrated', (
      select coalesce(jsonb_agg(distinct x), '[]'::jsonb) from (
        select jsonb_array_elements_text(coalesce(value->'unrated', '[]'::jsonb)) as x
          from public.kre_settings where key = 'roles'
        union
        select initial from public.team_members
         where name ilike '_a_da_%' or name ilike 'erdem%' or name ilike 'remaks%'
      ) s)),
    updated_at = now()
where key = 'roles';

-- 2) Anıl: operasyonda pasif + hesabı kreatif ekibine
update public.ops_members set active = false where name ilike 'an_l%';

update public.profiles p
set role = 'creative',
    initial = coalesce((select t.initial from public.team_members t where t.name ilike 'an_l%' limit 1), p.initial)
where p.name ilike 'an_l%' and p.role = 'ops';

-- 3) yeni temizlik listesi
do $$
declare missing text;
begin
  create temp table _r(day date, a text, b text) on commit drop;
  insert into _r values
    ('2026-09-21','Halil','Rabia'),
    ('2026-09-22','Besra','Melek'),
    ('2026-09-23','Mustafa','Halil'),
    ('2026-09-24','Rabia','Cengiz'),
    ('2026-09-25','Sait','Besra'),
    ('2026-09-26','Melek','Halil'),
    ('2026-09-28','Mustafa','Rabia'),
    ('2026-09-29','Cengiz','Sait'),
    ('2026-09-30','Besra','Mustafa'),
    ('2026-10-01','Rabia','Melek'),
    ('2026-10-02','Halil','Cengiz'),
    ('2026-10-03','Besra','Rabia'),
    ('2026-10-05','Sait','Mustafa'),
    ('2026-10-06','Melek','Cengiz'),
    ('2026-10-07','Halil','Sait'),
    ('2026-10-08','Mustafa','Cengiz'),
    ('2026-10-09','Besra','Halil'),
    ('2026-10-10','Mustafa','Melek'),
    ('2026-10-12','Rabia','Sait'),
    ('2026-10-13','Cengiz','Besra'),
    ('2026-10-14','Halil','Rabia'),
    ('2026-10-15','Sait','Melek'),
    ('2026-10-16','Mustafa','Besra'),
    ('2026-10-17','Cengiz','Halil'),
    ('2026-10-19','Rabia','Sait');

  create temp table _p on commit drop as
  select n.nm, coalesce(
      (select case when count(*)=1 then min(id::text) end from public.ops_members where lower(name)=lower(n.nm)),
      (select case when count(*)=1 then min(id::text) end from public.ops_members where split_part(lower(name),' ',1)=lower(n.nm))
    )::uuid as id
  from (select a as nm from _r union select b from _r) n;

  select string_agg(nm, ', ') into missing from _p where id is null;
  if missing is not null then
    raise exception 'Operasyon ekibinde bulunamayan isim: %', missing;
  end if;

  delete from public.ops_duty where day between date '2026-09-21' and date '2026-10-19';
  insert into public.ops_duty(day, a_id, b_id, updated_at)
  select r.day, pa.id, pb.id, now() from _r r join _p pa on pa.nm=r.a join _p pb on pb.nm=r.b;
end $$;

-- kontrol: 17 Eylül–19 Ekim arası kişi başı temizlik görevi
select m.name as kisi, count(*) as gorev
from public.ops_duty d
join public.ops_members m on m.id in (d.a_id, d.b_id)
where d.day between date '2026-09-17' and date '2026-10-19'
group by m.name order by gorev desc, kisi;

-- ============================================================
-- v2.7 TUVALET TEMİZLİĞİ SIRASI (operasyon + kreatif ortak)
-- Her cumartesi tek kişi, listedeki sırayla. İlk cumartesi: 26 Eylül 2026.
-- Aktif hesabı olan herkes okur; sırayı yönetici + ortaklar değiştirir.
-- ============================================================
create table if not exists public.shared_settings (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz default now()
);
alter table public.shared_settings enable row level security;
drop policy if exists "ss_select" on public.shared_settings;
drop policy if exists "ss_write"  on public.shared_settings;
create policy "ss_select" on public.shared_settings for select using (public.my_role() is not null);
create policy "ss_write"  on public.shared_settings for all
  using      (coalesce(public.my_role() in ('admin','partner'), false))
  with check (coalesce(public.my_role() in ('admin','partner'), false));

insert into public.shared_settings(key, value) values
  ('wc_rotation', '{"start":"2026-09-26","names":["Rabia","İmkan","Mustafa Kemal","Besra","İbrahim","Sait","Anıl","Sinan","Elif"]}')
on conflict (key) do nothing;

-- kontrol: önümüzdeki 9 cumartesi
select (date '2026-09-26' + 7*g)::date as cumartesi,
       (value->'names')->>(g % jsonb_array_length(value->'names')) as sorumlu
from public.shared_settings, generate_series(0,8) g
where key = 'wc_rotation';
