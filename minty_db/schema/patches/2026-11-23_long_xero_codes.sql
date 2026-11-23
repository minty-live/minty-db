-- 2026-11-23: account_code_from_xero reads ANY Xero code longer than 10 characters as a name, not
-- a code - for a database already at 0001.
--
-- A Xero organisation sent CURRENT accounts whose "code" was the account's name ("Amount due from
-- LEE Min Ho", "KPAY (Noodle Town)"). The function blanked a long code for BANK accounts only, so
-- trg_account_info_fill put the long value in account_info.code (VARCHAR(10)), the row was refused,
-- and the whole Xero connect - or the account sync after a matching - failed ("value too long for
-- type character varying(10)"; Mary Baclay's "OTT - Noodle Town (Demo)", 18 Nov 2026).
--
-- Now code stays empty for any type; xero_code keeps Xero's full value, and Petty Cash and Payment
-- Requests publish with xero_code, so nothing reaching Xero changes. Codes of 10 or fewer are
-- untouched. Nothing is backfilled: a bank row with a long xero_code already has no code, and no
-- other row can have one (its insert failed). The count below shows both: non-bank should be 0.
-- The baseline is minty_db/schema/01_schema_rebased.sql, so a fresh build already has it:
--
--     python -m minty_db patch minty_db/schema/patches/2026-11-23_long_xero_codes.sql           # dry run
--     python -m minty_db patch minty_db/schema/patches/2026-11-23_long_xero_codes.sql --apply
--
-- Re-runnable (CREATE OR REPLACE). The way back is its _down.sql.

CREATE OR REPLACE FUNCTION account_code_from_xero(code TEXT, t TEXT) RETURNS VARCHAR(10)
LANGUAGE sql IMMUTABLE
RETURN CASE WHEN NULLIF(btrim(code), '') IS NULL THEN NULL
            WHEN length(btrim(code)) > 10 THEN NULL   -- a name, not a code (any type)
            ELSE btrim(code) END;

SELECT count(*) FILTER (WHERE upper(btrim(type)) = 'BANK')  AS bank_accounts_with_a_long_xero_code,
       count(*) FILTER (WHERE upper(btrim(type)) <> 'BANK') AS other_accounts_with_a_long_xero_code
FROM account_info WHERE length(btrim(xero_code)) > 10;
