-- ============================================================
-- REMAKS EKİP · GÖREV SİSTEMİ v2 — yeni Supabase projesine taşıma
-- (ciwpxeqqrwfsuoggdync · kreatif/operasyon/ortaklar ile aynı proje)
-- Supabase → SQL Editor → tamamını yapıştır → Run
-- ============================================================

-- ---------- profil alanları ----------
alter table public.profiles add column if not exists is_approved boolean not null default false;
alter table public.profiles add column if not exists title text;             -- ekranda görünen unvan (isteğe bağlı)
update public.profiles set is_approved = true where is_approved = false;     -- mevcut herkes onaylı; yeni kayıtlar onay bekler

create or replace function public.is_task_admin()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce(public.my_role() in ('admin','partner'), false) $$;

create or replace function public.is_approved()
returns boolean language sql security definer stable
set search_path = public
as $$ select coalesce((select is_approved or role in ('admin','partner') from public.profiles where id = auth.uid()), false) $$;

-- kayıt olunca profil otomatik açılsın (paneller de kendi eklemesini yapar; çakışırsa sorun olmaz)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, name, role, initial)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)),
          case when new.raw_user_meta_data->>'role' in ('ops','creative') then new.raw_user_meta_data->>'role' else 'creative' end,
          nullif(new.raw_user_meta_data->>'initial',''))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- ---------- kategoriler ----------
create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  color      text not null default '#7c8cff',
  sort_order integer not null default 0,
  owner_id   uuid references auth.users on delete cascade,    -- null = herkese açık, dolu = kişisel
  created_at timestamptz default now()
);
insert into public.categories (name, color, sort_order)
select v.name, v.color, v.sort_order from (values
  ('Meta / Strateji','#E8402A',1), ('Operasyon','#2F5DFF',2), ('Kreatif / Hook','#22C55E',3), ('Ar-Ge','#A855F7',4), ('Finans','#FFC53D',5)
) as v(name,color,sort_order) where not exists (select 1 from public.categories);

-- ---------- görevler ----------
create table if not exists public.tasks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users on delete cascade,   -- asıl sahibi / atanan
  title       text not null,
  descr       text default '',
  due         date,
  status      text not null default 'todo',                            -- todo | doing | done
  priority    text not null default 'normal' check (priority in ('kritik','yuksek','normal','dusuk')),
  category_id uuid references public.categories(id) on delete set null,
  start_time  text, end_time text, link text,
  assigned_by uuid references auth.users on delete set null default auth.uid(),
  source      text default 'ekip',                                     -- ekip | operasyon | ortaklar | kreatif
  done_note   text,
  done_at     timestamptz,
  created_at  timestamptz default now()
);
create index if not exists tasks_user_idx on public.tasks(user_id);
create table if not exists public.task_assignees (
  task_id uuid not null references public.tasks on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  primary key (task_id, user_id)
);
create table if not exists public.task_comments (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  text       text not null,
  created_at timestamptz default now()
);
create table if not exists public.inbox_notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  text       text not null,
  created_at timestamptz default now()
);
create table if not exists public.personal_blocks (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  title      text not null default '',
  link       text, start_time text, end_time text,
  status     text not null default 'fikir' check (status in ('fikir','yapilacak','yapiliyor','yapildi','arsiv')),
  created_at timestamptz default now()
);
create table if not exists public.push_subscriptions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  created_at timestamptz default now()
);

create or replace function public.is_task_member(_task_id uuid)
returns boolean language sql security definer stable
set search_path = public
as $$ select exists (select 1 from public.task_assignees where task_id = _task_id and user_id = auth.uid()) $$;

-- ---------- RLS ----------
alter table public.categories        enable row level security;
alter table public.tasks             enable row level security;
alter table public.task_assignees    enable row level security;
alter table public.task_comments     enable row level security;
alter table public.inbox_notes       enable row level security;
alter table public.personal_blocks   enable row level security;
alter table public.push_subscriptions enable row level security;

drop policy if exists "categories_read"  on public.categories;
drop policy if exists "categories_write" on public.categories;
create policy "categories_read"  on public.categories for select using (owner_id is null or owner_id = auth.uid());
create policy "categories_write" on public.categories for all
  using (public.is_task_admin() or owner_id = auth.uid()) with check (public.is_task_admin() or owner_id = auth.uid());

drop policy if exists "tasks_read"   on public.tasks;
drop policy if exists "tasks_insert" on public.tasks;
drop policy if exists "tasks_update" on public.tasks;
drop policy if exists "tasks_delete" on public.tasks;
create policy "tasks_read" on public.tasks for select using (
  user_id = auth.uid() or public.is_task_admin() or public.is_task_member(id)
);
create policy "tasks_insert" on public.tasks for insert with check (
  (user_id = auth.uid() and public.is_approved()) or public.is_task_admin()
);
create policy "tasks_update" on public.tasks for update using (
  user_id = auth.uid() or public.is_task_admin() or public.is_task_member(id)
);
create policy "tasks_delete" on public.tasks for delete using (
  public.is_task_admin() or (user_id = auth.uid() and (assigned_by = auth.uid() or assigned_by is null))
);

drop policy if exists "assignees_read"  on public.task_assignees;
drop policy if exists "assignees_write" on public.task_assignees;
create policy "assignees_read"  on public.task_assignees for select using (public.is_task_admin() or public.is_task_member(task_id) or exists (select 1 from public.tasks t where t.id = task_id and t.user_id = auth.uid()));
create policy "assignees_write" on public.task_assignees for all
  using (public.is_task_admin() or user_id = auth.uid()) with check (public.is_task_admin() or user_id = auth.uid());

drop policy if exists "comments_read"   on public.task_comments;
drop policy if exists "comments_insert" on public.task_comments;
drop policy if exists "comments_delete" on public.task_comments;
create policy "comments_read" on public.task_comments for select using (
  public.is_task_admin() or public.is_task_member(task_id) or exists (select 1 from public.tasks t where t.id = task_id and t.user_id = auth.uid())
);
create policy "comments_insert" on public.task_comments for insert with check (
  user_id = auth.uid() and (public.is_task_admin() or public.is_task_member(task_id) or exists (select 1 from public.tasks t where t.id = task_id and t.user_id = auth.uid()))
);
create policy "comments_delete" on public.task_comments for delete using (user_id = auth.uid() or public.is_task_admin());

drop policy if exists "inbox_all" on public.inbox_notes;
create policy "inbox_all" on public.inbox_notes for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "pb_all" on public.personal_blocks;
create policy "pb_all" on public.personal_blocks for all
  using (user_id = auth.uid() and public.is_task_admin()) with check (user_id = auth.uid() and public.is_task_admin());
drop policy if exists "push_subs_own" on public.push_subscriptions;
create policy "push_subs_own" on public.push_subscriptions for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- push bildirimi: görev eklenince send-push fonksiyonunu çağır ----------
create extension if not exists pg_net;
create or replace function public.notify_task_assigned()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://ciwpxeqqrwfsuoggdync.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpd3B4ZXFxcndmc3VvZ2dkeW5jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY2MjI4ODQsImV4cCI6MjEwMjE5ODg4NH0.S_vgxYMAjQ9RtkRHxyMJs0NG9aj94_Jn2FfaGszzTOI'),
    body := jsonb_build_object('record', to_jsonb(NEW))
  );
  return new;
end $$;
drop trigger if exists on_task_insert_notify on public.tasks;
create trigger on_task_insert_notify after insert on public.tasks for each row execute function public.notify_task_assigned();
-- ek atananlara da bildirim
create or replace function public.notify_task_assignee_added()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare t record;
begin
  select * into t from public.tasks where id = new.task_id;
  perform net.http_post(
    url := 'https://ciwpxeqqrwfsuoggdync.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNpd3B4ZXFxcndmc3VvZ2dkeW5jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY2MjI4ODQsImV4cCI6MjEwMjE5ODg4NH0.S_vgxYMAjQ9RtkRHxyMJs0NG9aj94_Jn2FfaGszzTOI'),
    body := jsonb_build_object('record', jsonb_build_object('id', t.id, 'title', t.title, 'user_id', new.user_id))
  );
  return new;
end $$;
drop trigger if exists on_task_assignee_notify on public.task_assignees;
create trigger on_task_assignee_notify after insert on public.task_assignees for each row execute function public.notify_task_assignee_added();

-- ---------- eski panel görevlerini taşı (bir kez; tasks boşsa) ----------
do $$
begin
  if not exists (select 1 from public.tasks) then
    insert into public.tasks (user_id, title, descr, due, status, assigned_by, source, done_note, done_at, created_at)
      select m.user_id, t.title, t.detail, t.due, case when t.done then 'done' else 'todo' end, t.created_by, 'operasyon', t.done_note, t.done_at, coalesce(t.created_at, now())
      from public.ops_tasks t join public.ops_members m on m.id = t.member_id where m.user_id is not null;
    insert into public.tasks (user_id, title, descr, due, status, assigned_by, source, done_note, done_at, created_at)
      select t.assigned_to, t.title, t.detail, t.due, case when t.done then 'done' else 'todo' end, t.created_by, 'ortaklar', t.done_note, t.done_at, coalesce(t.created_at, now())
      from public.prt_tasks t where t.assigned_to is not null;
  end if;
end $$;
