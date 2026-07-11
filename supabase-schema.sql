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
drop policy if exists "select_own_data" on public.user_data;
create policy "select_own_data"
  on public.user_data for select
  using (auth.uid() = user_id);

-- Cada usuario solo puede crear su propia fila
drop policy if exists "insert_own_data" on public.user_data;
create policy "insert_own_data"
  on public.user_data for insert
  with check (auth.uid() = user_id);

-- Cada usuario solo puede actualizar su propia fila
drop policy if exists "update_own_data" on public.user_data;
create policy "update_own_data"
  on public.user_data for update
  using (auth.uid() = user_id);

-- (Opcional pero recomendado) cada usuario puede borrar su propia fila
drop policy if exists "delete_own_data" on public.user_data;
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

-- ============================================================
-- FASE 2 (opcional): gimnasios self-service, con código de invitación
-- Reemplaza el mecanismo manual de la FASE PILOTO (is_trainer + gym_id de texto)
-- por gimnasios reales, con dueño, código de invitación y roles.
-- Es SEGURA de correr aunque ya hayas usado la FASE PILOTO: migra tus datos
-- existentes automáticamente, sin borrar nada (el gym_id de texto queda
-- archivado en "gym_id_legacy_text" por si acaso).
-- ============================================================

create extension if not exists pgcrypto;

-- 1) Tabla de gimnasios
create table if not exists public.gyms (
  id                uuid primary key default gen_random_uuid(),
  nombre            text not null,
  codigo_invitacion text unique not null,
  owner_id          uuid references auth.users(id) on delete set null,
  plan              text default 'piloto',
  limite_miembros   int,
  created_at        timestamptz default now()
);
alter table public.gyms enable row level security;
drop policy if exists "owner_manage_gym" on public.gyms;
create policy "owner_manage_gym"
  on public.gyms for all
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- 2) Columna "role" — reemplaza a is_trainer (member / trainer / owner)
alter table public.user_data add column if not exists role text default 'member';
update public.user_data set role = 'owner' where is_trainer = true and role = 'member';
update public.user_data set role = 'member' where role is null;

-- 3) Archivar el gym_id de texto viejo (si existía) y crear el nuevo, como referencia real a gyms
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='user_data' and column_name='gym_id'
               and data_type <> 'uuid') then
    alter table public.user_data rename column gym_id to gym_id_legacy_text;
  end if;
end $$;
alter table public.user_data add column if not exists gym_id uuid references public.gyms(id);

-- 4) Migrar cada gym_id_legacy_text (texto libre de la fase piloto) a un gimnasio real,
--    preservando qué usuarios pertenecían a cuál "gimnasio"
do $$
declare
  r record;
  v_gym_id uuid;
  v_codigo text;
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='user_data' and column_name='gym_id_legacy_text') then
    for r in
      select distinct gym_id_legacy_text
      from public.user_data
      where gym_id_legacy_text is not null and gym_id is null
    loop
      select id into v_gym_id from public.gyms where nombre = r.gym_id_legacy_text limit 1;
      if v_gym_id is null then
        v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
        select user_id into v_gym_id from public.user_data
          where gym_id_legacy_text = r.gym_id_legacy_text and role = 'owner' limit 1;
        if v_gym_id is not null then
          insert into public.gyms (nombre, codigo_invitacion, owner_id)
          values (r.gym_id_legacy_text, v_codigo, v_gym_id)
          returning id into v_gym_id;
        else
          insert into public.gyms (nombre, codigo_invitacion)
          values (r.gym_id_legacy_text, v_codigo)
          returning id into v_gym_id;
        end if;
      end if;
      update public.user_data set gym_id = v_gym_id where gym_id_legacy_text = r.gym_id_legacy_text;
    end loop;
  end if;
end $$;

-- 5) Funciones self-service
create or replace function public.crear_gym(p_nombre text)
returns table(id uuid, nombre text, codigo_invitacion text)
language plpgsql security definer
as $$
declare
  v_id uuid;
  v_codigo text;
begin
  v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into public.gyms (nombre, codigo_invitacion, owner_id)
  values (p_nombre, v_codigo, auth.uid())
  returning gyms.id into v_id;

  update public.user_data set gym_id = v_id, role = 'owner' where user_id = auth.uid();

  return query select v_id, p_nombre, v_codigo;
end;
$$;

create or replace function public.unirse_a_gym(p_codigo text)
returns table(id uuid, nombre text)
language plpgsql security definer
as $$
declare
  v_gym record;
begin
  select * into v_gym from public.gyms where codigo_invitacion = upper(p_codigo);
  if not found then
    raise exception 'Código de invitación no válido';
  end if;
  update public.user_data set gym_id = v_gym.id, role = 'member' where user_id = auth.uid();
  return query select v_gym.id, v_gym.nombre;
end;
$$;

-- Info del gimnasio del usuario que hace la consulta (segura, no expone otras filas)
create or replace function public.mi_gym_info()
returns table(gym_id uuid, nombre text, codigo_invitacion text, role text)
language sql security definer stable
as $$
  select g.id, g.nombre, g.codigo_invitacion, u.role
  from public.user_data u
  left join public.gyms g on g.id = u.gym_id
  where u.user_id = auth.uid();
$$;

-- 6) Actualizar las funciones/política de visibilidad del entrenador para usar "role" + gym_id (uuid)
-- (mi_gym_id cambia su tipo de "text" a "uuid", así que hay que borrarla primero;
--  CASCADE también borra la política vieja que dependía de ella, la cual se vuelve a crear más abajo)
drop function if exists public.mi_gym_id() cascade;
drop function if exists public.soy_entrenador() cascade;

create or replace function public.mi_gym_id()
returns uuid
language sql security definer stable
as $$
  select gym_id from public.user_data where user_id = auth.uid();
$$;

create or replace function public.soy_entrenador()
returns boolean
language sql security definer stable
as $$
  select coalesce(role in ('trainer','owner'), false) from public.user_data where user_id = auth.uid();
$$;

drop policy if exists "trainer_view_gym" on public.user_data;
create policy "trainer_view_gym"
  on public.user_data for select
  using ( public.soy_entrenador() and gym_id is not null and gym_id = public.mi_gym_id() );
