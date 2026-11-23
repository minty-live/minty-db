-- 2026-11-23: the way back from 2026-11-23_long_xero_codes.sql. account_code_from_xero blanks a
-- long code for BANK accounts only again, so a non-bank Xero account whose code is longer than 10
-- characters is refused again. One transaction, rolled back unless --apply. Run it only with the
-- services back on a minty-db before v0.17, and only while no non-bank account_info row has such a
-- xero_code (an update of that row would then fail).

CREATE OR REPLACE FUNCTION account_code_from_xero(code TEXT, t TEXT) RETURNS VARCHAR(10)
LANGUAGE sql IMMUTABLE
RETURN CASE WHEN NULLIF(btrim(code), '') IS NULL THEN NULL
            WHEN upper(btrim(t)) = 'BANK' AND length(btrim(code)) > 10 THEN NULL   -- the name, not a code
            ELSE btrim(code) END;

SELECT 'account_code_from_xero blanks long codes for BANK accounts only' AS done;
