-- P3 (docs/requirements-audit-2026-09-13.md): entity extraction only
-- recognized person/place/organization/date (0011_entities.sql). Adds
-- product, price, website, and technology — the four types the audit
-- flagged as missing. Existing rows are untouched; a plain
-- ADD CONSTRAINT/DROP CONSTRAINT swap since the old constraint's four
-- values are a strict subset of the new one's eight.

alter table entities drop constraint entities_type_check;

alter table entities add constraint entities_type_check
  check (type in (
    'person', 'place', 'organization', 'date',
    'product', 'price', 'website', 'technology'
  ));
