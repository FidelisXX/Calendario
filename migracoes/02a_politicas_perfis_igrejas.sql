-- ============================================================
--  MIGRAÇÃO 02a — Políticas de igrejas e profiles
-- ============================================================
--  Pode rodar com o front antigo no ar: ele não usa estas tabelas.
--  Permite testar o novo front (login pelo Supabase Auth, seletor de
--  igreja, gestão de usuários) antes de ligar o RLS nas tabelas de
--  dados com a migração 02.
--
--  São as mesmas políticas das seções 1 e 2 da migração 02, que as
--  recria de novo ao rodar (idempotente).
-- ============================================================

begin;

do $$
declare
  t text;
  p record;
begin
  foreach t in array array['igrejas', 'profiles'] loop
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t loop
      execute format('drop policy %I on public.%I', p.policyname, t);
    end loop;
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

-- IGREJAS — pastor e admin criam/editam; só admin exclui
create policy igrejas_ler    on public.igrejas for select to authenticated
  using (public.eh_global() or id = public.minha_igreja());
create policy igrejas_criar  on public.igrejas for insert to authenticated
  with check (public.eh_global());
create policy igrejas_editar on public.igrejas for update to authenticated
  using (public.eh_global()) with check (public.eh_global());
create policy igrejas_apagar on public.igrejas for delete to authenticated
  using (public.app_role() = 'admin');

-- PROFILES — cada um vê o próprio e os da sua igreja; pastor/admin veem todos
create policy profiles_ler    on public.profiles for select to authenticated
  using (id = auth.uid() or public.eh_global()
         or (igreja_id is not null and igreja_id = public.minha_igreja()));
create policy profiles_editar on public.profiles for update to authenticated
  using (id = auth.uid() or public.eh_global())
  with check (id = auth.uid() or public.eh_global());
create policy profiles_apagar on public.profiles for delete to authenticated
  using (public.eh_global() and id <> auth.uid());

commit;
