-- Chạy trong Supabase: Dashboard → SQL Editor → New query → dán vào → Run.
-- Chạy lại nhiều lần vẫn an toàn.

-- 1. Bucket riêng tư chứa kết quả của pipeline (không ai đọc được nếu chưa đăng nhập)
insert into storage.buckets (id, name, public)
values ('data', 'data', false)
on conflict (id) do update set public = false;

-- Thành viên đã đăng nhập được đọc. Chỉ pipeline (dùng service key) được ghi.
drop policy if exists "Thành viên đọc dữ liệu" on storage.objects;
create policy "Thành viên đọc dữ liệu"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'data');

-- 2. Danh sách theo dõi riêng của từng thành viên
create table if not exists public.watchlist (
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  symbol text not null check (symbol ~ '^[A-Z0-9]{3,10}$'),
  created_at timestamptz not null default now(),
  primary key (user_id, symbol)
);
alter table public.watchlist enable row level security;

drop policy if exists "Xem danh sách của mình" on public.watchlist;
create policy "Xem danh sách của mình" on public.watchlist
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "Thêm vào danh sách của mình" on public.watchlist;
create policy "Thêm vào danh sách của mình" on public.watchlist
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Gỡ khỏi danh sách của mình" on public.watchlist;
create policy "Gỡ khỏi danh sách của mình" on public.watchlist
  for delete to authenticated using (user_id = auth.uid());

-- 3. Kết quả phân tích AI theo yêu cầu. Mọi thành viên xem chung (dùng lại kết quả
-- trong vài giờ để tiết kiệm chi phí). Chỉ hàm "analyze" (service key) được ghi.
create table if not exists public.stock_analyses (
  id bigint generated always as identity primary key,
  symbol text not null,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users on delete set null,
  model text,
  inputs jsonb not null,
  result jsonb not null
);
create index if not exists stock_analyses_symbol_time on public.stock_analyses (symbol, created_at desc);
create index if not exists stock_analyses_user_time on public.stock_analyses (created_by, created_at desc);
alter table public.stock_analyses enable row level security;

drop policy if exists "Thành viên xem phân tích" on public.stock_analyses;
create policy "Thành viên xem phân tích" on public.stock_analyses
  for select to authenticated using (true);
