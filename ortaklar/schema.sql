-- ============================================================
-- Ortaklar Paneli · Supabase Şeması (v1.0)
-- remakspazarlama.com/ortaklar — sadece admin + partner
-- Aynı Supabase projesi. Kreatif ve operasyon verilerini kendi
-- RLS kurallarıyla okur (ortakların operasyonu görmesi için
-- operasyon schema v1.7 çalıştırılmış olmalı).
-- ============================================================
create or replace function public.is_partner()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() in ('admin','partner'), false) $$;

-- ortak günlüğü
create table if not exists public.prt_daily (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  name       text,
  day        date not null,
  did        text,          -- bugün ne yaptım
  saw        text,          -- ne gördüm / gözlem / sorun
  plan       text,          -- sırada ne var
  updated_at timestamptz default now(),
  unique (user_id, day)
);
-- ortaklara verilen işler
create table if not exists public.prt_tasks (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  detail        text,
  assigned_to   uuid references auth.users on delete cascade,
  assigned_name text,
  due           date,
  created_by    uuid references auth.users on delete set null,
  created_name  text,
  created_at    timestamptz default now(),
  done          boolean default false,
  done_at       timestamptz,
  done_note     text
);
alter table public.prt_daily enable row level security;
alter table public.prt_tasks enable row level security;
create policy "pd_select" on public.prt_daily for select using (public.is_partner());
create policy "pd_insert" on public.prt_daily for insert with check (public.is_partner() and user_id = auth.uid());
create policy "pd_update" on public.prt_daily for update using (public.is_admin() or user_id = auth.uid());
create policy "pd_delete" on public.prt_daily for delete using (public.is_admin() or user_id = auth.uid());
create policy "pt_select" on public.prt_tasks for select using (public.is_partner());
create policy "pt_insert" on public.prt_tasks for insert with check (public.is_partner() and created_by = auth.uid());
create policy "pt_update" on public.prt_tasks for update using (public.is_admin() or assigned_to = auth.uid() or created_by = auth.uid());
create policy "pt_delete" on public.prt_tasks for delete using (public.is_admin() or created_by = auth.uid());
