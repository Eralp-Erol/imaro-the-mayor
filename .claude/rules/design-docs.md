---
paths:
  - "design/**"
---
# Design documents

- `design/foundation/` is immutable canon (hook-protected, SHA-256 manifest via `tools/canon-check.sh`). Never edit, move or "fix" it.
- `design/decisions/D-NNN-*.md` only records decisions the **user actually stated in chat** (quote them, date them). Agents never author decisions on the user's behalf.
- `design/specs/` are working models (status ÇALIŞMA MODELİ unless a decision says otherwise); every spec cites REQ ids and lists open questions.
- Keep the status vocabulary exact: KANONİK / ONAYLANMIŞ YÖN / ÇALIŞMA MODELİ / AÇIK / REDDEDİLDİ. Don't promote a status without a user decision.
