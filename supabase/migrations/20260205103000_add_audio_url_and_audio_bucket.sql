alter table journal_sessions
    add column if not exists audio_url text;

insert into storage.buckets (id, name, public)
values ('journal-audio', 'journal-audio', false)
on conflict (id) do nothing;

create policy "Users can upload journal audio"
    on storage.objects for insert to authenticated
    with check (
        bucket_id = 'journal-audio'
        and auth.uid() = owner
    );

create policy "Users can read journal audio"
    on storage.objects for select to authenticated
    using (
        bucket_id = 'journal-audio'
        and auth.uid() = owner
    );
