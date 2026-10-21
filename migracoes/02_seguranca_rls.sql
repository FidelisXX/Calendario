-- ============================================================
--  MIGRAÇÃO 02 — Segurança: RLS por igreja e por papel
-- ============================================================
--  ATENÇÃO: QUEBRA O FRONT ANTIGO. A partir daqui a anon key não lê
--  nem grava mais nada; só usuários logados pelo Supabase Auth, e cada
--  um só vê a própria igreja. Rodar JUNTO com o deploy do novo front.
--
--  Pré-requisitos: migração 01 + importar_usuarios.mjs executados.
--
--  As regras reproduzem as que hoje existem só no JavaScript
--  (canApprove, canDelete, canSeeGabinete, canSeeNotes, canEditRegistros,
--  fluxo pendente/aprovado do líder, compartilhamento de ministérios).
--
--  Idempotente: remove e recria as políticas destas tabelas.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 0. Limpa políticas antigas destas tabelas e liga RLS
-- ------------------------------------------------------------
do $$
declare
  t text;
  p record;
begin
  foreach t in array array[
    'igrejas', 'profiles',
    'ibcj_events', 'ibcj_liturgias', 'ibcj_agenda', 'ibcj_diaconal',
    'ibcj_ministerios', 'ibcj_ministerio_members', 'ibcj_financial_reports',
    'ibcj_registros', 'ibcj_gabinete_notes', 'ibcj_membros',
    'ibcj_reuniao_admin_reports', 'ibcj_culto_reports', 'ibcj_notas'
  ] loop
    if to_regclass('public.' || t) is null then continue; end if;
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    -- remove o DEFAULT = IBCJ da migração 01: o front passa a enviar igreja_id
    if t not in ('igrejas', 'profiles') then
      execute format('alter table public.%I alter column igreja_id drop default', t);
    end if;
  end loop;
end $$;


-- ------------------------------------------------------------
-- 1. IGREJAS — pastor e admin criam/editam; só admin exclui
-- ------------------------------------------------------------
create policy igrejas_ler    on public.igrejas for select to authenticated
  using (public.eh_global() or id = public.minha_igreja());
create policy igrejas_criar  on public.igrejas for insert to authenticated
  with check (public.eh_global());
create policy igrejas_editar on public.igrejas for update to authenticated
  using (public.eh_global()) with check (public.eh_global());
create policy igrejas_apagar on public.igrejas for delete to authenticated
  using (public.app_role() = 'admin');


-- ------------------------------------------------------------
-- 2. PROFILES — cada um vê o próprio e os da sua igreja;
--    pastor/admin veem todos e atribuem tags (trigger proteger_perfil
--    impede que outros mudem papel/igreja). Insert só via trigger do Auth.
-- ------------------------------------------------------------
create policy profiles_ler    on public.profiles for select to authenticated
  using (id = auth.uid() or public.eh_global()
         or (igreja_id is not null and igreja_id = public.minha_igreja()));
create policy profiles_editar on public.profiles for update to authenticated
  using (id = auth.uid() or public.eh_global())
  with check (id = auth.uid() or public.eh_global());
create policy profiles_apagar on public.profiles for delete to authenticated
  using (public.eh_global() and id <> auth.uid());


-- ------------------------------------------------------------
-- 3. EVENTOS — aprovados são visíveis à igreja; líder vê/edita só os
--    próprios pendentes; categoria Gabinete só para gestores
-- ------------------------------------------------------------
create policy eventos_ler on public.ibcj_events for select to authenticated
  using (public.pode_acessar(igreja_id)
         and (category is distinct from 'Gabinete' or public.eh_gestor(igreja_id))
         and (status = 'aprovado' or public.eh_gestor(igreja_id)
              or lower(created_by) = public.meu_email()));
create policy eventos_criar on public.ibcj_events for insert to authenticated
  with check (public.eh_gestor(igreja_id)
              or (public.pode_acessar(igreja_id) and status = 'pendente'
                  and lower(created_by) = public.meu_email()));
create policy eventos_editar on public.ibcj_events for update to authenticated
  using      (public.eh_gestor(igreja_id) or (status = 'pendente' and lower(created_by) = public.meu_email()))
  with check (public.eh_gestor(igreja_id)
              or (public.pode_acessar(igreja_id) and status = 'pendente'
                  and lower(created_by) = public.meu_email()));
create policy eventos_apagar on public.ibcj_events for delete to authenticated
  using (public.eh_gestor(igreja_id));


-- ------------------------------------------------------------
-- 4. LITURGIAS, AGENDA, DIACONAL — mesmo fluxo de aprovação, mas o
--    líder só enxerga os que ele mesmo criou (como no front atual)
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['ibcj_liturgias', 'ibcj_agenda', 'ibcj_diaconal'] loop
    execute format($p$create policy ler on public.%I for select to authenticated
      using (public.eh_gestor(igreja_id)
             or (public.pode_acessar(igreja_id) and lower(created_by) = public.meu_email()))$p$, t);
    execute format($p$create policy criar on public.%I for insert to authenticated
      with check (public.eh_gestor(igreja_id)
                  or (public.pode_acessar(igreja_id) and status = 'pendente'
                      and lower(created_by) = public.meu_email()))$p$, t);
    execute format($p$create policy editar on public.%I for update to authenticated
      using      (public.eh_gestor(igreja_id) or (status = 'pendente' and lower(created_by) = public.meu_email()))
      with check (public.eh_gestor(igreja_id)
                  or (public.pode_acessar(igreja_id) and status = 'pendente'
                      and lower(created_by) = public.meu_email()))$p$, t);
    execute format($p$create policy apagar on public.%I for delete to authenticated
      using (public.eh_gestor(igreja_id) or (status = 'pendente' and lower(created_by) = public.meu_email()))$p$, t);
  end loop;
end $$;


-- ------------------------------------------------------------
-- 5. MINISTÉRIOS — gestores veem todos da igreja; líder vê os que criou
--    e os compartilhados com ele (ibcj_ministerio_members)
-- ------------------------------------------------------------
-- SECURITY DEFINER evita recursão entre as políticas de ministérios e membros
create or replace function public.acessa_ministerio(min_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.ibcj_ministerios m
    where m.id = min_id
      and public.pode_acessar(m.igreja_id)
      and (public.eh_gestor(m.igreja_id)
           or lower(m.created_by) = public.meu_email()
           or exists (select 1 from public.ibcj_ministerio_members mm
                      where mm.ministerio_id = m.id and lower(mm.user_email) = public.meu_email())))
$$;

create or replace function public.dono_ministerio(min_id text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.ibcj_ministerios m
    where m.id = min_id
      and (public.eh_gestor(m.igreja_id)
           or (public.pode_acessar(m.igreja_id) and lower(m.created_by) = public.meu_email())))
$$;

create policy ler on public.ibcj_ministerios for select to authenticated
  using (public.acessa_ministerio(id));
create policy criar on public.ibcj_ministerios for insert to authenticated
  with check (public.pode_acessar(igreja_id) and lower(created_by) = public.meu_email());
create policy editar on public.ibcj_ministerios for update to authenticated
  using (public.dono_ministerio(id)) with check (public.pode_acessar(igreja_id));
create policy apagar on public.ibcj_ministerios for delete to authenticated
  using (public.eh_gestor(igreja_id));

-- Compartilhamento: quem acessa vê; só o dono (ou gestor) adiciona/remove
create policy ler on public.ibcj_ministerio_members for select to authenticated
  using (public.acessa_ministerio(ministerio_id));
create policy criar on public.ibcj_ministerio_members for insert to authenticated
  with check (public.dono_ministerio(ministerio_id));
create policy editar on public.ibcj_ministerio_members for update to authenticated
  using (public.dono_ministerio(ministerio_id)) with check (public.dono_ministerio(ministerio_id));
create policy apagar on public.ibcj_ministerio_members for delete to authenticated
  using (public.dono_ministerio(ministerio_id));

-- Relatórios financeiros: quem acessa o ministério lê/cria/edita;
-- excluir só gestor ou quem criou o relatório
create policy ler on public.ibcj_financial_reports for select to authenticated
  using (public.acessa_ministerio(ministerio_id));
create policy criar on public.ibcj_financial_reports for insert to authenticated
  with check (public.acessa_ministerio(ministerio_id));
create policy editar on public.ibcj_financial_reports for update to authenticated
  using (public.acessa_ministerio(ministerio_id)) with check (public.acessa_ministerio(ministerio_id));
create policy apagar on public.ibcj_financial_reports for delete to authenticated
  using (public.eh_gestor(igreja_id) or lower(created_by) = public.meu_email());

-- Registros semanais: quem acessa lê/cria; editar/excluir = canEditRegistros()
create policy ler on public.ibcj_registros for select to authenticated
  using (public.acessa_ministerio(ministerio_id));
create policy criar on public.ibcj_registros for insert to authenticated
  with check (public.acessa_ministerio(ministerio_id));
create policy editar on public.ibcj_registros for update to authenticated
  using (public.eh_gestor(igreja_id)) with check (public.eh_gestor(igreja_id));
create policy apagar on public.ibcj_registros for delete to authenticated
  using (public.eh_gestor(igreja_id));


-- ------------------------------------------------------------
-- 6. NOTAS DO GABINETE — só pastor e admin (canSeeNotes)
-- ------------------------------------------------------------
create policy gabinete on public.ibcj_gabinete_notes for all to authenticated
  using (public.eh_global()) with check (public.eh_global());

-- ibcj_notas: tabela antiga de notas por evento, não usada pelo front atual
do $$
begin
  if to_regclass('public.ibcj_notas') is not null then
    create policy gabinete on public.ibcj_notas for all to authenticated
      using (public.eh_global()) with check (public.eh_global());
  end if;
end $$;


-- ------------------------------------------------------------
-- 7. MEMBROS, ATAS e RELATÓRIOS DE CULTO — só gestores da igreja
--    (ibcj_membros contém dados pessoais: telefone, endereço, nascimento)
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array['ibcj_membros', 'ibcj_reuniao_admin_reports', 'ibcj_culto_reports'] loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format($p$create policy gestores on public.%I for all to authenticated
      using (public.eh_gestor(igreja_id)) with check (public.eh_gestor(igreja_id))$p$, t);
  end loop;
end $$;


-- ------------------------------------------------------------
-- 8. TABELA ANTIGA DE USUÁRIOS — bloqueada (tinha senhas em texto puro)
-- ------------------------------------------------------------
--  Mantida por enquanto só para permitir rollback. Ver passo 10.
do $$
begin
  if to_regclass('public.ibcj_users') is not null then
    alter table public.ibcj_users rename to ibcj_users_legacy;
  end if;
end $$;
alter table if exists public.ibcj_users_legacy enable row level security;
revoke all on public.ibcj_users_legacy from anon, authenticated;


-- ------------------------------------------------------------
-- 9. STORAGE — bucket comprovantes deixa de ser público
-- ------------------------------------------------------------
--  Novos arquivos: comprovantes/<igreja_id>/<arquivo>
--  Arquivos antigos (pasta = e-mail do usuário) são considerados da IBCJ.
--  O front precisa passar a usar createSignedUrl() em vez de getPublicUrl().
create or replace function public.igreja_do_arquivo(caminho text)
returns uuid language sql stable security definer set search_path = public as $$
  select case
    when split_part(caminho, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then split_part(caminho, '/', 1)::uuid
    else (select id from public.igrejas where tag = 'ibcj')
  end
$$;

update storage.buckets set public = false where id = 'comprovantes';

do $$
declare
  p record;
begin
  -- remove políticas antigas que mencionem o bucket (ex.: liberações para anon)
  for p in
    select policyname from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and (coalesce(qual, '') ilike '%comprovantes%' or coalesce(with_check, '') ilike '%comprovantes%')
  loop
    execute format('drop policy %I on storage.objects', p.policyname);
  end loop;
end $$;

create policy comprovantes_ler on storage.objects for select to authenticated
  using (bucket_id = 'comprovantes' and public.pode_acessar(public.igreja_do_arquivo(name)));
create policy comprovantes_enviar on storage.objects for insert to authenticated
  with check (bucket_id = 'comprovantes' and public.pode_acessar(public.igreja_do_arquivo(name)));
create policy comprovantes_editar on storage.objects for update to authenticated
  using (bucket_id = 'comprovantes' and public.pode_acessar(public.igreja_do_arquivo(name)));
create policy comprovantes_apagar on storage.objects for delete to authenticated
  using (bucket_id = 'comprovantes' and public.eh_gestor(public.igreja_do_arquivo(name)));

commit;

-- Políticas de storage.objects que NÃO citam bucket nenhum continuam valendo
-- e podem liberar acesso. Confira se esta consulta retorna algo inesperado:
-- select policyname, roles, cmd, qual from pg_policies
-- where schemaname = 'storage' and tablename = 'objects';


-- ============================================================
-- 10. LIMPEZA (rodar só depois de 1–2 semanas sem problemas)
-- ============================================================
-- drop table public.ibcj_users_legacy;
