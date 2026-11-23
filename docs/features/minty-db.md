# minty-db

Phase 0 of the Flask retirement plan (2026-10-30). This package replaces the four hand-kept `shared_models/` copies in the Django APIs and Flask's Alembic migrations as the only owner of the schema.

## What it guarantees

| Check | Where |
|---|---|
| Every model's columns and types equal the schema's, table by table | `tests/test_schema.py::test_every_column_has_the_models_type` (Postgres) |
| Every model, views included, can be queried on the real schema | `tests/test_models.py::test_every_model_can_be_queried` |
| `models.py`/`enums.py` are what the schema file generates | `scripts/generate_models.py --check`, run by a test |
| Migration state equals the models | `makemigrations --check` test |
| A patch brings a database at `0001` to what a fresh build has | `test_the_xero_keys_patch_merges_duplicates_and_matches_a_fresh_build`, `test_the_xero_optional_patch_matches_a_fresh_build_and_its_down_patch_reverses_it` (whole catalogue: columns, constraints, indexes, triggers, functions, enums) |
| Generated columns are computed, never written by the ORM | `tests/test_models.py::test_generated_columns_are_computed_and_never_written` |
| `migrate` builds a fresh database, and refuses then baselines an existing one | `test_migrate_builds_a_fresh_database_and_baselines_an_existing_one` |

CI runs everything twice: on SQLite, and on Postgres 15 built from the packaged schema file.

## Decisions

- **Generated from the database, not merged from the copies.** The copies disagreed in 58 places across 21 shared tables, nearly all on the id type. The generator reads a fresh build's catalogue, so the models are the schema's mirror by construction.
- **Ids are `uuid.UUID`** (owner, 2026-10-28). `MintyUUIDField`, which returned text, is retired. subscription-api and petty-cash-api convert before they switch, and a test-only check turns any `UUID`-vs-`str` comparison into a failure.
- **Foreign keys only on `<name>_id` columns, with `db_constraint=False` and `related_name="+"`.** This keeps the APIs' existing code and lenient SQLite tests working; the real constraints are the database's. `created_by`, `invited_by` and `currency` stay plain fields, because the APIs assign raw values to them.
- **Database defaults are `db_default`.** Django 5.2 returns them on insert, so `created_at` is a datetime straight after `create()` on both SQLite and Postgres.
- **Unique rules come from the schema (v0.2).** Every unique constraint and unique index is read from the catalogue: one column -> `unique=True` (a key becomes a `OneToOneField`), several -> `Meta.constraints`, a partial index -> a `UniqueConstraint` whose `Q` is written once in `PARTIAL_UNIQUE` and checked against the predicate Postgres reports (the generator stops if it changes).
- **Reverse names and ordering are declared exceptions (v0.2).** `RELATED_NAMES` and `ORDERING` in the generator hold what an API's code uses (`user.billing_groups`, `invoice.lines` in creation order) - added as each API switches, never removed while one uses them. v0.2 regenerated `0001`'s STATE only: the rules were already in the schema file, so a baselined database is unchanged.
- **Django-only relations (v0.3).** `VIRTUAL_FKS` declares a relation the schema does not have but an API joins through: `entity_sale_setting.sale_id` -> `sale_info` (onboarding-api). It is `db_constraint=False`, so nothing reaches the database; 01 says `sale_id` is not a real reference, so a join simply skips rows that do not match, as the API's own copy behaved.
- **The id guard is shared (v0.3).** `minty_db.testing.uuid_guard`: under test, a service's code comparing a `UUID` with uuid text raises. Django's own comparisons (its foreign-key setter, `refresh_from_db`) are left alone. A dict or set keyed one way and looked up the other compares by hash and stays invisible.
- **A database default now applies on insert.** The models carry the schema's defaults as `db_default`, where an API's old copy often had none and wrote `NULL`. Audited 2026-10-30 across all four copies: the only such column was `entities.onboarding_saved_step` (default 9 = "finished"); onboarding-api's create now writes `NULL` explicitly, as Flask's does.
- **No pyright.** Django ships no type stubs, the same reason the Django APIs run only ruff.
- **`0001` is the only migration until the owner says otherwise (2026-11-03).** A schema change goes into the schema file (a fresh build runs it) and `0001`'s STATE half, and a database already at `0001` gets it from a hand-run patch in `minty_db/schema/patches/` (`python -m minty_db patch FILE [--apply]`: one transaction, rolled back unless `--apply`; `search_path` is the URL's schema, so a patch names none). Pinned by `test_the_xero_keys_patch_merges_duplicates_and_matches_a_fresh_build`.
- **The Xero unique keys (v0.4, 2026-11-03).** `entity_account_xero (account_id)` (`uq_eax_account`, so `account` is a `OneToOneField`), `entity_bill_account_xero (entity_id, xero_account_id)` (`uq_ebax_entity_xero_account`, a partial unique index `WHERE xero_account_id <> ''`: a code added by hand has no Xero id - NULL, or `''` as minty-payment-request-api writes it - and any number may exist) and `xero_contact_sync (entity_id, xero_contact_id)` (`uq_xcs_entity_contact`). Their syncs read-then-inserted, so two at once wrote a row twice (QA: onboarding's duplicate chart of accounts). The patch `2026-11-03_xero_unique_keys.sql` first keeps one row per key (a ticked one, the default bill code, the oldest contact) and moves every reference to a removed contact (`report_expense.contact_id`, `bill.contact_id`, the three `entity_pettycash_settings` contact columns) to the one kept.

- **Xero optional, EXPAND (v0.5, 2026-11-10).** The design is `Minty/docs/modernisation/xero_optional_database.md` (its SQL: `minty-xero.sql`, part 1 here). Additive: Minty's own account and supplier columns beside the Xero ones, the Xero copies (`xero_account`, `xero_contact`), `account_module`, `account_change_log`/`contact_change_log`, `account_match_draft`, `account_template`, and onboarding's answers on `entities`. Triggers keep the new columns in step while services still write only the old ones, so nothing has to change in an API to take it. It is the schema file's last section (under `SET search_path = pettycash_test`), and `patches/2026-11-10_xero_optional_expand.sql` (with `_down.sql`) brings a database at `0001` there; schema changes stay baseline (owner, 2026-11-10).
  - **Function bodies survive the build's schema rename.** The build creates `pettycash_test` and renames it, and a PL/pgSQL body is text: the helper functions use SQL-standard `RETURN` bodies (stored parsed), and the trigger bodies reach their schema through `TG_TABLE_SCHEMA`, so they also work from a session whose `search_path` is elsewhere.
  - **Generated columns** (`account_info.class`, `account_info.active_xero_link`, `account_template.is_system`) are `GeneratedField`s, their rule written once in the generator's `GENERATED` and checked against the expression Postgres reports. A deferrable unique constraint (`uq_account_active_xero_link`) carries `deferrable=Deferrable.IMMEDIATE`. `DB_ONLY_UNIQUE` names the indexes the models leave to the database: `account_template`'s three (NULLS NOT DISTINCT, one on an expression), a catalogue no API writes.

## Where each database stands

Each database was checked column by column against the models before its baseline (`python -m minty_db migrate --baseline` records `0001` without running it).

| Database | State |
|---|---|
| Local `postgres` / `pettycashv3` | Baselined 2026-10-30 (0 differences) |
| Local `pettycashv3_data` / `pettycashv3` | Baselined 2026-10-30 (0 differences) |
| Supabase `development` | Brought up to date 2026-10-30: Minty's `i1a01` and 01's `entity_setup_summary` view had never reached it. Then 0 differences, baselined |
| Supabase `pettycashv3` | 0 differences (re-checked against v0.3), baselined 2026-11-03 |

Patches: `2026-11-03_xero_unique_keys.sql` applied 2026-11-03 on all four (owner: "do all"), each after a dry run, and a second run found nothing: local `postgres` (39 bill codes / 278 contacts merged, 33 references moved), `pettycashv3_data` (39 / 283 / 33), Supabase `development` (no duplicates; keys only), Supabase `pettycashv3` (39 / 284 / 33; the six touched tables saved first to Minty's git-ignored `backups/pg/supabase_pettycashv3_prexerokeys_20261103.dump`). All still record `0001` only.

`2026-11-03_slip_placeholders.sql` is a **data** repair, not a schema change, run the same way (owner, 2026-11-03: "Repair 68 + list the 3"). Until then minty-payment-request-web's bank slip upload made a 0.00 payment with no date to hold a slip when the bill had no payment yet. On a bill (not voided) with exactly one real payment, the holder's `payment_attachment` rows move onto it; with several, onto the next real payment recorded after the holder (owner, 2026-11-03: "go to the next payment recorded"). Then the holder is deleted - links first, since the delete cascades; it stops if any link would be lost. A bill whose real payments all came before the holder is listed for the owner; bills with none keep their holder. Minty's load does the same (`docs/schema/generators/gen.py` `SLIP_PLACEHOLDERS`). Applied 2026-11-03 on Supabase `pettycashv3` (owner: "just do the repair in supabase"), after a dry run, `payment` and `payment_attachment` saved first to Minty's git-ignored `backups/pg/supabase_pettycashv3_preslips_20261103.dump`: 67 holders folded, 69 slip links moved, none lost; 58 left (2 bills with several real payments - `MBIHAR-121128110626`, `MBIJAY-161745270726` - 52 with no real payment, 4 on voided bills); a second run found nothing; every bill's `amount_paid` still matches its completed payments. Run again the same day with the next-payment rule (`preslips2` saved first): 3 more folded - `MBIHAR-121128110626` and `MBIJAY-161745270726` onto their first payment, and `MBIMIC-095721070926`, a holder made 17:20 that day by the still-deployed old upload; 0 left after several payments, 52 with none, 4 voided. Not applied to the local databases or Supabase `development`.

`2026-11-10_xero_optional_expand.sql` (Xero optional, EXPAND; v0.5) applied 2026-11-10 on local `postgres` only, after a dry run and a snapshot (Minty's git-ignored `backups/pg/postgres_pre20261110.dump`): 4,815 of 5,184 accounts and 11,064 of 11,070 suppliers linked to their new Xero copies, none left unlinked at a company with an org; a second run stopped at the guard. Rehearsed first through Minty's v2->v3 load (ALL GREEN twice on `production-backup_20261104.dump`). Not applied: `pettycashv3_data` (built by the load, which has these in its baseline). Supabase `development` and `pettycashv3` have all four (below), so the APIs may now pin v0.5.

**Supabase `development`, 2026-11-10 (owner: "yes"):** all four 2026-11-10 patches applied in order (Xero optional, archived, tracker view, bill contacts), each after a dry run and a schema snapshot (Minty's git-ignored `backups/pg/supabase_development_pre{xerooptional,archived,tracker,billcontacts}_20261110.dump`): 145 of 232 accounts and 234 of 234 suppliers linked, 6 companies (none archived) on the tracker, 3 bills relinked (0 left). Then compared with local `postgres` (the same four applied): 0 differences in columns, views, triggers, functions, constraints and indexes. **Supabase `pettycashv3`, 2026-11-10 (owner: "yes")**: the same four, each after a dry run and a snapshot (`backups/pg/supabase_pettycashv3_pre{xerooptional,archived,tracker,billcontacts}_20261110.dump`): 5,054 of 5,423 accounts and 11,293 of 11,299 suppliers linked (136 bank accounts with no code), 86 companies (none archived) on the tracker, 1,548 of 1,550 bills relinked (the 2 left are of the companies deleted 2026-11-09, SWITCH 2c-0); a second run of the repair found nothing more. Compared with local `postgres`: 0 differences but `qa_status`, a view made by hand on Supabase before today that no repo creates or reads.

`2026-11-10_entity_archived.sql` (also v0.5, separate from EXPAND, either order): `entities.archived_at` and `archived_by_user_id` (FK `fk_entities_archived_user`, ON DELETE SET NULL) - archiving a company outside `status`, which the Xero paths rewrite and CONTRACT rebuilds. In the baseline (`entities`' CREATE TABLE); owner-approved 2026-11-10; applied that day on local `postgres` only, after a snapshot (`backups/pg/postgres_prearchived20261110.dump`; 83 companies, none archived). Pinned by `test_the_archived_patch_matches_a_fresh_build_and_its_down_patch_reverses_it`.

`2026-11-10_tracker_view.sql` (also v0.5; owner, requested by the github-67 session): the client tracker's view, folded in from tracker-backend's retired `tracker_view_v3.sql` - fifteen columns (`pc_latest_submitted_date`, `country_code`, `timezone` added; the counts and module flags never NULL) and no archived company (`entities.archived_at IS NULL`). Run it after the archived patch (its guard says so); DROP + CREATE (a column can't be inserted mid-list); re-runnable. The archived `_down.sql` puts the twelve-column view back first, since the view reads `archived_at`. Owner-approved 2026-11-10; applied that day on local `postgres` only (snapshot `backups/pg/postgres_pretracker20261110.dump`; 83 companies on the tracker). Pinned by `test_the_tracker_view_patch_matches_a_fresh_build_and_leaves_archived_companies_out`.

`2026-11-12_xero_matching.sql` (**v0.6**; Phase 3 of the Xero matching, owner-approved 2026-11-12):
the enum `xero_matching` ('first','new_accounts','new_org','change') and `entities.xero_matching`
(NULL = no matching open), set and cleared by minty-accounts-api. The patch marks `first` any company
Phase 2 has mid-matching (keeps its books in Minty, an organisation recorded, own accounts). In the
baseline (the schema file's last section); applied 2026-11-12 on local `postgres` only (87 companies,
2 marked: My Company 2 and 3). Not applied on Supabase yet: every API pins v0.6 only after both
Supabase schemas have it. Pinned by
`test_the_xero_matching_patch_matches_a_fresh_build_backfills_and_its_down_patch_reverses_it`.

`2026-11-12_sale_info_owner.sql` (**v0.7**; owner-approved 2026-11-12): `sale_info.entity_id` - who
owns a sales method. NULL = Minty's catalogue (offered to every company; never renamed or deleted, a
company only takes it off its own list); set = the company that typed it, its own to rename or
delete. `UNIQUE (sale_name)` became two expression indexes, `lower(sale_name)` among Minty's rows
and within a company (`DB_ONLY_UNIQUE`: the APIs check names themselves). The owner's backfill:
Minty's are Visa, Mastercard, Alipay, WeChat Pay, UnionPay, Amex, Octopus, Payme, JCB, Food Panda,
Keeta, OpenRice, Deliveroo and Cash; a case twin of one (MasterCard, PayMe, payme) merges into it
(a company holding both keeps one link, a report holding both one row, summed); a row nobody uses
goes; every other row is its company's own, a name several companies used split into one row each. **GCash moves to Electronic** (owner, 2026-11-12: a card and wallet payment, not delivery) - every
company's row, so past reports count it there.
Applied 2026-11-12 on local `postgres` only (3 twins merged, 9 copies, 14 Minty's, 53 companies'
own). Not on Supabase yet: after v0.6, on the owner's yes. The down-patch folds the copies back and
restores `UNIQUE (sale_name)`. Pinned by
`test_the_sale_info_owner_patch_matches_a_fresh_build_backfills_and_its_down_patch_reverses_it`.

`2026-11-13_expense_description.sql` (**v0.8**; owner, 2026-11-13): `report_expense.remarks` becomes
`report_expense.description`. What a person types in an expense line's Description field always
lived in `remarks` (VARCHAR(300)); the TEXT `description` beside it was never written (0 of 16,599
lines on the 2026-11-04 copy of production), so it is dropped and `remarks` renamed, keeping its
type and every value. The patch stops with nothing changed when any line holds a `description`.
**Release order:** code before v0.8 reads `remarks` and fails on every expense line once the patch
is in, and development's services share production's data until the December cutover - apply it as
minty-petty-cash-api's v0.8 build goes live. Flask's code still names `remarks` (owner: left as is;
nothing runs it). Pinned by `test_the_expense_description_patch_keeps_every_remark_and_matches_a_fresh_build`.
Applied 2026-11-13 on local `postgres` and `pettycashv3_data` only; **not yet on Supabase**
(`pettycashv3` or `development`).

`2026-11-13_entity_subscriber.sql` (**v0.9**; owner-approved 2026-11-13): `entities.subscriber_user_id`
(UUID NULL, FK `fk_entities_subscriber_user` -> `user`, ON DELETE SET NULL) - who holds a company's
subscription. Onboarding writes the creator, a handover moves it, and confirming billing makes that
person `entity_module_subscription.payer_user_id`, which the column then mirrors. Only the subscriber
may start a trial, activate, change modules or hand over (minty-subscription-api); NULL = not
assigned, view-only for everyone. The patch copies an existing payer into the column; every other
company stays NULL until assigned by hand (Minty's `scripts/schema_migration/subscribers.py`, the
owner's list at the December load). Not re-runnable (a second run stops at the guard); the way back
is its `_down.sql`. v0.9 contains v0.8, so a service on v0.9 needs BOTH patches in its database.
Applied 2026-11-13 on local `postgres` (1 subscriber), `pettycashv3_data` (0), Supabase `pettycashv3`
(3 payers copied, then 6 assigned by hand - 9 subscribers; 2026-11-16 Angelika's 3 sole-admin companies
added - 12) and Supabase `development` (2). Local `postgres` got Angelika on her 6 unassigned companies
the same day (7 subscribers). Old code
ignores the column. Pinned by
`test_the_subscriber_patch_matches_a_fresh_build_copies_the_payers_and_its_down_patch_reverses_it`.

`2026-11-16_entity_one_connected_org.sql` (**v0.10**; owner-approved 2026-11-16): the unique index
`uq_entities_connected_xero_org` - one Xero organisation, at most one company whose `status` is not
`disconnected`. The rule itself is old (Flask's "one org = one entity", tightened 2026-10-09) and
accounts-api holds it at connect time (`connect.live_org_claimant`); the index closes the race of two
connects at once. A disconnected company keeps its organisation (2026-11-10) and is never counted; an
`onboarding` one holding it is. The model carries it (`PARTIAL_UNIQUE`). No data changes; a database
already breaking the rule is refused with each clashing organisation named. Not re-runnable (guard);
the way back is its `_down.sql`. Applied 2026-11-16, each after a dry run, on local `postgres` (50
holding, 10 disconnected keeping one), `pettycashv3_data` (48, 6), Supabase `development` (1, 0) and
Supabase `pettycashv3` (52, 8; `entities`' definition saved first to Minty's git-ignored
`backups/pg/supabase_{development,pettycashv3}_preoneorg_20261116.sql`). All five APIs pin v0.10 the
same day (accounts-api's duplicate-claimant test rewritten: two connected companies on one
organisation can no longer exist). Pinned by `test_the_one_connected_org_patch_matches_a_fresh_build_and_holds_the_rule`.

`2026-11-17_entity_sales_ticks.sql` (**v0.11**; owner-approved 2026-11-17): `entities.sells_electronic`
and `entities.sells_delivery` (BOOLEAN NULL, beside `uses_sales_cash`) - onboarding's sales accounts
screen (Figma 464:73 row 1): Sales - Electronic Payment and Sales - Delivery ticked or not, which
decides the sales-method lists Petty Cash Settings asks for. Sales - Cash is `uses_sales_cash`. NULL =
not chosen: minty-onboarding-api lets the business type pick. No backfill. Not re-runnable (guard);
the way back is its `_down.sql`. Applied 2026-11-17, each after a dry run, on local `postgres` (87
companies), Supabase `development` (6) and Supabase `pettycashv3` (90) - all NULL; not on
`pettycashv3_data`. minty-onboarding-api's `requirements.txt` names
v0.11 (needs this tag pushed). Old code ignores the columns. Pinned by
`test_the_sales_ticks_patch_matches_a_fresh_build_and_its_down_patch_reverses_it`.

`2026-11-17_sales_account_codes.sql` (**v0.12**; owner, 2026-11-17: "each sales should be tied"): `entity_pettycash_settings.electronic_sale_account_id` and `delivery_sale_account_id` (UUID NULL, FKs `fk_eps_elecsale_acct` / `fk_eps_delsale_acct` -> `account_info`, ON DELETE SET NULL) - Sales - Electronic Payment's and Sales - Delivery's account codes, beside `cash_sale_account_id` (Sales - Cash's). Petty Cash Settings' Account mapping picks them (optional, shown while that sales account is ticked); the Minty path links 4001 and 4002 (4004 for General) from the sheet; the day's sales invoice gets a line for each with a code. No backfill. Not re-runnable (guard); the way back is its `_down.sql`. Applied 2026-11-17, each after a dry run, on local `postgres`, Supabase `development` (4 companies with settings) and Supabase `pettycashv3` (74); not on `pettycashv3_data`. onboarding-api, petty-cash-api and accounts-api pin v0.12. Pinned by `test_the_sales_account_codes_patch_matches_a_fresh_build_and_its_down_patch_reverses_it`.

`2026-11-18_ai_policy_and_reads.sql` (**v0.13**; owner-approved 2026-11-18): the AI readers' settings and each company's allowance. `ai_policy` - one row (`CHECK id = 1`, like `billing_policy`): `primary_model`, `backup_model` (tried once when the first errors, times out or is rate-limited), `default_grant` (the one-time grant a company is given on its first read, `{"tokens", "reads", "days"}`; NULL = none) and `limit_rules` (extra caps over every company, all applying, `{"reads", "tokens", "period_days"}`). Changed by an UPDATE, never a release. `ai_grant` - a company's allowances (`tokens_total`/`reads_total`, `expires_at`, `source` default|manual; `uq_ai_grant_one_default`: the default once per company, ever; a top-up is another row). `ai_read` - one row per read asked for (`pending` -> `ok` | `failed`), charged to a grant (`grant_id`, ON DELETE SET NULL), with the model that answered and the chain tried. A company's grants and reads go with the company. The policy row is `seed_catalogue.sql`'s (preview: `gemini-3.5-flash-lite` then `gemini-3.8-flash`, default grant `{"tokens": 20000}`, no caps), which the patch also inserts. The JSON columns have no column default (the generator would write a JSON string). Not re-runnable (guard); the way back is its `_down.sql`. Applied 2026-11-18 on local `postgres`, and 2026-11-19 on Supabase `pettycashv3` and `development` (owner: "yes"), each after a dry run; a second run stops at the guard on both. Petty-cash-api, payment-request-api and accounts-api pin v0.13. Pinned by `test_the_ai_patch_matches_a_fresh_build_seeds_the_policy_and_its_down_patch_reverses_it`.

`2026-11-19_merges_and_report_version.sql` (**v0.14**; the owner's decisions doc "Minty Xero Sync & Report Decisions", M2 and R2): `minty_merge` - one row per merge of two of a company's accounts or two of its contacts (`kind` account|contact, `merged_id`, `kept_id` - no FK, they name an `account_info` or `xero_contact_sync` row by kind; `reason` user|xero_matching|merged_in_xero; `merged_by_user_id` ON DELETE SET NULL; a company's merges go with it). `minty_merge_record` - each record a merge moved (`table_name`, `column_name`, `record_id`), so its original can always be found; it goes with its merge. `report.edit_version` (INTEGER NOT NULL DEFAULT 0, `>= 0`) - the version a Petty Cash step save carries, a save from an older one refused - and `report.saved_by_user_id` (FK `user`, ON DELETE SET NULL) - who saved last. Not re-runnable (guard); the way back is its `_down.sql`. Applied 2026-11-19 on local `postgres` (6,035 reports at version 0), then the same day on Supabase `development` (12) and `pettycashv3` (6,092) (owner: "yes"), each after a dry run; a second run stops at the guard, and the five tables match local column by column. Pinned by `test_the_merge_patch_matches_a_fresh_build_and_its_down_patch_reverses_it`.

`2026-11-19_exchange_rate.sql` (**v0.14**, owner 2026-11-19): `report_expense` and `bill` each gain six nullable columns saying how an AI-read amount in another currency was converted - `original_currency` CHAR(3), `original_amount` NUMERIC(14,2), `exchange_rate` NUMERIC(20,10), `exchange_rate_date` (the day the rate is for: Frankfurter v1 gives a weekend or holiday the previous business day), `exchange_rate_basis` (`receipt` = the document's date, `report_date` = the report's or the bill's entry day) and `exchange_rate_source` (`Frankfurter`). `amount` stays in the company currency. A CHECK per table (`ck_report_expense_exchange`, `ck_bill_exchange`) holds all six set - rate above 0, a known basis - or none; each part says `IS NOT NULL` itself, because a NULL inside a CHECK passes. Not re-runnable (guard); the way back is its `_down.sql`. Applied 2026-11-19 on local `postgres`, then the same day on Supabase `development` and `pettycashv3` (owner: "yes"), each after a dry run; the columns match local. Pinned by `test_the_exchange_rate_patch_matches_a_fresh_build_and_holds_all_six_or_none`.

`2026-11-20_ai_reader_settings.sql` (**v0.15**, owner 2026-11-20): `ai_policy` gains the AI readers' settings that were each service's environment (`EXPENSE_AI_*` / `BILL_AI_*`) - `receipt_reader_on` and `invoice_reader_on` (Petty Cash's receipt reader, Payment Request's invoice reader; default off, a reader ships dark), `timeout_s` (5-120, default 25), `max_output_tokens` (256-65536, default 4096, thinking included), `thinking_level` (`minimal`|`low`|`medium`|`high`, default `low`), `max_file_mb` (1-20, default 10) and `location` (the Vertex AI region, default `asia-southeast1`; lower-case letters, digits and hyphens - it decides which models exist, so it sits beside them), each rule a CHECK. The patch sets both readers on, keeping what the services ran with; old code ignores the columns, so the patch goes first. Read by minty-shared v0.11's `ai_allowance.Policy.reader()`. The seed row is now `gemini-3.5-flash` (the model Vertex AI serves in `asia-southeast1`), no backup, both readers on. Not re-runnable (guard); the way back is its `_down.sql`. Not applied anywhere yet. Pinned by `test_the_ai_settings_patch_matches_a_fresh_build_keeps_the_readers_on_and_holds_its_ranges`; the 2026-11-18 test re-applies it after its own down-and-up.

`2026-11-20_ai_grant_ended.sql` (**v0.16**, owner 2026-11-20): `ai_grant` gains `ended_at` (TIMESTAMPTZ) and `ended_by` (VARCHAR(255), the superuser's email) - a superuser can end a company's AI grant early from minty-web's AI allowances mode (minty-accounts-api `POST /api/me/ai/companies/<id>/grants/<grant id>/end`). Ending also sets `expires_at` to now, which is what stops the allowance counting it (minty-shared's `ai_allowance` is unchanged); the two columns are for the dialog's "Ended ... by ...". `ck_ai_grant_ended`: both set or both empty, each part `IS NOT NULL` itself. An ended grant stays a grant, so the one-time default grant is never given again. Not re-runnable (guard); the way back is its `_down.sql`. Applied 2026-11-20 on local `postgres` only. Pinned by `test_the_grant_ended_patch_matches_a_fresh_build_and_holds_both_or_neither`.

`2026-11-23_long_xero_codes.sql` (**v0.17**, owner 2026-11-23): `account_code_from_xero` reads any Xero code longer than 10 characters as a name, so `account_info.code` (VARCHAR(10)) stays empty for every account type - before, only `BANK` accounts. A Xero organisation sent `CURRENT` accounts whose "code" was the account's name ("Amount due from LEE Min Ho"); `trg_account_info_fill` put it in `code`, the insert was refused ("value too long for type character varying(10)") and the whole connect, or the account sync after a matching, failed (18-19 Nov 2026, "OTT - Noodle Town (Demo)"). `xero_code` keeps Xero's full value and is what Petty Cash and Payment Requests publish with, so nothing sent to Xero changes. No backfill (no row could hold such a code). Re-runnable (`CREATE OR REPLACE`); the way back is its `_down.sql`. Pinned by `test_a_xero_code_longer_than_ten_is_no_code_for_every_account_type`.

`2026-11-23_drop_ai_policy_location.sql` (**v0.17**, owner 2026-11-23: "no need for setting region"): `ai_policy.location` and `ck_ai_policy_location` (from v0.15) go - every AI read runs on Vertex AI's global endpoint (minty-shared v0.12: `ai.VERTEX_LOCATION = "global"`, `load_policy` selects named columns and no longer reads it). The model, `0001`'s STATE half and the seed lose it too. **Order:** apply it only after petty-cash-api and payment-request-api pin v0.17 - the services read named columns, but petty-cash-api's hand-run `manage.py ai_policy` loads the whole row through the model, which before v0.17 still declares `location`. Not re-runnable (guard); the way back is its `_down.sql` (the column back as `global`, with its CHECK). Pinned by `test_ai_policy_has_no_location_and_the_drop_patch_matches_a_fresh_build`; the v0.15 test now goes back to v0.16 first and applies this patch on the way up.

`2026-11-10_bill_contact_ids.sql` (a DATA repair, no schema change; owner: "fix it"): the v2->v3 load wrote Xero's ContactID into `bill.contact_id`, which names a `xero_contact_sync` row, so loaded bills opened with no supplier picked. Each such bill is linked by the Xero id in its company, else by the supplier's name (case and spaces ignored), else to a restored supplier row; a bill of a company that no longer exists is left (no row can be made for it). Re-runnable; the before/after SELECTs are the report. Applied 2026-11-10 on local `postgres` only (snapshot `backups/pg/postgres_prebillcontacts20261110.dump`): 1,548 of 1,550 linked, the 2 left belong to the companies deleted on 2026-11-09 (Minty's SWITCH 2c-0). Minty's load runs the same statements at the end of 03 (`gen.py` `BILL_CONTACTS`, check R14; rehearsed ALL GREEN). Pinned by `test_the_bill_contact_repair_links_each_bill_to_a_supplier_row`.

`pettycashv3` (and local `postgres`) also hold `sessions`, Flask-Session's table. It is outside the schema file and has no model; it goes with Flask's session cutover.

## Open

- Flask's `docs/schema/generators/audit_models.py` should read `minty-db` too. That's a Minty change, made when Alembic stops (Phase 0, step 5).
- The catalogue loader (`seed_catalogue.sql` is packaged; `Minty/scripts/load_catalogue.py`'s schema-renaming load moves here when Minty stops owning it). `00_enum_coverage_check.sql` (enums must cover what the code produces) moves here with the API switches.
- `py-package.yml` in `.github` for both Python packages, a GitHub-visible change.
