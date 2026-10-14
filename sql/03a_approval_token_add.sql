-- ═══════════════════════════════════════════════════════════════════
-- 03a · Approval link token — PART A (safe, nothing breaks)
-- Project: arqx (quotes)
-- Adds a random token per approval + two functions the public approval
-- page uses instead of reading the table directly. Old ?id= links keep
-- working for events that haven't happened yet (transition period).
-- Run PART A → deploy code → test → run 03b.
-- ═══════════════════════════════════════════════════════════════════
begin;

-- 1. Random, unguessable token per approval (existing rows get one too)
alter table public.quote_approvals
  add column if not exists public_token uuid not null default gen_random_uuid();
create unique index if not exists quote_approvals_public_token_key
  on public.quote_approvals (public_token);

-- 2. Finds ONE approval row: by token, or (transition only) by old numeric id
--    Old ?id= links work only for rows created before the cutoff and for
--    events from a week ago onward. New links always use the token.
create or replace function public._approval_find(p_token uuid, p_quote_id text)
returns public.quote_approvals
language sql stable security definer set search_path = public as $$
  select a.* from public.quote_approvals a
  where (p_token is not null and a.public_token = p_token)
     or (p_token is null and p_quote_id is not null
         and a.quote_id = p_quote_id
         and a.created_at < timestamptz '2026-10-16 00:00+03'
         and (a.event_date is null or a.event_date >= current_date - 7))
  limit 1;
$$;
revoke all on function public._approval_find(uuid, text) from public, anon, authenticated;

-- 3. Read for the client page (never returns signature image or IP)
create or replace function public.approval_get(p_token uuid default null, p_quote_id text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r public.quote_approvals;
begin
  r := public._approval_find(p_token, p_quote_id);
  if r.id is null then return null; end if;
  return to_jsonb(r) - 'signature_image' - 'ip_address';
end $$;

-- 4. Client approves: marks approved, stores signature (optional),
--    and for a reservation moves the quote from draft → reserved
--    (this last part was silently failing before).
create or replace function public.approval_submit(
  p_token uuid default null, p_quote_id text default null, p_signature text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare r public.quote_approvals;
begin
  r := public._approval_find(p_token, p_quote_id);
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status = 'approved' then
    return jsonb_build_object('ok', true, 'already', true, 'approved_at', r.approved_at);
  end if;
  if p_signature is not null and length(p_signature) > 600000 then
    return jsonb_build_object('ok', false, 'error', 'signature_too_large');
  end if;

  update public.quote_approvals
     set status = 'approved',
         approved_at = now(),
         signature_image = coalesce(p_signature, signature_image)
   where id = r.id;

  if r.kind = 'reservation' and r.quote_id ~ '^[0-9]+$' then
    update public.qz_quotes
       set status = 'reserved'
     where id = r.quote_id::int and (status is null or status = 'draft');
  end if;

  return jsonb_build_object('ok', true, 'already', false, 'approved_at', now());
end $$;

grant execute on function public.approval_get(uuid, text)          to anon, authenticated;
grant execute on function public.approval_submit(uuid, text, text) to anon, authenticated;

commit;

-- Check: every approval has a token, functions exist
select count(*) as approvals, count(public_token) as with_token from public.quote_approvals;
select proname from pg_proc where proname in ('approval_get','approval_submit','_approval_find');
