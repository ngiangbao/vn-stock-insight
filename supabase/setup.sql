-- Chạy một lần trong Supabase: Dashboard → SQL Editor → New query → dán vào → Run.

-- Bucket riêng tư chứa kết quả phân tích (không ai đọc được nếu chưa đăng nhập)
insert into storage.buckets (id, name, public)
values ('data', 'data', false)
on conflict (id) do update set public = false;

-- Thành viên đã đăng nhập được đọc. Chỉ pipeline (dùng service key) được ghi.
drop policy if exists "Thành viên đọc dữ liệu" on storage.objects;
create policy "Thành viên đọc dữ liệu"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'data');
