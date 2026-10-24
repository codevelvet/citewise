#!/bin/sh
set -e

FORBIDDEN_PUBLIC_IP="8.8.8.8"     # A public IP that SHOULD be blocked

echo "=== [PRE-LAUNCH] devcontainer security verification ==="

# 1. OUTBOUND CHECK: Verify Data Exfiltration Prevention is Active
fail() {
  echo "❌ CRITICAL SECURITY FAILURE: $1" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || fail "curl not installed; cannot verify egress"

echo "Testing egress restrictions..."
for url in "https://$FORBIDDEN_PUBLIC_IP" "http://$FORBIDDEN_PUBLIC_IP"; do
  rc=0
  curl -sS -o /dev/null --connect-timeout 3 --max-time 5 "$url" 2>/dev/null || rc=$?
  case "$rc" in
    7|28) ;;  # 7 = couldn't connect (REJECT), 28 = timed out (DROP): blocked
    *) fail "egress to $url not blocked (curl exit $rc)" ;;
  esac
done

# 2. DATABASE CHECK: Verify permissions
echo "Testing database restrictions..."
check_database() {
  command -v psql >/dev/null 2>&1 || fail "psql not installed; cannot verify database restrictions"

  # Attributes and memberships that amount to superuser, or to reading/writing
  # server files or running programs on the database host.
  sql="SELECT 'ok:' || concat_ws(',',
         CASE WHEN r.rolsuper       THEN 'superuser'  END,
         CASE WHEN r.rolcreaterole  THEN 'createrole' END,
         CASE WHEN r.rolreplication THEN 'replication' END,
         CASE WHEN r.rolbypassrls   THEN 'bypassrls'  END,
         CASE WHEN EXISTS (SELECT 1 FROM pg_roles s
                           WHERE s.rolsuper AND pg_has_role(r.oid, s.oid, 'MEMBER'))
              THEN 'member-of-superuser' END,
         CASE WHEN pg_has_role(r.oid, 'pg_read_server_files', 'MEMBER')
                OR pg_has_role(r.oid, 'pg_write_server_files', 'MEMBER')
                OR pg_has_role(r.oid, 'pg_execute_server_program', 'MEMBER')
              THEN 'server-file-or-program-access' END)
       FROM pg_roles r WHERE r.rolname = current_user"

  rc=0
  out=$(PGPASSWORD="$DB_PASSWORD" PGCONNECT_TIMEOUT=5 \
        psql -h "$DB_HOST" -U "$DB_USER" -d citewise_development \
             -X -tA -v ON_ERROR_STOP=1 -c "$sql" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || fail "could not query database role (psql exit $rc)"
  [ "$out" = "ok:" ] || fail "database role $DB_USER has elevated privileges: ${out#ok:}"
  echo "✅ Database role $DB_USER has no superuser-level privileges."

  # The admin account must be refused by pg_hba.conf before any password is asked.
  out=$(PGCONNECT_TIMEOUT=5 psql -h "$DB_HOST" -U postgres -d postgres -w -X -c 'SELECT 1' 2>&1) && \
    fail "connected to the database as postgres"
  case "$out" in
    *"pg_hba.conf rejects connection"*) echo "✅ Superuser login over the network is rejected." ;;
    *) fail "postgres login failed for an unexpected reason: $out" ;;
  esac
}
check_database

# 3. DATABASE CHECK: Verify no copy to/from container
  # Running a program on the database host must be refused.
  out=$(PGPASSWORD="$DB_PASSWORD" PGCONNECT_TIMEOUT=5 \
        psql -h "$DB_HOST" -U "$DB_USER" -d citewise_development \
             -X -v ON_ERROR_STOP=1 -c "COPY (SELECT 1) TO PROGRAM 'true'" 2>&1) && \
    fail "COPY TO PROGRAM succeeded: $DB_USER can run programs on the database host"
  case "$out" in
    *"permission denied to COPY to or from an external program"*)
      echo "✅ COPY TO PROGRAM is denied." ;;
    *) fail "COPY TO PROGRAM failed for an unexpected reason: $out" ;;
  esac

echo "🛡️ All security checks passed. Initializing AI Agent..."
echo "=================================================="


