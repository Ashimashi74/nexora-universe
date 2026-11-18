-- NEXORA social media attachments: photos, audio/music and documents in Orbit chats.
-- Files are stored under <uid>/chat/ and can only be uploaded by their owner.

alter table public.nx_messages drop constraint if exists nx_messages_kind_check;
alter table public.nx_messages add constraint nx_messages_kind_check
  check (kind in ('text','art','shared','invite','system','call','photo','audio','file'));

create or replace function public.nx_send_message(p_chat uuid, p_kind text, p_text text, p_payload jsonb default '{}', p_reply_to uuid default null)
returns public.nx_messages
language plpgsql security definer set search_path = public as $$
declare k text; r text; m nx_messages;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select kind into k from nx_chats where id = p_chat;
  r := nx_chat_role(p_chat);
  if k is null or r is null then raise exception 'not_member'; end if;
  if k = 'channel' and r not in ('owner','admin') then raise exception 'channel_admins_only'; end if;
  if p_kind not in ('text','art','shared','invite','call','photo','audio','file') then raise exception 'bad_kind'; end if;
  if p_kind = 'text' and coalesce(trim(p_text),'') = '' then raise exception 'empty'; end if;
  if p_kind in ('photo','audio','file') and coalesce(p_payload->>'url','') = '' then raise exception 'missing_media'; end if;
  if p_kind in ('photo','audio','file') and length(coalesce(p_payload->>'name','')) > 255 then raise exception 'bad_media_name'; end if;
  insert into nx_messages(chat_id, author, author_name, kind, text, payload, reply_to)
    values (p_chat, auth.uid(), _nx_name(auth.uid()), p_kind, left(trim(coalesce(p_text,'')),4000), coalesce(p_payload,'{}'), p_reply_to)
    returning * into m;
  update nx_chats set last_msg_at = m.created_at where id = p_chat;
  update nx_chat_members set last_read_at = m.created_at where chat_id = p_chat and user_id = auth.uid();
  return m;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('nx-media', 'nx-media', true, 8388608, array[
  'image/jpeg','image/png','image/webp','image/gif',
  'audio/mpeg','audio/mp4','audio/wav','audio/ogg','audio/aac',
  'application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/zip','text/plain','application/json'
])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- Re-assert the folder boundary after the bucket update. A user can never write another user's folder.
drop policy if exists nx_media_insert on storage.objects;
create policy nx_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'nx-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists nx_media_update on storage.objects;
create policy nx_media_update on storage.objects for update to authenticated
  using (bucket_id = 'nx-media' and owner = auth.uid());
drop policy if exists nx_media_delete on storage.objects;
create policy nx_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'nx-media' and (storage.foldername(name))[1] = auth.uid()::text);
