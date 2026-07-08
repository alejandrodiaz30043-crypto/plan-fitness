-- ============================================================
-- Plan Fitness — esquema de base de datos para Supabase
-- Corre esto en: tu proyecto → SQL Editor → New query → Run
-- ============================================================

-- Tabla: un registro por usuario, con todo su progreso en columnas JSON
create table if not exists public.user_data (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  mode        text default 'casa',
  days        jsonb default '[0,1,2,3,4,5]'::jsonb,
  start_date  date default current_date,
  log         jsonb default '{}'::jsonb,
  checkins    jsonb default '{}'::jsonb,
  notes       jsonb default '{}'::jsonb,
  diet        jsonb,
  onboarded   boolean default false,
  updated_at  timestamptz default now()
);

-- Activa seguridad a nivel de fila: nadie puede leer/escribir filas ajenas
alter table public.user_data enable row level security;

-- Cada usuario solo puede ver su propia fila
create policy "select_own_data"
  on public.user_data for select
  using (auth.uid() = user_id);

-- Cada usuario solo puede crear su propia fila
create policy "insert_own_data"
  on public.user_data for insert
  with check (auth.uid() = user_id);

-- Cada usuario solo puede actualizar su propia fila
create policy "update_own_data"
  on public.user_data for update
  using (auth.uid() = user_id);

-- (Opcional pero recomendado) cada usuario puede borrar su propia fila
create policy "delete_own_data"
  on public.user_data for delete
  using (auth.uid() = user_id);
