-- ============================================================
--  IBCJ GESTÃO — Script completo do banco de dados Supabase
--  Igreja Batista Central do Jordão
--  Gerado automaticamente a partir do sistema calendario.html
-- ============================================================
-- IMPORTANTE:
--   O sistema usa autenticação própria (tabela ibcj_users),
--   NÃO usa o Supabase Auth nativo (auth.uid()).
--   Por isso, o RLS é DESABILITADO em todas as tabelas.
--   As regras de acesso são controladas pelo próprio JavaScript.
-- ============================================================


-- ============================================================
-- 1. USUÁRIOS DO SISTEMA
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_users (
  id          TEXT        PRIMARY KEY,
  name        TEXT        NOT NULL,
  email       TEXT        NOT NULL UNIQUE,
  pw          TEXT        NOT NULL,           -- senha em texto simples (app-controlled)
  role        TEXT        NOT NULL DEFAULT 'lider',
                                              -- Valores: admin | pastor | secretaria | lider
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_users DISABLE ROW LEVEL SECURITY;

-- Índice para login por e-mail
CREATE INDEX IF NOT EXISTS idx_ibcj_users_email ON ibcj_users(email);


-- ============================================================
-- 2. EVENTOS DO CALENDÁRIO
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_events (
  id           TEXT        PRIMARY KEY,
  name         TEXT        NOT NULL,
  date         TEXT        NOT NULL,          -- formato ISO: '2025-01-15'
  start_time   TEXT,                          -- ex: '09:00'
  end_time     TEXT,                          -- ex: '11:00'
  category     TEXT,
    -- Valores comuns: Culto | Celebração da Ceia | Reunião |
    --   Reunião Administrativa | Acampamento | Aniversário |
    --   EBD | Jovens | Ensaio | Outro
  description  TEXT,
  recurrence   TEXT DEFAULT 'none',           -- none | monthly | yearly
  status       TEXT NOT NULL DEFAULT 'aprovado',
                                              -- aprovado | pendente | rejected
  created_by   TEXT,                          -- e-mail do criador
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_events DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_events_date   ON ibcj_events(date);
CREATE INDEX IF NOT EXISTS idx_ibcj_events_status ON ibcj_events(status);


-- ============================================================
-- 3. LITURGIAS
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_liturgias (
  id          TEXT        PRIMARY KEY,
  title       TEXT        NOT NULL,
  date        TEXT,                           -- ISO date
  time        TEXT,                           -- ex: '19:00'
  slogan      TEXT,
  footer      TEXT,
  items       JSONB       NOT NULL DEFAULT '[]',
    -- Array: [{desc, resp, sub, bold, italic}]
  status      TEXT        NOT NULL DEFAULT 'aprovado',
                                              -- aprovado | pendente | rejected
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_liturgias DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_liturgias_created_at ON ibcj_liturgias(created_at DESC);


-- ============================================================
-- 4. AGENDA SEMANAL
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_agenda (
  id          TEXT        PRIMARY KEY,
  title       TEXT        NOT NULL,
  date_start  TEXT,                           -- ISO date
  date_end    TEXT,                           -- ISO date
  slogan      TEXT,
  footer      TEXT,
  note        TEXT,                           -- lembrete / nota final
  days        JSONB       NOT NULL DEFAULT '[]',
    -- Array: [{date, label, items:[{time, desc, note, bullet, subs:[]}]}]
  status      TEXT        NOT NULL DEFAULT 'aprovado',
                                              -- aprovado | pendente | rejected
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_agenda DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_agenda_date_start ON ibcj_agenda(date_start);


-- ============================================================
-- 5. SERVIÇO DIACONAL
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_diaconal (
  id          TEXT        PRIMARY KEY,
  title       TEXT        NOT NULL,
  event_id    TEXT,                           -- referência opcional a ibcj_events
  date        TEXT,                           -- ISO date
  items       JSONB       NOT NULL DEFAULT '[]',
    -- Array: [{role, persons}]
  status      TEXT        NOT NULL DEFAULT 'aprovado',
                                              -- aprovado | pendente | rejected
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_diaconal DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_diaconal_created_at ON ibcj_diaconal(created_at DESC);


-- ============================================================
-- 6. MINISTÉRIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_ministerios (
  id          TEXT        PRIMARY KEY,
  name        TEXT        NOT NULL,
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_ministerios DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_ministerios_created_at ON ibcj_ministerios(created_at);


-- ============================================================
-- 7. MEMBROS DOS MINISTÉRIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_ministerio_members (
  id             TEXT        PRIMARY KEY,
  ministerio_id  TEXT        NOT NULL REFERENCES ibcj_ministerios(id) ON DELETE CASCADE,
  user_email     TEXT        NOT NULL,
  invited_by     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ministerio_id, user_email)
);

ALTER TABLE ibcj_ministerio_members DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_min_members_email      ON ibcj_ministerio_members(user_email);
CREATE INDEX IF NOT EXISTS idx_ibcj_min_members_ministerio ON ibcj_ministerio_members(ministerio_id);


-- ============================================================
-- 8. RELATÓRIOS FINANCEIROS (por ministério)
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_financial_reports (
  id             TEXT          PRIMARY KEY,
  ministerio_id  TEXT          NOT NULL REFERENCES ibcj_ministerios(id) ON DELETE CASCADE,
  period_start   TEXT          NOT NULL,      -- ISO date (início do período)
  period_end     TEXT,                        -- ISO date (fim do período)
  income_total   NUMERIC(12,2) NOT NULL DEFAULT 0,
  expense_total  NUMERIC(12,2) NOT NULL DEFAULT 0,
  items          JSONB         NOT NULL DEFAULT '[]',
    -- Array: [{type:'income'|'expense', desc, value, receipt_url}]
  notes          TEXT,
  created_by     TEXT,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_financial_reports DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_fin_ministerio    ON ibcj_financial_reports(ministerio_id);
CREATE INDEX IF NOT EXISTS idx_ibcj_fin_period_start  ON ibcj_financial_reports(period_start);


-- ============================================================
-- 9. REGISTROS SEMANAIS DE CULTO (por ministério)
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_registros (
  id                TEXT        PRIMARY KEY,
  ministerio_id     TEXT        NOT NULL REFERENCES ibcj_ministerios(id) ON DELETE CASCADE,
  data_culto        TEXT        NOT NULL,     -- ISO date
  dia_semana        TEXT,                     -- ex: 'Domingo', 'Quarta-feira'
  nome_culto        TEXT,                     -- ex: 'Culto de Celebração'
  presentes         INTEGER     NOT NULL DEFAULT 0,
  convertidos       INTEGER     NOT NULL DEFAULT 0,
  pregador          TEXT,
  texto_biblico     TEXT,
  diaconos_ausentes TEXT,
  lideres_ausentes  TEXT,
  talento           TEXT,
  observacao        TEXT,
  created_by        TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_registros DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_registros_ministerio  ON ibcj_registros(ministerio_id);
CREATE INDEX IF NOT EXISTS idx_ibcj_registros_data_culto  ON ibcj_registros(data_culto DESC);


-- ============================================================
-- 10. NOTAS PASTORAIS PRIVADAS (por evento)
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_gabinete_notes (
  id          BIGSERIAL   PRIMARY KEY,
  event_id    TEXT        NOT NULL UNIQUE,    -- uma nota por evento
  content     TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_gabinete_notes DISABLE ROW LEVEL SECURITY;

-- Política RLS (caso prefira habilitar no futuro):
-- CREATE POLICY "gabinete_notes_policy" ON ibcj_gabinete_notes
--   USING (true) WITH CHECK (true);


-- ============================================================
-- 11. LISTA DE MEMBROS DA IGREJA
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_membros (
  id              TEXT        PRIMARY KEY,
  nome            TEXT        NOT NULL,
  departamento    TEXT,
  telefone        TEXT,
  email           TEXT,
  data_nascimento TEXT,                       -- ISO date
  endereco        TEXT,
  observacoes     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_membros DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_membros_nome ON ibcj_membros(nome);


-- ============================================================
-- 12. RELATÓRIOS DE REUNIÃO ADMINISTRATIVA
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_reuniao_admin_reports (
  id                    TEXT        PRIMARY KEY,
  event_id              TEXT,                 -- referência opcional a ibcj_events
  data                  TEXT,                 -- ISO date da reunião
  pauta                 TEXT,
  presentes             TEXT,
  ausentes              TEXT,
  oracao_inicial        TEXT,
  relatorio_fin_igreja  TEXT,
  extraordinaria        BOOLEAN     NOT NULL DEFAULT FALSE,
  votacoes              JSONB       NOT NULL DEFAULT '[]',
    -- Array: [{assunto, votos_sim, votos_nao, abstencoes, resultado, obs}]
  created_by            TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_reuniao_admin_reports DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_rad_event_id  ON ibcj_reuniao_admin_reports(event_id);
CREATE INDEX IF NOT EXISTS idx_ibcj_rad_data       ON ibcj_reuniao_admin_reports(data DESC);


-- ============================================================
-- 13. RELATÓRIOS DE CULTO (detalhado por evento)
-- ============================================================
CREATE TABLE IF NOT EXISTS ibcj_culto_reports (
  id            TEXT        PRIMARY KEY,
  event_id      TEXT,                         -- referência opcional a ibcj_events
  presentes     INTEGER     NOT NULL DEFAULT 0,
  convertidos   INTEGER     NOT NULL DEFAULT 0,
  pregador      TEXT,
  texto_biblico TEXT,
  diaconos      TEXT,
  lideres       TEXT,
  talento       TEXT,
  observacao    TEXT,
  created_by    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ibcj_culto_reports DISABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ibcj_culto_reports_event_id ON ibcj_culto_reports(event_id);


-- ============================================================
-- 14. STORAGE BUCKET — COMPROVANTES FINANCEIROS
-- ============================================================
-- Execute no painel Supabase → Storage → New Bucket:
--   Nome: comprovantes
--   Public: SIM (para acesso às URLs públicas dos arquivos)
--
-- Ou via SQL (API do Supabase Storage):
INSERT INTO storage.buckets (id, name, public)
VALUES ('comprovantes', 'comprovantes', TRUE)
ON CONFLICT (id) DO NOTHING;

-- Políticas de storage (permitir tudo para usuários autenticados via app):
CREATE POLICY "allow_all_comprovantes"
  ON storage.objects FOR ALL
  USING (bucket_id = 'comprovantes')
  WITH CHECK (bucket_id = 'comprovantes');


-- ============================================================
-- RESUMO DAS TABELAS
-- ============================================================
--
--  Tabela                       | Descrição
--  -----------------------------|----------------------------------------
--  ibcj_users                   | Usuários do sistema (auth própria)
--  ibcj_events                  | Eventos do calendário anual
--  ibcj_liturgias               | Documentos de liturgia
--  ibcj_agenda                  | Agendas semanais
--  ibcj_diaconal                | Escalas do serviço diaconal
--  ibcj_ministerios             | Ministérios (grupos) da igreja
--  ibcj_ministerio_members      | Membros de cada ministério
--  ibcj_financial_reports       | Relatórios financeiros por ministério
--  ibcj_registros               | Registros semanais de presença/culto
--  ibcj_gabinete_notes          | Anotações pastorais privadas (por evento)
--  ibcj_membros                 | Cadastro de membros da igreja
--  ibcj_reuniao_admin_reports   | Atas de reuniões administrativas
--  ibcj_culto_reports           | Relatórios detalhados de culto
--  storage: comprovantes        | Bucket para comprovantes financeiros
--
-- ============================================================
-- ROLES DE USUÁRIO
-- ============================================================
--
--  Role         | Acesso
--  -------------|---------------------------------------------------
--  admin        | Acesso total, gestão de usuários
--  pastor       | Acesso a todas as abas, aprovação de pendentes,
--               | notas pastorais privadas (gabinete)
--  secretaria   | Acesso a Adm. Secretaria e Adm. Pastoral,
--               | aprovação de pendentes
--  lider        | Acesso apenas ao ministério próprio,
--               | eventos ficam como "pendente" até aprovação
--
-- ============================================================
-- CAMPOS DE STATUS (eventos, liturgias, agenda, diaconal)
-- ============================================================
--
--  aprovado  → visível para todos
--  pendente  → aguardando aprovação (criado por 'lider')
--  rejected  → recusado pelo pastor/secretaria/admin
--
-- ============================================================
