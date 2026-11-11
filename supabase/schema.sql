-- MOD K8 / Supabase schema starter
-- Run this in Supabase SQL Editor. Review before production.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  product_type text not null check (product_type in ('acc','file','link','tool')),
  price bigint not null check (price >= 0),
  status text not null default 'available' check (status in ('available','soldout','maintenance')),
  storage_path text,
  external_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (product_type = 'file' and storage_path is not null and external_url is null)
    or (product_type in ('link','tool') and external_url is not null)
    or (product_type = 'acc')
  )
);

create table if not exists public.acc_inventory (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  username text not null,
  password text not null,
  status text not null default 'available' check (status in ('available','reserved','delivered','disabled')),
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  order_id uuid,
  unique(product_id, username)
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  order_code text not null unique default ('MK8-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,12))),
  status text not null default 'pending_payment' check (status in ('pending_payment','paid','fulfilled','cancelled','refunded')),
  total_amount bigint not null check (total_amount >= 0),
  payment_reference text unique,
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  fulfilled_at timestamptz
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  unit_price bigint not null,
  quantity integer not null check (quantity > 0),
  created_at timestamptz not null default now()
);

create table if not exists public.order_deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  order_item_id uuid not null references public.order_items(id) on delete cascade,
  delivery_type text not null check (delivery_type in ('acc','file','link','tool')),
  delivery_payload jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.acc_inventory
  add constraint acc_inventory_order_id_fkey
  foreign key (order_id) references public.orders(id) on delete set null;

create index if not exists products_type_status_idx on public.products(product_type,status);
create index if not exists acc_inventory_stock_idx on public.acc_inventory(product_id,status);
create index if not exists orders_user_created_idx on public.orders(user_id,created_at desc);
create index if not exists order_items_order_idx on public.order_items(order_id);

-- Create profile row on signup. New users are always customers.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, display_name, role)
  values(new.id, coalesce(new.raw_user_meta_data->>'display_name',''), 'customer')
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.acc_inventory enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_deliveries enable row level security;

create policy "profiles read own or admin" on public.profiles for select
using (id=auth.uid() or public.is_admin());
create policy "profiles update own display only via backend" on public.profiles for update
using (id=auth.uid()) with check (id=auth.uid() and role='customer');

create policy "public read available products" on public.products for select
using (status='available' or public.is_admin());
create policy "admin manage products" on public.products for all
using (public.is_admin()) with check (public.is_admin());

create policy "admin only acc inventory" on public.acc_inventory for all
using (public.is_admin()) with check (public.is_admin());

create policy "customer read own orders" on public.orders for select
using (user_id=auth.uid() or public.is_admin());
create policy "admin manage orders" on public.orders for all
using (public.is_admin()) with check (public.is_admin());

create policy "customer read own order items" on public.order_items for select
using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
create policy "admin manage order items" on public.order_items for all
using (public.is_admin()) with check (public.is_admin());

create policy "customer read own deliveries" on public.order_deliveries for select
using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
create policy "admin manage deliveries" on public.order_deliveries for all
using (public.is_admin()) with check (public.is_admin());

-- Private bucket for paid downloads. Storage objects are never public.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('product-files','product-files',false,524288000,null)
on conflict(id) do update set public=false, file_size_limit=524288000;

create policy "admin upload product files" on storage.objects for insert
with check (bucket_id='product-files' and public.is_admin());
create policy "admin read product files" on storage.objects for select
using (bucket_id='product-files' and public.is_admin());
create policy "admin update product files" on storage.objects for update
using (bucket_id='product-files' and public.is_admin())
with check (bucket_id='product-files' and public.is_admin());
create policy "admin delete product files" on storage.objects for delete
using (bucket_id='product-files' and public.is_admin());

-- IMPORTANT:
-- 1) Create your first user through Supabase Auth, then promote that UUID manually:
--    update public.profiles set role='admin' where id='YOUR_AUTH_USER_UUID';
-- 2) Never allow a customer to update role, inventory, prices, order status or wallet.
-- 3) Payment webhook and order fulfilment must run server-side with service role.
-- 4) Do not store credentials in localStorage or expose service_role key in browser code.
