#!/usr/bin/env bash
# Apply pending Supabase migrations to the configured live project.
#
# Required:
#   SUPABASE_ACCESS_TOKEN   Supabase CLI access token
#   SUPABASE_DB_PASSWORD    Database password for the project (used by `supabase link`)
#
# Usage:
#   ./scripts/apply_supabase_live.sh --plan
#   ./scripts/apply_supabase_live.sh --apply
#
# The script is intentionally fail-closed. It never applies anything unless
# --apply is provided and the exact live-project confirmation is entered.

set -Eeuo pipefail
IFS=$'\n\t'

readonly EXPECTED_PROJECT_REF="eisstodgncimypdawisy"
readonly TARGET_MIGRATION="20261119000100_nx_chat_media.sql"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

MODE=""
PROJECT_REF="${SUPABASE_PROJECT_REF:-$EXPECTED_PROJECT_REF}"

usage() {
  cat <<'EOF'
Apply pending Supabase migrations to the NEXORA live project.

Usage:
  scripts/apply_supabase_live.sh --plan
  scripts/apply_supabase_live.sh --apply

Options:
  --plan    Link/check the project and show migration status only.
  --apply   Apply all pending migrations after an explicit production confirmation.
  --help    Show this help.

Environment:
  SUPABASE_ACCESS_TOKEN   Required by Supabase CLI authentication.
  SUPABASE_DB_PASSWORD    Required when linking the project.
  SUPABASE_PROJECT_REF    Optional; defaults to the NEXORA live project ref.

The Supabase CLI must be installed and available on PATH.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

while (($#)); do
  case "$1" in
    --plan) [[ -z "$MODE" ]] || fail "Choose only one mode"; MODE="plan" ;;
    --apply) [[ -z "$MODE" ]] || fail "Choose only one mode"; MODE="apply" ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown argument: $1 (use --help)" ;;
  esac
  shift
done

[[ -n "$MODE" ]] || { usage >&2; exit 2; }
[[ "$PROJECT_REF" == "$EXPECTED_PROJECT_REF" ]] || fail "Refusing unexpected project: $PROJECT_REF (expected $EXPECTED_PROJECT_REF)"
[[ -d "$REPO_ROOT/supabase/migrations" ]] || fail "supabase/migrations was not found"
[[ -f "$REPO_ROOT/supabase/migrations/$TARGET_MIGRATION" ]] || fail "Target migration is missing: $TARGET_MIGRATION"

require_command supabase

# Prevent applying an edited/staged/uncommitted migration by accident.
if ! git -C "$REPO_ROOT" diff-index --quiet HEAD -- supabase/migrations; then
  fail "Migration files have uncommitted changes. Commit/review them before applying live."
fi

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  fail "SUPABASE_ACCESS_TOKEN is not set"
fi
if [[ -z "${SUPABASE_DB_PASSWORD:-}" ]]; then
  fail "SUPABASE_DB_PASSWORD is not set"
fi

cd "$REPO_ROOT"
printf 'Target Supabase project: %s\n' "$PROJECT_REF"
printf 'Migration directory: %s\n' "$REPO_ROOT/supabase/migrations"
printf 'Target migration: %s\n\n' "$TARGET_MIGRATION"

# `link` is idempotent and makes --linked explicit; the password is read from
# the environment rather than being placed in shell history or process args.
supabase link \
  --project-ref "$PROJECT_REF" \
  --password "$SUPABASE_DB_PASSWORD" \
  >/dev/null

printf '%s\n' 'Current remote migration status:'
supabase migration list --linked

if [[ "$MODE" == "plan" ]]; then
  printf '\nPlan only: no migration was applied.\n'
  exit 0
fi

printf '\nThis is a LIVE Supabase database operation. It will apply every pending migration in this repository.\n'
printf 'Type exactly: APPLY %s\n' "$PROJECT_REF"
read -r confirmation
[[ "$confirmation" == "APPLY $PROJECT_REF" ]] || fail "Confirmation did not match; nothing was applied"

printf '\nApplying pending migrations...\n'
supabase db push --linked --yes

printf '\nMigration status after push:\n'
supabase migration list --linked
printf '\nDone. Confirm that %s is marked applied above.\n' "$TARGET_MIGRATION"
