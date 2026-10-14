-- ═══════════════════════════════════════════════════════════════════
-- 03b · Approval link token — PART B (lock the table)
-- Project: arqx (quotes)
-- Run ONLY after the new code is live and a test approval worked.
-- After this, outsiders can't list or edit approvals; the client page
-- works only through approval_get / approval_submit.
-- ═══════════════════════════════════════════════════════════════════
begin;

drop policy if exists "read by quote_id" on public.quote_approvals;
drop policy if exists "allow update"     on public.quote_approvals;

drop policy if exists "approvals_all_auth" on public.quote_approvals;
create policy "approvals_all_auth" on public.quote_approvals
  for all to authenticated using (true) with check (true);

commit;

-- Check: only authenticated policies should remain
select policyname, cmd, roles from pg_policies
where schemaname = 'public' and tablename = 'quote_approvals' order by 1;

-- ─── ROLLBACK (only if something broke) ─────────────────────────────
-- begin;
-- drop policy if exists "approvals_all_auth" on public.quote_approvals;
-- create policy "read by quote_id" on public.quote_approvals for select using (true);
-- create policy "allow update"     on public.quote_approvals for update using (true) with check (true);
-- commit;
