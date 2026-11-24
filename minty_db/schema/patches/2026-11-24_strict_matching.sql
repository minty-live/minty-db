-- 2026-11-24: Xero matching without merging, with a contacts step, and Minty's code kept beside Xero's
-- (the user, 2026-11-24) - for a database already recorded at 0001.
--
-- * account_match_draft: one Minty account per Xero account (uq_account_match_draft_xero). Accounts are
--   never merged any more, so two can't share a Xero account. Duplicate picks still open on a page (two
--   accounts on one Xero account) are cleared first - all but the earliest, which keeps its pick; the
--   count below says how many, and those accounts are picked again on the page.
-- * contact_match_draft: the matching screen's contacts step - each supplier's Xero contact (or "new in
--   Xero"), each daily-closing contact still to choose - saved until Finish.
-- * trg_account_info_fill: Xero's code fills account_info.code only while it is empty, never over one,
--   so an account keeps its Minty code beside its Xero code (xero_code). Codes Xero already overwrote
--   stay as they are; the count below says how many account_change_log could name the Minty code of.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql, so a fresh build already has all of it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-24_strict_matching.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-24_strict_matching.sql --apply
--
-- Old code (minty-db v0.17 and before) still runs on it: nothing it reads changes; its Finish combines
-- accounts only when two pick one Xero account, which the new index now refuses.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = current_schema() AND table_name = 'contact_match_draft') THEN
    RAISE EXCEPTION 'contact_match_draft is already in this schema';
  END IF;
END $$;

WITH ranked AS (
  SELECT account_id, row_number() OVER (PARTITION BY xero_account_id ORDER BY picked_at, account_id) AS n
  FROM account_match_draft
), cleared AS (
  DELETE FROM account_match_draft d USING ranked r WHERE d.account_id = r.account_id AND r.n > 1
  RETURNING d.account_id
)
SELECT count(*) AS duplicate_account_picks_cleared FROM cleared;

DROP INDEX idx_account_match_draft_xero;
CREATE UNIQUE INDEX uq_account_match_draft_xero ON account_match_draft (xero_account_id);

CREATE TABLE contact_match_draft (
  id               UUID         NOT NULL DEFAULT gen_random_uuid(),
  entity_id        UUID         NOT NULL,
  contact_id       UUID         NULL,
  slot             VARCHAR(20)  NULL,
  xero_contact_id  UUID         NULL,
  add_to_xero      BOOLEAN      NOT NULL DEFAULT FALSE,
  picked_by        UUID         NULL,
  picked_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT contact_match_draft_pkey PRIMARY KEY (id),
  CONSTRAINT uq_contact_match_contact UNIQUE (contact_id),
  CONSTRAINT uq_contact_match_slot UNIQUE (entity_id, slot),
  CONSTRAINT chk_contact_match_target CHECK ((contact_id IS NULL) <> (slot IS NULL)),
  CONSTRAINT chk_contact_match_slot CHECK (slot IS NULL OR slot IN ('cash_sale','director','discrepancy')),
  CONSTRAINT chk_contact_match_answer CHECK ((xero_contact_id IS NOT NULL) <> add_to_xero),
  CONSTRAINT chk_contact_match_new CHECK (NOT add_to_xero OR contact_id IS NOT NULL),
  CONSTRAINT fk_contact_match_contact FOREIGN KEY (contact_id, entity_id)
    REFERENCES xero_contact_sync (id, entity_id) ON DELETE CASCADE,
  CONSTRAINT fk_contact_match_xero FOREIGN KEY (xero_contact_id, entity_id)
    REFERENCES xero_contact (id, entity_id) ON DELETE CASCADE,
  CONSTRAINT fk_contact_match_entity FOREIGN KEY (entity_id) REFERENCES entities (id) ON DELETE CASCADE,
  CONSTRAINT fk_contact_match_user FOREIGN KEY (picked_by) REFERENCES "user" (id) ON DELETE SET NULL
);
CREATE INDEX idx_contact_match_draft_entity ON contact_match_draft (entity_id);
CREATE INDEX idx_contact_match_draft_xero   ON contact_match_draft (xero_contact_id);

CREATE OR REPLACE FUNCTION account_info_fill() RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE s TEXT := quote_ident(TG_TABLE_SCHEMA);
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.code IS NULL THEN
      EXECUTE format('SELECT %s.account_code_from_xero($1, $2)', s) INTO NEW.code USING NEW.xero_code, NEW.type;
    END IF;
    IF NEW.account_type IS NULL THEN
      EXECUTE format('SELECT %s.account_type_from_xero($1)', s) INTO NEW.account_type USING NEW.type;
    END IF;
    IF NEW.status IS NOT NULL THEN
      EXECUTE format('SELECT %s.record_status_from_xero($1)', s) INTO NEW.record_status USING NEW.status;
    END IF;
  ELSE
    -- Minty's code is Minty's (the user, 2026-11-24: Minty Code + Xero Code): Xero's code fills it
    -- only while it is empty, never over one
    IF NEW.code IS NULL AND (NEW.xero_code IS DISTINCT FROM OLD.xero_code OR NEW.type IS DISTINCT FROM OLD.type) THEN
      EXECUTE format('SELECT %s.account_code_from_xero($1, $2)', s) INTO NEW.code USING NEW.xero_code, NEW.type;
    END IF;
    IF NEW.type IS DISTINCT FROM OLD.type THEN
      EXECUTE format('SELECT %s.account_type_from_xero($1)', s) INTO NEW.account_type USING NEW.type;
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      EXECUTE format('SELECT %s.record_status_from_xero($1)', s) INTO NEW.record_status USING NEW.status;
    END IF;
  END IF;
  RETURN NEW;
END $fn$;

-- accounts whose Minty code a matching overwrote, the original kept in account_change_log (not restored)
SELECT count(DISTINCT l.account_id) AS accounts_whose_minty_code_the_log_holds
FROM account_change_log l JOIN account_info a ON a.id = l.account_id
WHERE l.kind = 'overwritten' AND l.before_code IS NOT NULL AND l.before_code IS DISTINCT FROM a.code;
