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
