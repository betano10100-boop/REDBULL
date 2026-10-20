-- Execute no SQL Editor do seu projeto Supabase.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  cpf text unique,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  price numeric(10,2) not null default 0 check (price >= 0),
  image text not null default '',
  category text not null default 'Clássicos',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.products enable row level security;
-- Permite executar este script novamente sem falhar por políticas já existentes.
drop policy if exists "Profiles can read own profile" on public.profiles;
drop policy if exists "Users can insert own profile" on public.profiles;
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "Public can read active products" on public.products;
drop policy if exists "Admins can insert products" on public.products;
drop policy if exists "Admins can update products" on public.products;
drop policy if exists "Admins can delete products" on public.products;

create policy "Profiles can read own profile" on public.profiles for select to authenticated using (auth.uid() = id);
create policy "Users can insert own profile" on public.profiles for insert to authenticated with check (auth.uid() = id and is_admin = false);
create policy "Users can update own profile" on public.profiles for update to authenticated using (auth.uid() = id and is_admin = false) with check (auth.uid() = id and is_admin = false);
create policy "Public can read active products" on public.products for select to anon, authenticated using (active = true or exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.is_admin = true));
create policy "Admins can insert products" on public.products for insert to authenticated with check (exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.is_admin = true));
create policy "Admins can update products" on public.products for update to authenticated using (exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.is_admin = true)) with check (exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.is_admin = true));
create policy "Admins can delete products" on public.products for delete to authenticated using (exists (select 1 from public.profiles where profiles.id = auth.uid() and profiles.is_admin = true));

-- Produtos de demonstração (opcional)
insert into public.products (name, description, price, image, category, active)
select seed.name, seed.description, seed.price, seed.image, seed.category, true
from (values
  ('Red Bull Energy Drink','250 ml',12.99,'/img/can-1.png','Clássicos'),
  ('Red Bull Sugarfree','250 ml',12.99,'/img/can-2.png','Clássicos'),
  ('Red Bull The Blue Edition','250 ml',13.99,'/img/can-3.png','Edições'),
  ('Red Bull 4 Pack','4 x 250 ml',45.99,'/img/can-4.png','Packs'),
  ('Red Bull Tropical Edition','250 ml',13.99,'/img/can-5.png','Edições'),
  ('Red Bull Red Edition','250 ml',13.99,'/img/can-6.png','Edições')
) as seed(name, description, price, image, category)
where not exists (
  select 1 from public.products existing where existing.name = seed.name
);

-- Depois de criar sua conta, substitua SEU_EMAIL pelo e-mail real no SQL Editor:
-- update public.profiles set is_admin = true where id = (select id from auth.users where email = 'SEU_EMAIL');
-- Se não existir perfil, crie-o usando o id do usuário autenticado (Dashboard > Authentication > Users):
-- insert into public.profiles (id, full_name, is_admin) values ('UUID_DO_USUARIO','Administrador',true)
-- on conflict (id) do update set is_admin = true;


-- Pedidos: os clientes autenticados só podem ver os próprios pedidos;
-- administradores podem consultar e atualizar todos os pedidos.
create sequence if not exists public.order_number_seq;

grant usage, select on sequence public.order_number_seq to authenticated;

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique default ('RB-' || lpad(nextval('public.order_number_seq')::text, 6, '0')),
  user_id uuid not null references auth.users(id) on delete restrict,
  customer_name text not null,
  customer_email text not null default '',
  items jsonb not null default '[]'::jsonb,
  subtotal numeric(10,2) not null check (subtotal >= 0),
  discount numeric(10,2) not null default 0 check (discount >= 0),
  coupon text not null default '',
  shipping numeric(10,2) not null default 0 check (shipping >= 0),
  shipping_days integer not null default 0,
  total numeric(10,2) not null check (total >= 0),
  status text not null default 'Aguardando pagamento'
    check (status in ('Aguardando pagamento','Pago','Em separação','Enviado','Entregue','Cancelado')),
  address text not null,
  created_at timestamptz not null default now()
);

alter table public.orders enable row level security;
drop policy if exists "Users can create own orders" on public.orders;
drop policy if exists "Users can read own orders" on public.orders;
drop policy if exists "Admins can read all orders" on public.orders;
drop policy if exists "Admins can update orders" on public.orders;

create policy "Users can create own orders" on public.orders
  for insert to authenticated
  with check (auth.uid() = user_id);
create policy "Users can read own orders" on public.orders
  for select to authenticated
  using (auth.uid() = user_id);
create policy "Admins can read all orders" on public.orders
  for select to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));
create policy "Admins can update orders" on public.orders
  for update to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin = true));

-- PixouPay: metadados da cobrança. Não expor service_role no navegador.
alter table public.orders add column if not exists payment_id text unique;
alter table public.orders add column if not exists pix_code text;
alter table public.orders add column if not exists pix_qrcode_base64 text;
alter table public.orders add column if not exists payment_status text not null default 'pending';
