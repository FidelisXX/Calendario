-- ============================================================
--  MIGRAÇÃO 03 — Rodapé padrão por igreja
-- ============================================================
--  Endereço / CNPJ / pastor usados como rodapé inicial de novas
--  liturgias, escalas diaconais e agendas. Editável em
--  "Configuração" (pastor/admin — política igrejas_editar).
--
--  Independente das outras: pode rodar antes ou depois da 02.
--  Idempotente.
-- ============================================================

begin;

alter table public.igrejas add column if not exists rodape text;

-- IBCJ: rodapé que estava fixo no código (só se ainda estiver vazio)
update public.igrejas
set rodape = E'Rua Emílio Monteiro Fonseca, 1368 - Ibura, Recife - PE,\nCEP 51240-490  CNPJ 02.783.591/0001-46\nPr. Pres. Lucas Wayney Bezerra'
where id = '921a5810-1f64-4033-b5db-61ccb626ae90' and rodape is null;

commit;
