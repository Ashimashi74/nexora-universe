-- NEXORA private social media attachments: photos, audio/music and documents in Orbit chats.
-- Files are stored under <uid>/chat/<chat_uuid>/ and are never placed in public nx-media.

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
  if p_kind in ('photo','audio','file') and coalesce(p_payload->>'path','') = '' then raise exception 'missing_media'; end if;
  if p_kind in ('photo','audio','file') and length(coalesce(p_payload->>'name','')) > 255 then raise exception 'bad_media_name'; end if;
  if p_kind in ('photo','audio','file') and (
       split_part(p_payload->>'path','/',1) <> auth.uid()::text
       or split_part(p_payload->>'path','/',2) <> 'chat'
       or split_part(p_payload->>'path','/',3) <> p_chat::text
     ) then raise exception 'media_path_forbidden'; end if;
  insert into nx_messages(chat_id, author, author_name, kind, text, payload, reply_to)
    values (p_chat, auth.uid(), _nx_name(auth.uid()), p_kind, left(trim(coalesce(p_text,'')),4000), coalesce(p_payload,'{}'), p_reply_to)
    returning * into m;
  update nx_chats set last_msg_at = m.created_at where id = p_chat;
  update nx_chat_members set last_read_at = m.created_at where chat_id = p_chat and user_id = auth.uid();
  return m;
end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('nx-chat-media', 'nx-chat-media', false, 8388608, array[
  'image/jpeg','image/png','image/webp','image/gif',
  'audio/mpeg','audio/mp4','audio/wav','audio/ogg','audio/aac',
  'application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/zip','text/plain','application/json'
])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.nx_can_read_chat_media(object_name text) returns boolean
language plpgsql stable security definer set search_path = public, storage as $$
declare parts text[]; chat_id uuid;
begin
  if auth.uid() is null then return false; end if;
  parts := storage.foldername(object_name);
  if coalesce(array_length(parts, 1), 0) < 4 or parts[2] <> 'chat' then return false; end if;
  begin chat_id := parts[3]::uuid; exception when invalid_text_representation then return false; end;
  return parts[1] = auth.uid()::text or public.nx_is_chat_member(chat_id);
end $$;

revoke all on function public.nx_can_read_chat_media(text) from public, anon;
grant execute on function public.nx_can_read_chat_media(text) to authenticated;

drop policy if exists nx_chat_media_read on storage.objects;
create policy nx_chat_media_read on storage.objects for select to authenticated
  using (bucket_id = 'nx-chat-media' and public.nx_can_read_chat_media(name));
drop policy if exists nx_chat_media_insert on storage.objects;
create policy nx_chat_media_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'nx-chat-media'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (storage.foldername(name))[2] = 'chat'
    and public.nx_is_chat_member(((storage.foldername(name))[3])::uuid)
  );
drop policy if exists nx_chat_media_update on storage.objects;
create policy nx_chat_media_update on storage.objects for update to authenticated
  using (bucket_id = 'nx-chat-media' and owner = auth.uid() and public.nx_can_read_chat_media(name));
drop policy if exists nx_chat_media_delete on storage.objects;
create policy nx_chat_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'nx-chat-media' and owner = auth.uid());
