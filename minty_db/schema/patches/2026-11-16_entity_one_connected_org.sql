-- 2026-11-16: uq_entities_connected_xero_org - one Xero organisation, at most one company holding
-- it - for a database already recorded at 0001 (owner-approved, 2026-11-16).
--
-- The baseline is minty_db/schema/01_schema_rebased.sql (the index sits beside
-- uq_ebax_entity_xero_account), so a fresh build already has it. Schema changes stay baseline:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-16_entity_one_connected_org.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-16_entity_one_connected_org.sql --apply
--
-- The rule has always been one organisation = one company (Flask's "one org = one entity",
-- tightened 2026-10-09); accounts-api holds it at connect time (xero/services/connect.py
-- live_org_claimant), and this index closes the race two connects at once leave open. A
-- disconnected company keeps its organisation (2026-11-10) and is no claim, so it is left out; an
-- onboarding company holding one reads as connected and counts.
--
-- No data is changed. A database that already breaks the rule is refused with each clashing
-- organisation named: disconnect all but one company of it by hand, then run again. Not
-- re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$
DECLARE clash TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_indexes
             WHERE schemaname = current_schema() AND indexname = 'uq_entities_connected_xero_org') THEN
    RAISE EXCEPTION 'uq_entities_connected_xero_org is already in this schema';
  END IF;
  SELECT string_agg(format('%s (%s)', xero_org_id, names), '; ') INTO clash
    FROM (SELECT xero_org_id, string_agg(name || ' [' || status || ']', ', ' ORDER BY name) AS names
            FROM entities
           WHERE xero_org_id IS NOT NULL AND status <> 'disconnected'
           GROUP BY xero_org_id
          HAVING count(*) > 1) c;
  IF clash IS NOT NULL THEN
    RAISE EXCEPTION 'more than one company holds a Xero organisation: %', clash;
  END IF;
END $$;

CREATE UNIQUE INDEX uq_entities_connected_xero_org
    ON entities (xero_org_id)
 WHERE status <> 'disconnected';

SELECT count(*) FILTER (WHERE xero_org_id IS NOT NULL AND status <> 'disconnected') AS companies_holding_an_org,
       count(*) FILTER (WHERE xero_org_id IS NOT NULL AND status = 'disconnected') AS disconnected_keeping_one
  FROM entities;
