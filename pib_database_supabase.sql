-- ============================================================
--  PIB GESTÃO — Script completo do banco de dados Supabase
--  Primeira Igreja Batista de Cajueiro Seco
--  Compatível com o sistema calendario.html
-- ============================================================
-- IMPORTANTE:
--   O sistema usa autenticação própria (tabela pib_users),
--   NÃO usa o Supabase Auth nativo (auth.uid()).
--   Por isso, o RLS é DESABILITADO em todas as tabelas.
--   As regras de acesso são controladas pelo próprio JavaScript.
-- ============================================================

-- ============================================================
-- 1. USUÁRIOS DO SISTEMA
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_users (
  id          TEXT        PRIMARY KEY,
  name        TEXT        NOT NULL,
  email       TEXT        NOT NULL UNIQUE,
  pw          TEXT        NOT NULL,
  role        TEXT        NOT NULL DEFAULT 'lider',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_users DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_users_email ON pib_users(email);

-- ============================================================
-- 2. EVENTOS DO CALENDÁRIO
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_events (
  id           TEXT        PRIMARY KEY,
  name         TEXT        NOT NULL,
  date         TEXT        NOT NULL,
  start_time   TEXT,
  end_time     TEXT,
  category     TEXT,
  description  TEXT,
  recurrence   TEXT DEFAULT 'none',
  status       TEXT NOT NULL DEFAULT 'aprovado',
  created_by   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_events DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_events_date   ON pib_events(date);
CREATE INDEX IF NOT EXISTS idx_pib_events_status ON pib_events(status);

-- ============================================================
-- 3. LITURGIAS
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_liturgias (
  id          TEXT        PRIMARY KEY,
  title       TEXT        NOT NULL,
  date        TEXT,
  time        TEXT,
  slogan      TEXT,
  footer      TEXT,
  items       JSONB       NOT NULL DEFAULT '[]',
  status      TEXT        NOT NULL DEFAULT 'aprovado',
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_liturgias DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_liturgias_created_at ON pib_liturgias(created_at DESC);

-- ============================================================
-- 4. AGENDA SEMANAL
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_agenda (
  id          TEXT        PRIMARY KEY,
  title       TEXT        NOT NULL,
  date_start  TEXT,
  date_end    TEXT,
  slogan      TEXT,
  footer      TEXT,
  note        TEXT,
  days        JSONB       NOT NULL DEFAULT '[]',
  status      TEXT        NOT NULL DEFAULT 'aprovado',
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_agenda DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_agenda_date_start ON pib_agenda(date_start);

-- ============================================================
-- 5. SERVIÇO DIACONAL
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_diaconal (
  id          TEXT        PRIMARY KEY,
  title       TEXT        NOT NULL,
  event_id    TEXT,
  date        TEXT,
  items       JSONB       NOT NULL DEFAULT '[]',
  status      TEXT        NOT NULL DEFAULT 'aprovado',
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_diaconal DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_diaconal_created_at ON pib_diaconal(created_at DESC);

-- ============================================================
-- 6. MINISTÉRIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_ministerios (
  id          TEXT        PRIMARY KEY,
  name        TEXT        NOT NULL,
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_ministerios DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_ministerios_created_at ON pib_ministerios(created_at);

-- ============================================================
-- 7. MEMBROS DOS MINISTÉRIOS
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_ministerio_members (
  id             TEXT        PRIMARY KEY,
  ministerio_id  TEXT        NOT NULL REFERENCES pib_ministerios(id) ON DELETE CASCADE,
  user_email     TEXT        NOT NULL,
  invited_by     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ministerio_id, user_email)
);

ALTER TABLE pib_ministerio_members DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_min_members_email      ON pib_ministerio_members(user_email);
CREATE INDEX IF NOT EXISTS idx_pib_min_members_ministerio ON pib_ministerio_members(ministerio_id);

-- ============================================================
-- 8. RELATÓRIOS FINANCEIROS (por ministério)
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_financial_reports (
  id             TEXT          PRIMARY KEY,
  ministerio_id  TEXT          NOT NULL REFERENCES pib_ministerios(id) ON DELETE CASCADE,
  period_start   TEXT          NOT NULL,
  period_end     TEXT,
  income_total   NUMERIC(12,2) NOT NULL DEFAULT 0,
  expense_total  NUMERIC(12,2) NOT NULL DEFAULT 0,
  items          JSONB         NOT NULL DEFAULT '[]',
  notes          TEXT,
  created_by     TEXT,
  created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_financial_reports DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_fin_ministerio    ON pib_financial_reports(ministerio_id);
CREATE INDEX IF NOT EXISTS idx_pib_fin_period_start  ON pib_financial_reports(period_start);

-- ============================================================
-- 9. REGISTROS SEMANAIS DE CULTO (por ministério)
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_registros (
  id                TEXT        PRIMARY KEY,
  ministerio_id     TEXT        NOT NULL REFERENCES pib_ministerios(id) ON DELETE CASCADE,
  data_culto        TEXT        NOT NULL,
  dia_semana        TEXT,
  nome_culto        TEXT,
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

ALTER TABLE pib_registros DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_registros_ministerio  ON pib_registros(ministerio_id);
CREATE INDEX IF NOT EXISTS idx_pib_registros_data_culto  ON pib_registros(data_culto DESC);

-- ============================================================
-- 10. NOTAS PASTORAIS PRIVADAS (por evento)
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_gabinete_notes (
  id          BIGSERIAL   PRIMARY KEY,
  event_id    TEXT        NOT NULL UNIQUE,
  content     TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_gabinete_notes DISABLE ROW LEVEL SECURITY;

-- ============================================================
-- 11. LISTA DE MEMBROS DA IGREJA
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_membros (
  id              TEXT        PRIMARY KEY,
  nome            TEXT        NOT NULL,
  departamento    TEXT,
  telefone        TEXT,
  email           TEXT,
  data_nascimento TEXT,
  endereco        TEXT,
  observacoes     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_membros DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_membros_nome ON pib_membros(nome);

-- ============================================================
-- 12. RELATÓRIOS DE REUNIÃO ADMINISTRATIVA
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_reuniao_admin_reports (
  id                    TEXT        PRIMARY KEY,
  event_id              TEXT,
  data                  TEXT,
  pauta                 TEXT,
  presentes             TEXT,
  ausentes              TEXT,
  oracao_inicial        TEXT,
  relatorio_fin_igreja  TEXT,
  extraordinaria        BOOLEAN     NOT NULL DEFAULT FALSE,
  votacoes              JSONB       NOT NULL DEFAULT '[]',
  created_by            TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE pib_reuniao_admin_reports DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_rad_event_id  ON pib_reuniao_admin_reports(event_id);
CREATE INDEX IF NOT EXISTS idx_pib_rad_data       ON pib_reuniao_admin_reports(data DESC);

-- ============================================================
-- 13. RELATÓRIOS DE CULTO (detalhado por evento)
-- ============================================================
CREATE TABLE IF NOT EXISTS pib_culto_reports (
  id            TEXT        PRIMARY KEY,
  event_id      TEXT,
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

ALTER TABLE pib_culto_reports DISABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_pib_culto_reports_event_id ON pib_culto_reports(event_id);

-- ============================================================
-- 14. STORAGE BUCKET — COMPROVANTES FINANCEIROS
-- ============================================================
-- No painel do Supabase, crie um bucket chamado "comprovantes" com publicidade habilitada.
INSERT INTO storage.buckets (id, name, public)
VALUES ('comprovantes', 'comprovantes', TRUE)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "allow_all_comprovantes" ON storage.objects;
CREATE POLICY "allow_all_comprovantes"
  ON storage.objects FOR ALL
  USING (bucket_id = 'comprovantes')
  WITH CHECK (bucket_id = 'comprovantes');

-- ============================================================
-- PASSO A PASSO PARA O NOVO PROJETO SUPABASE
-- ============================================================
-- 1. Crie um novo projeto no Supabase.
-- 2. Abra SQL Editor e execute este script inteiro.
-- 3. No painel, vá em Settings > API e copie:
--      - Project URL
--      - anon public key
-- 4. No arquivo calendario.html, substitua os valores abaixo:
--      const PIB_SUPABASE_URL = 'https://iqujehfmwarlabhhmmfx.supabase.co';
--      const PIB_SUPABASE_ANON_KEY = 'sb_publishable_72sa3w2DxdOxjLEiNzWWRw_B39wSFij';
-- 5. Salve e abra o arquivo no navegador.
-- 6. Para criar o usuário administrador, execute este SQL:


-- ============================================================
