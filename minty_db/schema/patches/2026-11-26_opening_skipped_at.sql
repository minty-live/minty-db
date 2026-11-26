-- 2026-11-26 (the user): entity_pettycash_settings.opening_skipped_at - when someone pressed "Skip for
-- now" on onboarding's Opening Balance step, for a database already recorded at 0001. The balance stays
-- NOT SET (opening_balance and start_date NULL, never 0): the first petty cash report asks for it
-- (petty-cash-api PUT /opening-balance), and any saved balance clears the mark. Only the onboarding
-- resume reads it, through entity_setup_summary, which gains it as its last column.
--
-- The baseline is minty_db/schema/01_schema_rebased.sql, so a fresh build already has it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-26_opening_skipped_at.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-26_opening_skipped_at.sql --apply
--
-- Old code ignores the column (a view may only gain columns at its end, so it is appended), so the
-- patch goes first. Not re-runnable: a second run stops at the guard. The way back is its _down.sql.

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = current_schema() AND table_name = 'entity_pettycash_settings'
               AND column_name = 'opening_skipped_at') THEN
    RAISE EXCEPTION 'entity_pettycash_settings.opening_skipped_at is already in this schema';
  END IF;
END $$;

ALTER TABLE entity_pettycash_settings ADD COLUMN opening_skipped_at TIMESTAMPTZ NULL;

CREATE OR REPLACE VIEW entity_setup_summary AS
SELECT e.id AS entity_id,
       e.name AS entity_name,
       e.status AS entity_status,
       e.currency_id,
       e.country_code,
       e.status = 'connected' AS xero_connected,
       e.xero_org_id IS NOT NULL AS xero_org_linked,
       e.xero_org_id,
       e.xero_tenant_name,
       e.last_connected_at,
       e.connected_by_user_id,
       cu.username AS connected_by_username,
       COALESCE(m.pettycash_enabled, false) AS pettycash_module_enabled,
       COALESCE(m.bill_enabled, false) AS bill_module_enabled,
       (eps.pettycash_account_id IS NOT NULL)::integer + (eps.bank_account_id IS NOT NULL)::integer
         + (eps.cash_sale_account_id IS NOT NULL)::integer + (eps.discrepancy_bank_account_id IS NOT NULL)::integer
         + (eps.discrepancy_account_id IS NOT NULL)::integer + (eps.director_account_id IS NOT NULL)::integer
         AS pettycash_accounts_set,
       6 AS pettycash_accounts_total,
       (eps.cash_sale_contact_id IS NOT NULL)::integer + (eps.director_contact_id IS NOT NULL)::integer
         + (eps.discrepancy_contact_id IS NOT NULL)::integer AS pettycash_contacts_set,
       3 AS pettycash_contacts_total,
       COALESCE(ai.n, 0) AS xero_accounts_synced,
       COALESCE(ba.n_active, 0) AS bill_accounts_set,
       COALESCE(ba.n_default, 0) AS bill_accounts_default,
       eps.opening_balance,
       eps.start_date,
       a_pc.name AS pettycash_account_name,
       a_pc.xero_code AS pettycash_account_code,
       a_bk.name AS bank_account_name,
       a_bk.xero_code AS bank_account_code,
       a_cs.name AS cash_sale_account_name,
       a_cs.xero_code AS cash_sale_account_code,
       a_db.name AS discrepancy_bank_account_name,
       a_db.xero_code AS discrepancy_bank_account_code,
       a_dc.name AS discrepancy_account_name,
       a_dc.xero_code AS discrepancy_account_code,
       a_dr.name AS director_account_name,
       a_dr.xero_code AS director_account_code,
       c_cs.name AS cash_sale_contact_name,
       c_dr.name AS director_contact_name,
       c_dc.name AS discrepancy_contact_name,
       eps.updated_at AS pettycash_settings_updated_at,
       eps.opening_skipped_at
  FROM entities e
  LEFT JOIN "user" cu ON cu.id = e.connected_by_user_id
  LEFT JOIN entity_pettycash_settings eps ON eps.entity_id = e.id
  LEFT JOIN account_info a_pc ON a_pc.id = eps.pettycash_account_id
  LEFT JOIN account_info a_bk ON a_bk.id = eps.bank_account_id
  LEFT JOIN account_info a_cs ON a_cs.id = eps.cash_sale_account_id
  LEFT JOIN account_info a_db ON a_db.id = eps.discrepancy_bank_account_id
  LEFT JOIN account_info a_dc ON a_dc.id = eps.discrepancy_account_id
  LEFT JOIN account_info a_dr ON a_dr.id = eps.director_account_id
  LEFT JOIN xero_contact_sync c_cs ON c_cs.id = eps.cash_sale_contact_id
  LEFT JOIN xero_contact_sync c_dr ON c_dr.id = eps.director_contact_id
  LEFT JOIN xero_contact_sync c_dc ON c_dc.id = eps.discrepancy_contact_id
  LEFT JOIN LATERAL (
        SELECT bool_or(ef.function_code = 'PETTY_CASH' AND efm.is_enabled) AS pettycash_enabled,
               bool_or(ef.function_code = 'PAYMENT_REQUEST' AND efm.is_enabled) AS bill_enabled
          FROM entity_function_map efm
          JOIN entity_function ef ON ef.id = efm.entity_function_id
         WHERE efm.entity_id = e.id) m ON true
  LEFT JOIN LATERAL (
        SELECT count(*) AS n FROM account_info x WHERE x.entity_id = e.id) ai ON true
  LEFT JOIN LATERAL (
        SELECT count(*) FILTER (WHERE b.is_active AND NOT b.is_deleted) AS n_active,
               count(*) FILTER (WHERE b.is_active AND NOT b.is_deleted AND b.is_default) AS n_default
          FROM entity_bill_account_xero b
         WHERE b.entity_id = e.id) ba ON true;

SELECT count(*) AS companies,
       count(*) FILTER (WHERE start_date IS NULL) AS opening_not_set
  FROM entity_setup_summary;
