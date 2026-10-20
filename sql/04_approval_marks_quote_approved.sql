-- 04 — A signed quote approval now moves the quote to "approved" (it used to stay "reserved").
-- Reservation links still move draft → reserved, as before. Cancelled / postponed are never touched.
begin;

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

  if r.quote_id ~ '^[0-9]+$' then
    if r.kind = 'reservation' then
      update public.qz_quotes
         set status = 'reserved'
       where id = r.quote_id::int and (status is null or status = 'draft');
    else
      update public.qz_quotes
         set status = 'approved'
       where id = r.quote_id::int and (status is null or status in ('draft', 'reserved', 'pending'));
    end if;
  end if;

  return jsonb_build_object('ok', true, 'already', false, 'approved_at', now());
end $$;
grant execute on function public.approval_submit(uuid, text, text) to anon, authenticated;

-- One-time repair: quotes the client already signed but that are still stuck in draft / reserved / pending
update public.qz_quotes q
   set status = 'approved'
  from public.quote_approvals a
 where a.quote_id = q.id::text
   and a.status = 'approved'
   and coalesce(a.kind, '') <> 'reservation'
   and (q.status is null or q.status in ('draft', 'reserved', 'pending'))
returning q.id, q.client_name, q.event_date;

commit;
