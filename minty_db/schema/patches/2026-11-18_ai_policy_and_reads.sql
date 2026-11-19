-- 2026-11-18: ai_policy, ai_grant and ai_read - the AI readers' settings, each company's grants
-- (owner-approved, 2026-11-18) - for a database already recorded at 0001.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (its last section), so a fresh build already
-- has both tables; its policy row is seed_catalogue.sql's, which this patch also inserts:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-18_ai_policy_and_reads.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-18_ai_policy_and_reads.sql --apply
--
-- ai_policy: one row - the model each read tries first, the backup, the one-time grant every
-- company gets on its first read (the preview: 20,000 tokens) and extra caps (none). ai_grant: a
-- company's allowances, Petty Cash and Payment Request together. ai_read: one row per read a person
-- asks for, charged to a grant. Old code ignores all three.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = current_schema() AND table_name IN ('ai_policy', 'ai_grant', 'ai_read')) THEN
    RAISE EXCEPTION 'ai_policy / ai_grant / ai_read is already in this schema';
  END IF;
END $$;

CREATE TABLE ai_policy (
  id            INTEGER      NOT NULL,
  primary_model VARCHAR(100) NOT NULL,
  backup_model  VARCHAR(100) NULL,
  default_grant JSONB        NULL,
  limit_rules   JSONB        NOT NULL,
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_by    VARCHAR(255) NULL,
  CONSTRAINT ai_policy_pkey PRIMARY KEY (id),
  CONSTRAINT ck_ai_policy_singleton    CHECK (id = 1),
  CONSTRAINT ck_ai_policy_rules_list   CHECK (jsonb_typeof(limit_rules) = 'array'),
  CONSTRAINT ck_ai_policy_grant_object CHECK (default_grant IS NULL OR jsonb_typeof(default_grant) = 'object'),
  CONSTRAINT ck_ai_policy_backup_other CHECK (backup_model IS NULL OR backup_model <> primary_model)
);
CREATE TRIGGER trg_ai_policy_updated BEFORE UPDATE ON ai_policy
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ai_grant (owner, 2026-11-18): an AI allowance given to one company - Petty Cash and Payment
-- Request read against it together. tokens_total and/or reads_total (NULL = no cap on that one);
-- expires_at NULL = never. A grant used up or expired is spent and stays as the record; a company
-- may hold several (a top-up is another grant). source: 'default' = ai_policy.default_grant, given
-- once on the company's first read; 'manual' = given by hand. Each read is charged to one grant
-- (ai_read.grant_id), the oldest with room.
CREATE TABLE ai_grant (
  id           UUID         NOT NULL DEFAULT gen_random_uuid(),
  entity_id    UUID         NOT NULL,
  tokens_total INTEGER      NULL,
  reads_total  INTEGER      NULL,
  expires_at   TIMESTAMPTZ  NULL,
  source       VARCHAR(10)  NOT NULL DEFAULT 'manual',
  granted_by   VARCHAR(255) NULL,
  note         VARCHAR(255) NULL,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT ai_grant_pkey PRIMARY KEY (id),
  CONSTRAINT fk_ai_grant_entity FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
  CONSTRAINT ck_ai_grant_caps   CHECK (tokens_total IS NOT NULL OR reads_total IS NOT NULL),
  CONSTRAINT ck_ai_grant_sizes  CHECK ((tokens_total IS NULL OR tokens_total > 0) AND (reads_total IS NULL OR reads_total > 0)),
  CONSTRAINT ck_ai_grant_source CHECK (source IN ('default', 'manual'))
);
CREATE INDEX idx_ai_grant_entity ON ai_grant (entity_id, created_at);
-- the default grant is given once per company, ever
CREATE UNIQUE INDEX uq_ai_grant_one_default ON ai_grant (entity_id) WHERE source = 'default';

-- ai_read: one row per AI read a person asked for - what the allowance counts and how a read is
-- traced. pending = reserved, the model not answered yet; ok = a model answered with a valid reply
-- (counts as a read); failed = no valid reply (never counts as a read). Tokens are every attempt's,
-- failed ones included (they are billed), and are charged to grant_id. model_answered is the model
-- that replied; attempts the chain tried ('gemini-3.5-flash-lite:timeout>gemini-3.8-flash:ok').
-- Never anything read off the document.
CREATE TABLE ai_read (
  id              UUID          NOT NULL DEFAULT gen_random_uuid(),
  entity_id       UUID          NOT NULL,
  grant_id        UUID          NULL,
  user_id         UUID          NULL,
  module          VARCHAR(20)   NOT NULL,
  status          VARCHAR(10)   NOT NULL DEFAULT 'pending',
  reason          VARCHAR(40)   NULL,
  model_answered  VARCHAR(100)  NULL,
  attempts        VARCHAR(400)  NULL,
  tokens_in       INTEGER       NOT NULL DEFAULT 0,
  tokens_out      INTEGER       NOT NULL DEFAULT 0,
  tokens_thought  INTEGER       NOT NULL DEFAULT 0,
  tokens_cached   INTEGER       NOT NULL DEFAULT 0,
  estimated_cost  NUMERIC(12,6) NULL,
  latency_ms      INTEGER       NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
  finished_at     TIMESTAMPTZ   NULL,
  CONSTRAINT ai_read_pkey PRIMARY KEY (id),
  CONSTRAINT fk_ai_read_entity FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
  CONSTRAINT fk_ai_read_grant  FOREIGN KEY (grant_id)  REFERENCES ai_grant (id) ON DELETE SET NULL,
  CONSTRAINT fk_ai_read_user   FOREIGN KEY (user_id)   REFERENCES "user" (id)  ON DELETE SET NULL,
  CONSTRAINT ck_ai_read_module CHECK (module IN ('petty_cash', 'payment_request')),
  CONSTRAINT ck_ai_read_status CHECK (status IN ('pending', 'ok', 'failed')),
  CONSTRAINT ck_ai_read_tokens CHECK (tokens_in >= 0 AND tokens_out >= 0 AND tokens_thought >= 0 AND tokens_cached >= 0)
);
CREATE INDEX idx_ai_read_entity_created ON ai_read (entity_id, created_at);
CREATE INDEX idx_ai_read_grant ON ai_read (grant_id);

INSERT INTO ai_policy (id, primary_model, backup_model, default_grant, limit_rules, updated_by)
VALUES (1, 'gemini-3.5-flash-lite', 'gemini-3.8-flash', '{"tokens": 20000}', '[]',
        '2026-11-18_ai_policy_and_reads.sql');

SELECT id, primary_model, backup_model, default_grant, limit_rules FROM ai_policy;
