-- 2026-11-19: minty_merge + minty_merge_record (the merging table - owner's decisions doc M1-M4) and
-- report.edit_version + saved_by_user_id (two people on one report - doc R2), for a database already
-- recorded at 0001.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (the report table and its last section), so a
-- fresh build already has all of it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-19_merges_and_report_version.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-19_merges_and_report_version.sql --apply
--
-- minty_merge: one row per merge of two of a company's accounts or two of its contacts; the merged
-- one is archived with merged_into_id, every record on it moves to the kept one, Xero is not
-- touched. minty_merge_record: each record a merge moved, so its original can always be found.
-- report.edit_version: the version a step save carries (a save from an older one is refused);
-- saved_by_user_id: who saved last. Every existing report starts at version 0, no one named. Old
-- code ignores all of it.
-- Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = current_schema() AND table_name IN ('minty_merge', 'minty_merge_record'))
     OR EXISTS (SELECT 1 FROM information_schema.columns
                WHERE table_schema = current_schema() AND table_name = 'report'
                  AND column_name IN ('edit_version', 'saved_by_user_id')) THEN
    RAISE EXCEPTION 'minty_merge / report.edit_version is already in this schema';
  END IF;
END $$;

ALTER TABLE report
  ADD COLUMN edit_version     INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN saved_by_user_id UUID    NULL,
  ADD CONSTRAINT fk_report_saved_by FOREIGN KEY (saved_by_user_id) REFERENCES "user" (id) ON DELETE SET NULL,
  ADD CONSTRAINT ck_report_edit_version CHECK (edit_version >= 0);

CREATE TABLE minty_merge (
  id                UUID         NOT NULL DEFAULT gen_random_uuid(),
  entity_id         UUID         NOT NULL,
  kind              VARCHAR(10)  NOT NULL,
  merged_id         UUID         NOT NULL,
  kept_id           UUID         NOT NULL,
  reason            VARCHAR(20)  NOT NULL,
  merged_by_user_id UUID         NULL,
  merged_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
  CONSTRAINT minty_merge_pkey PRIMARY KEY (id),
  CONSTRAINT fk_minty_merge_entity FOREIGN KEY (entity_id)         REFERENCES entities (id) ON DELETE CASCADE,
  CONSTRAINT fk_minty_merge_user   FOREIGN KEY (merged_by_user_id) REFERENCES "user" (id)   ON DELETE SET NULL,
  CONSTRAINT ck_minty_merge_kind   CHECK (kind IN ('account', 'contact')),
  CONSTRAINT ck_minty_merge_reason CHECK (reason IN ('user', 'xero_matching', 'merged_in_xero')),
  CONSTRAINT ck_minty_merge_self   CHECK (merged_id <> kept_id)
);
CREATE INDEX idx_minty_merge_entity ON minty_merge (entity_id, merged_at);
CREATE INDEX idx_minty_merge_merged ON minty_merge (merged_id);

CREATE TABLE minty_merge_record (
  id          UUID         NOT NULL DEFAULT gen_random_uuid(),
  merge_id    UUID         NOT NULL,
  table_name  VARCHAR(63)  NOT NULL,
  column_name VARCHAR(63)  NOT NULL,
  record_id   UUID         NOT NULL,
  CONSTRAINT minty_merge_record_pkey PRIMARY KEY (id),
  CONSTRAINT fk_minty_merge_record_merge FOREIGN KEY (merge_id) REFERENCES minty_merge (id) ON DELETE CASCADE
);
CREATE INDEX idx_minty_merge_record_merge ON minty_merge_record (merge_id);

SELECT (SELECT count(*) FROM report) AS reports_at_version_0;
