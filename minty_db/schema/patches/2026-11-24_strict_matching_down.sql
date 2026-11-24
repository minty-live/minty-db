-- 2026-11-24: the way back from 2026-11-24_strict_matching.sql. contact_match_draft goes (open
-- contacts-step picks with it), several accounts may pick one Xero account again, and Xero's code
-- overwrites account_info.code again. One transaction, rolled back unless --apply. Run it only with
-- the services back on a minty-db before v0.18.

DROP TABLE contact_match_draft;
DROP INDEX uq_account_match_draft_xero;
CREATE INDEX idx_account_match_draft_xero ON account_match_draft (xero_account_id);

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
    IF NEW.xero_code IS DISTINCT FROM OLD.xero_code OR NEW.type IS DISTINCT FROM OLD.type THEN
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

SELECT 'contact_match_draft dropped; Xero overwrites account_info.code again' AS done;
