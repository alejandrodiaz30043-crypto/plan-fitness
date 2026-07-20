-- ============================================================
-- Plan Fitness — esquema de base de datos para Supabase
-- Corre esto en: tu proyecto → SQL Editor → New query → Run
--
-- Versión simplificada: escrita a partir del estado real que ya tenía tu base
-- de datos (FASE PILOTO + FASE 2 ya aplicadas), sin el historial de migración
-- que ya no hace falta. Sigue siendo segura de volver a correr cuantas veces
-- quieras — no borra ni duplica nada.
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- Tabla: progreso individual de cada usuario ----------
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
  display_name text,
  role         text default 'member',
  gym_id       uuid,
  updated_at   timestamptz default now()
);

-- Por si tu tabla ya existía sin alguna de estas columnas (no afecta filas existentes)
alter table public.user_data add column if not exists nivel text default 'principiante';
alter table public.user_data add column if not exists theme text;
alter table public.user_data add column if not exists proteina jsonb;
alter table public.user_data add column if not exists menu_history jsonb default '{}'::jsonb;
alter table public.user_data add column if not exists display_name text;
alter table public.user_data add column if not exists role text default 'member';
alter table public.user_data add column if not exists gym_id uuid;

alter table public.user_data enable row level security;

drop policy if exists "select_own_data" on public.user_data;
create policy "select_own_data" on public.user_data for select using (auth.uid() = user_id);

drop policy if exists "insert_own_data" on public.user_data;
create policy "insert_own_data" on public.user_data for insert with check (auth.uid() = user_id);

drop policy if exists "update_own_data" on public.user_data;
create policy "update_own_data" on public.user_data for update using (auth.uid() = user_id);

drop policy if exists "delete_own_data" on public.user_data;
create policy "delete_own_data" on public.user_data for delete using (auth.uid() = user_id);

-- ---------- Tabla: gimnasios ----------
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

-- El dueño solo puede LEER su gimnasio; cualquier cambio real (nombre, límite, plan)
-- pasa por funciones RPC validadas en el servidor, nunca directo desde el cliente
-- (evita que alguien se suba su propio límite de miembros abriendo la consola del navegador).
drop policy if exists "owner_manage_gym" on public.gyms;
drop policy if exists "owner_view_gym" on public.gyms;
create policy "owner_view_gym"
  on public.gyms for select
  using (owner_id = auth.uid());

-- ---------- Funciones auxiliares para las políticas de seguridad ----------
-- (drop defensivo: por si tu base tuviera una versión de estas funciones con un tipo
-- de retorno distinto de alguna corrida muy vieja — así funciona sin importar tu punto de partida)
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

-- Un entrenador/dueño puede ver (solo leer) las filas de su mismo gimnasio.
-- No le quita visibilidad a nadie más — solo AMPLÍA quién puede ver qué.
drop policy if exists "trainer_view_gym" on public.user_data;
create policy "trainer_view_gym"
  on public.user_data for select
  using ( public.soy_entrenador() and gym_id is not null and gym_id = public.mi_gym_id() );

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

-- ---------- Funciones self-service: crear/unirse/gestionar un gimnasio ----------

-- Crear un gimnasio nuevo (rechaza si ya perteneces a uno, para no perder tu
-- membresía anterior sin darte cuenta)
create or replace function public.crear_gym(p_nombre text)
returns table(id uuid, nombre text, codigo_invitacion text)
language plpgsql security definer
as $$
declare
  v_id uuid;
  v_codigo text;
  v_caller_gym uuid;
begin
  select gym_id into v_caller_gym from public.user_data where user_id = auth.uid();
  if v_caller_gym is not null then
    raise exception 'Ya perteneces a un gimnasio. Sal de él antes de crear uno nuevo.';
  end if;

  v_codigo := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  insert into public.gyms (nombre, codigo_invitacion, owner_id)
  values (p_nombre, v_codigo, auth.uid())
  returning gyms.id into v_id;

  update public.user_data set gym_id = v_id, role = 'owner' where user_id = auth.uid();

  return query select v_id, p_nombre, v_codigo;
end;
$$;

-- Unirse a un gimnasio con un código de invitación (respeta el límite de
-- miembros y evita que el dueño de un gimnasio se una a otro por accidente)
create or replace function public.unirse_a_gym(p_codigo text)
returns table(id uuid, nombre text)
language plpgsql security definer
as $$
declare
  v_gym record;
  v_total int;
  v_caller_role text;
begin
  select role into v_caller_role from public.user_data where user_id = auth.uid();
  if v_caller_role = 'owner' then
    raise exception 'Eres dueño de un gimnasio — no puedes unirte a otro con un código. Contáctanos si necesitas ayuda.';
  end if;
  if v_caller_role = 'trainer' then
    raise exception 'Eres entrenador de un gimnasio — no puedes unirte a otro con un código. Sal de tu gimnasio actual primero si quieres cambiarte.';
  end if;

  select * into v_gym from public.gyms where codigo_invitacion = upper(p_codigo);
  if not found then
    raise exception 'Código de invitación no válido';
  end if;

  if v_gym.limite_miembros is not null then
    select count(*) into v_total from public.user_data where gym_id = v_gym.id;
    if v_total >= v_gym.limite_miembros then
      raise exception 'Este gimnasio alcanzó su límite de miembros. Contacta al dueño.';
    end if;
  end if;

  update public.user_data set gym_id = v_gym.id, role = 'member' where user_id = auth.uid();
  return query select v_gym.id, v_gym.nombre;
end;
$$;

-- El dueño puede ascender a un miembro de su propio gimnasio a "trainer"
create or replace function public.promover_entrenador(p_member_id uuid)
returns boolean
language plpgsql security definer
as $$
declare
  v_caller_role text; v_caller_gym uuid; v_target_gym uuid;
begin
  select role, gym_id into v_caller_role, v_caller_gym from public.user_data where user_id = auth.uid();
  if v_caller_role is distinct from 'owner' or v_caller_gym is null then
    raise exception 'Solo el dueño del gimnasio puede hacer esto';
  end if;
  if p_member_id = auth.uid() then
    raise exception 'No puedes cambiar tu propio rol de dueño';
  end if;
  select gym_id into v_target_gym from public.user_data where user_id = p_member_id;
  if v_target_gym is null or v_target_gym is distinct from v_caller_gym then
    raise exception 'Ese usuario no pertenece a tu gimnasio';
  end if;
  update public.user_data set role = 'trainer' where user_id = p_member_id;
  return true;
end;
$$;

-- El dueño puede regresar a un entrenador a "member" (sin sacarlo del gimnasio)
create or replace function public.degradar_a_miembro(p_member_id uuid)
returns boolean
language plpgsql security definer
as $$
declare
  v_caller_role text; v_caller_gym uuid; v_target_gym uuid; v_target_role text;
begin
  select role, gym_id into v_caller_role, v_caller_gym from public.user_data where user_id = auth.uid();
  if v_caller_role is distinct from 'owner' or v_caller_gym is null then
    raise exception 'Solo el dueño del gimnasio puede hacer esto';
  end if;
  select gym_id, role into v_target_gym, v_target_role from public.user_data where user_id = p_member_id;
  if v_target_gym is null or v_target_gym is distinct from v_caller_gym then
    raise exception 'Ese usuario no pertenece a tu gimnasio';
  end if;
  if v_target_role = 'owner' then
    raise exception 'No puedes cambiar el rol del dueño desde aquí';
  end if;
  update public.user_data set role = 'member' where user_id = p_member_id;
  return true;
end;
$$;

-- El dueño puede expulsar a un miembro (lo saca del gimnasio por completo;
-- la cuenta y el progreso de esa persona no se tocan, solo deja de pertenecer al gym)
create or replace function public.expulsar_miembro(p_member_id uuid)
returns boolean
language plpgsql security definer
as $$
declare
  v_caller_role text; v_caller_gym uuid; v_target_gym uuid; v_target_role text;
begin
  select role, gym_id into v_caller_role, v_caller_gym from public.user_data where user_id = auth.uid();
  if v_caller_role is distinct from 'owner' or v_caller_gym is null then
    raise exception 'Solo el dueño del gimnasio puede hacer esto';
  end if;
  select gym_id, role into v_target_gym, v_target_role from public.user_data where user_id = p_member_id;
  if v_target_gym is null or v_target_gym is distinct from v_caller_gym then
    raise exception 'Ese usuario no pertenece a tu gimnasio';
  end if;
  if v_target_role = 'owner' then
    raise exception 'El dueño no puede expulsarse a sí mismo';
  end if;
  update public.user_data set gym_id = null, role = 'member' where user_id = p_member_id;
  return true;
end;
$$;

-- Cualquier miembro o entrenador puede salir de su gimnasio por su cuenta
-- (el dueño no puede usar esto — evita dejar un gimnasio sin dueño)
create or replace function public.salir_de_gym()
returns boolean
language plpgsql security definer
as $$
declare
  v_role text;
begin
  select role into v_role from public.user_data where user_id = auth.uid();
  if v_role is null then
    raise exception 'No perteneces a ningún gimnasio';
  end if;
  if v_role = 'owner' then
    raise exception 'Eres el dueño de este gimnasio — no puedes salir así. Contáctanos para transferir la propiedad.';
  end if;
  update public.user_data set gym_id = null, role = 'member' where user_id = auth.uid();
  return true;
end;
$$;

-- Borra todos los datos de la app del usuario que llama (calendario, racha, check-ins,
-- notas, plan de nutrición). No borra la cuenta de acceso (auth.users) en sí — eso
-- requiere privilegios de servidor que una función de base de datos normal no tiene;
-- para borrarla también, hazlo manualmente desde Supabase → Authentication → Users,
-- o automatízalo más adelante con una Edge Function.
create or replace function public.eliminar_mis_datos()
returns boolean
language plpgsql security definer
as $$
declare
  v_role text;
begin
  select role into v_role from public.user_data where user_id = auth.uid();
  if v_role = 'owner' then
    raise exception 'Eres dueño de un gimnasio — contáctanos para transferir la propiedad antes de eliminar tu cuenta.';
  end if;
  delete from public.user_data where user_id = auth.uid();
  return true;
end;
$$;
