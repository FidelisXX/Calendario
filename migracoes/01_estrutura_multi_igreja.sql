-- ============================================================
--  MIGRAÇÃO 01 — Estrutura multi-igreja
-- ============================================================
--  Pode ser executada com o sistema atual no ar: NÃO liga RLS nas
--  tabelas existentes (só nas novas igrejas/profiles) e
--  NÃO quebra o front antigo (igreja_id ganha DEFAULT = IBCJ, então
--  inserts antigos continuam funcionando).
--
--  O que faz:
--    1. Cria a tabela igrejas e cadastra a IBCJ (tag 'ibcj')
--    2. Cria profiles (perfil do usuário, ligado ao Supabase Auth)
--    3. Cria funções auxiliares usadas pelas políticas de RLS
--    4. Adiciona igreja_id em todas as tabelas de dados e marca
--       todos os registros existentes como IBCJ
--    5. Triggers que derivam igreja_id do ministério / evento
--
--  Idempotente: pode ser executada mais de uma vez.
--  Executar no Supabase → SQL Editor, depois de fazer BACKUP.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. IGREJAS (tags)
-- ------------------------------------------------------------
create table if not exists public.igrejas (
  id          uuid        primary key default gen_random_uuid(),
  tag         text        not null unique check (tag ~ '^[a-z0-9-]{2,30}$'),
  nome        text        not null,
  logo_url    text,
  created_by  uuid        references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

insert into public.igrejas (tag, nome)
values ('ibcj', 'Igreja Batista Central do Jordão')
on conflict (tag) do nothing;


-- ------------------------------------------------------------
-- 2. PROFILES (substitui ibcj_users)
-- ------------------------------------------------------------
--  admin / pastor → enxergam todas as igrejas (igreja_id pode ser nulo)
--  secretaria / lider → só a igreja de igreja_id
--  igreja_id nulo em secretaria/lider = "aguardando liberação"
create table if not exists public.profiles (
  id          uuid        primary key references auth.users(id) on delete cascade,
  name        text        not null default '',
  email       text        not null unique,
  role        text        not null default 'lider'
                          check (role in ('admin','pastor','secretaria','lider')),
  igreja_id   uuid        references public.igrejas(id) on delete set null,
  legacy_id   text        unique,             -- id antigo em ibcj_users
  created_at  timestamptz not null default now()
);

create index if not exists idx_profiles_igreja on public.profiles(igreja_id);

-- RLS ligado já agora (sem políticas = ninguém acessa pela anon key).
-- O front atual não usa estas tabelas; o script de importação usa a
-- service_role, que ignora RLS. As políticas são criadas na migração 02.
alter table public.igrejas  enable row level security;
alter table public.profiles enable row level security;

-- Todo usuário novo do Supabase Auth ganha um perfil 'lider' sem igreja.
-- O papel NUNCA vem dos metadados do cadastro (o usuário controla esses dados).
create or replace function public.criar_perfil_novo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name, email)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', ''), lower(new.email))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.criar_perfil_novo_usuario();


-- ------------------------------------------------------------
-- 3. FUNÇÕES AUXILIARES (usadas pelas políticas da migração 02)
-- ------------------------------------------------------------
create or replace function public.app_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.minha_igreja()
returns uuid language sql stable security definer set search_path = public as $$
  select igreja_id from public.profiles where id = auth.uid()
$$;

create or replace function public.meu_email()
returns text language sql stable as $$
  select lower(coalesce(auth.jwt() ->> 'email', ''))
$$;

-- admin e pastor enxergam todas as igrejas
create or replace function public.eh_global()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.app_role() in ('admin','pastor'), false)
$$;

create or replace function public.pode_acessar(ig uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select ig is not null and (public.eh_global() or ig = public.minha_igreja())
$$;

-- equivalente a canApprove()/canDelete() do front, mas restrito à igreja
create or replace function public.eh_gestor(ig uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.pode_acessar(ig)
     and coalesce(public.app_role() in ('admin','pastor','secretaria'), false)
$$;

-- Impede que usuários comuns alterem o próprio papel/igreja.
-- SECURITY INVOKER de propósito: current_user precisa ser o papel de quem chamou.
create or replace function public.proteger_perfil()
returns trigger language plpgsql as $$
begin
  -- SQL Editor (postgres) e scripts com service_role passam direto
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if new.id is distinct from old.id or new.email is distinct from old.email then
    raise exception 'O e-mail é gerenciado pelo login e não pode ser alterado aqui';
  end if;
  if (new.role, new.igreja_id) is distinct from (old.role, old.igreja_id) then
    if not public.eh_global() then
      raise exception 'Sem permissão para alterar papel ou igreja';
    end if;
    if (new.role = 'admin' or old.role = 'admin') and public.app_role() <> 'admin' then
      raise exception 'Apenas admin pode conceder ou remover o papel admin';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists trg_proteger_perfil on public.profiles;
create trigger trg_proteger_perfil
  before update on public.profiles
  for each row execute function public.proteger_perfil();


-- ------------------------------------------------------------
-- 4. igreja_id EM TODAS AS TABELAS DE DADOS
-- ------------------------------------------------------------
--  O DEFAULT = IBCJ é temporário (mantém o front antigo funcionando)
--  e é removido na migração 02.
do $$
declare
  ibcj uuid := (select id from public.igrejas where tag = 'ibcj');
  t    text;
begin
  foreach t in array array[
    'ibcj_events', 'ibcj_liturgias', 'ibcj_agenda', 'ibcj_diaconal',
    'ibcj_ministerios', 'ibcj_ministerio_members', 'ibcj_financial_reports',
    'ibcj_registros', 'ibcj_gabinete_notes', 'ibcj_membros',
    'ibcj_reuniao_admin_reports', 'ibcj_culto_reports',
    'ibcj_notas'  -- tabela antiga de notas por evento (não usada pelo front atual)
  ] loop
    if to_regclass('public.' || t) is null then
      raise notice 'Tabela % não existe — ignorada', t;
      continue;
    end if;
    execute format('alter table public.%I add column if not exists igreja_id uuid references public.igrejas(id)', t);
    execute format('update public.%I set igreja_id = %L where igreja_id is null', t, ibcj);
    execute format('alter table public.%I alter column igreja_id set default %L', t, ibcj);
    execute format('alter table public.%I alter column igreja_id set not null', t);
    execute format('create index if not exists %I on public.%I (igreja_id)', 'idx_' || t || '_igreja', t);
  end loop;
end $$;


-- ------------------------------------------------------------
-- 5. igreja_id DERIVADO (garante consistência e o front não precisa enviar)
-- ------------------------------------------------------------
-- Registros ligados a um ministério herdam a igreja do ministério
create or replace function public.herdar_igreja_do_ministerio()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.igreja_id := (select igreja_id from public.ibcj_ministerios where id = new.ministerio_id);
  return new;
end $$;

-- Registros ligados a um evento herdam a igreja do evento (quando houver evento)
create or replace function public.herdar_igreja_do_evento()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.event_id is not null then
    new.igreja_id := coalesce(
      (select igreja_id from public.ibcj_events where id = new.event_id),
      new.igreja_id);
  end if;
  return new;
end $$;

do $$
declare
  t text;
begin
  foreach t in array array['ibcj_ministerio_members', 'ibcj_financial_reports', 'ibcj_registros'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('drop trigger if exists trg_igreja_ministerio on public.%I', t);
    execute format('create trigger trg_igreja_ministerio before insert or update of ministerio_id, igreja_id
                    on public.%I for each row execute function public.herdar_igreja_do_ministerio()', t);
  end loop;

  -- Só tabelas que realmente têm a coluna event_id no banco
  for t in
    select table_name from information_schema.columns
    where table_schema = 'public' and column_name = 'event_id'
      and table_name in ('ibcj_gabinete_notes', 'ibcj_culto_reports', 'ibcj_reuniao_admin_reports',
                         'ibcj_diaconal', 'ibcj_liturgias', 'ibcj_notas')
  loop
    execute format('drop trigger if exists trg_igreja_evento on public.%I', t);
    execute format('create trigger trg_igreja_evento before insert or update of event_id, igreja_id
                    on public.%I for each row execute function public.herdar_igreja_do_evento()', t);
  end loop;
end $$;

commit;

-- Conferência: todas as linhas devem estar na IBCJ
-- select 'ibcj_events' t, count(*) from ibcj_events where igreja_id is null
-- union all select 'ibcj_membros', count(*) from ibcj_membros where igreja_id is null;
