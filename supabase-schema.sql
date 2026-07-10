-- ============================================================
-- Plan Fitness — esquema de base de datos para Supabase
-- Corre esto en: tu proyecto → SQL Editor → New query → Run
-- ============================================================

-- Tabla: un registro por usuario, con todo su progreso en columnas JSON
create table if not exists public.user_data (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  mode         text default 'casa',
  days         jsonb default '[0,1,2,3,4,5]'::jsonb,
  start_date   date default current_date,
  log          jsonb default '{}'::jsonb,
  checkins     jsonb default '{}'::jsonb,
  notes        jsonb default '{}'::jsonb,
  diet         jsonb,
  nivel        text default 'principiante',
  theme        text,
  proteina     jsonb,
  menu_history jsonb default '{}'::jsonb,
  onboarded    boolean default false,
  updated_at   timestamptz default now()
);

-- Migraciones: agregan columnas nuevas sin borrar nada si la tabla ya existía
alter table public.user_data add column if not exists nivel text default 'principiante';
alter table public.user_data add column if not exists theme text;
alter table public.user_data add column if not exists proteina jsonb;
alter table public.user_data add column if not exists menu_history jsonb default '{}'::jsonb;

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

-- ============================================================
-- FASE PILOTO (opcional): panel simple para entrenador/dueño de gimnasio
-- Todo esto es ADITIVO — no modifica ni reemplaza nada de lo anterior.
-- Solo corre este bloque cuando quieras activar el panel de entrenador.
-- ============================================================

-- Columnas nuevas (no afectan a los usuarios existentes; quedan en null/false por defecto)
alter table public.user_data add column if not exists gym_id text;
alter table public.user_data add column if not exists is_trainer boolean default false;
alter table public.user_data add column if not exists display_name text;

-- Funciones auxiliares: leen el gym_id / si-es-entrenador del usuario que hace la consulta,
-- evitando que la política de seguridad se referencie a sí misma (recursión).
create or replace function public.mi_gym_id()
returns text
language sql security definer stable
as $$
  select gym_id from public.user_data where user_id = auth.uid();
$$;

create or replace function public.soy_entrenador()
returns boolean
language sql security definer stable
as $$
  select coalesce(is_trainer, false) from public.user_data where user_id = auth.uid();
$$;

-- Política NUEVA y adicional: un entrenador puede ver (solo leer) las filas de su mismo
-- gimnasio. No le quita visibilidad a nadie más — las políticas de "select_own_data" etc.
-- siguen intactas; esta solo AMPLÍA quién puede ver qué, nunca restringe.
drop policy if exists "trainer_view_gym" on public.user_data;
create policy "trainer_view_gym"
  on public.user_data for select
  using ( public.soy_entrenador() and gym_id is not null and gym_id = public.mi_gym_id() );

-- Para activar a un usuario como entrenador de un gimnasio (hazlo manualmente desde
-- Table Editor, o corriendo esto reemplazando el correo y el nombre del gimnasio):
-- update public.user_data set is_trainer = true, gym_id = 'nombre-del-gym'
--   where user_id = (select id from auth.users where email = 'correo-del-entrenador@ejemplo.com');
--
-- Y para que un miembro aparezca en el panel de ese gimnasio, asígnale el mismo gym_id:
-- update public.user_data set gym_id = 'nombre-del-gym'
--   where user_id = (select id from auth.users where email = 'correo-del-miembro@ejemplo.com');
