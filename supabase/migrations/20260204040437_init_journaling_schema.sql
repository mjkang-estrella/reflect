create extension if not exists "pgcrypto";

create table journal_sessions (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    started_at timestamptz not null default now(),
    ended_at timestamptz,
    status text not null default 'draft' check (status in ('draft', 'completed')),
    mode text not null default 'text' check (mode in ('text', 'voice')),
    title text,
    final_text text,
    duration_seconds integer,
    tags text[] not null default '{}',
    mood text,
    is_favorite boolean not null default false
);

create index journal_sessions_user_started_idx on journal_sessions (user_id, started_at desc);

create table journal_entries (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references journal_sessions(id) on delete cascade,
    created_at timestamptz not null default now(),
    text text not null,
    source text not null check (source in ('user', 'ai'))
);

create index journal_entries_session_created_idx on journal_entries (session_id, created_at);

create table session_questions (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references journal_sessions(id) on delete cascade,
    created_at timestamptz not null default now(),
    question text not null,
    coverage_tag text,
    status text not null default 'shown' check (status in ('shown', 'answered', 'ignored')),
    answered_text text
);

create index session_questions_session_created_idx on session_questions (session_id, created_at);

create table daily_summaries (
    session_id uuid primary key references journal_sessions(id) on delete cascade,
    created_at timestamptz not null default now(),
    summary_json jsonb not null
);

create table me_db (
    user_id uuid primary key references auth.users(id) on delete cascade,
    profile_json jsonb not null default '{}'::jsonb,
    state_json jsonb not null default '{}'::jsonb,
    patterns_json jsonb not null default '{}'::jsonb,
    trust_json jsonb not null default '{}'::jsonb,
    updated_at timestamptz not null default now()
);

create table transcript_chunks (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references journal_sessions(id) on delete cascade,
    created_at timestamptz not null default now(),
    text text not null,
    confidence numeric,
    provider text
);

create index transcript_chunks_session_created_idx on transcript_chunks (session_id, created_at);

alter table journal_sessions enable row level security;
alter table journal_entries enable row level security;
alter table session_questions enable row level security;
alter table daily_summaries enable row level security;
alter table me_db enable row level security;
alter table transcript_chunks enable row level security;

create policy "Users can insert sessions"
    on journal_sessions for insert to authenticated
    with check (auth.uid() = user_id);

create policy "Users can select sessions"
    on journal_sessions for select to authenticated
    using (auth.uid() = user_id);

create policy "Users can update sessions"
    on journal_sessions for update to authenticated
    using (auth.uid() = user_id);

create policy "Users can delete sessions"
    on journal_sessions for delete to authenticated
    using (auth.uid() = user_id);

create policy "Users can insert entries"
    on journal_entries for insert to authenticated
    with check (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = journal_entries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can select entries"
    on journal_entries for select to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = journal_entries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can update entries"
    on journal_entries for update to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = journal_entries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can delete entries"
    on journal_entries for delete to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = journal_entries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can insert questions"
    on session_questions for insert to authenticated
    with check (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = session_questions.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can select questions"
    on session_questions for select to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = session_questions.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can update questions"
    on session_questions for update to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = session_questions.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can delete questions"
    on session_questions for delete to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = session_questions.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can insert summaries"
    on daily_summaries for insert to authenticated
    with check (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = daily_summaries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can select summaries"
    on daily_summaries for select to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = daily_summaries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can update summaries"
    on daily_summaries for update to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = daily_summaries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can delete summaries"
    on daily_summaries for delete to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = daily_summaries.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can insert me db"
    on me_db for insert to authenticated
    with check (auth.uid() = user_id);

create policy "Users can select me db"
    on me_db for select to authenticated
    using (auth.uid() = user_id);

create policy "Users can update me db"
    on me_db for update to authenticated
    using (auth.uid() = user_id);

create policy "Users can delete me db"
    on me_db for delete to authenticated
    using (auth.uid() = user_id);

create policy "Users can insert transcript chunks"
    on transcript_chunks for insert to authenticated
    with check (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = transcript_chunks.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can select transcript chunks"
    on transcript_chunks for select to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = transcript_chunks.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can update transcript chunks"
    on transcript_chunks for update to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = transcript_chunks.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );

create policy "Users can delete transcript chunks"
    on transcript_chunks for delete to authenticated
    using (
        exists (
            select 1 from journal_sessions
            where journal_sessions.id = transcript_chunks.session_id
              and journal_sessions.user_id = auth.uid()
        )
    );
