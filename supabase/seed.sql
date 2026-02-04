insert into journal_sessions (
    id,
    user_id,
    started_at,
    ended_at,
    status,
    mode,
    title,
    final_text,
    duration_seconds,
    tags,
    mood,
    is_favorite
) values
    (
        '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0001',
        '1d13b3bd-0a67-4004-b0de-035047e82d03',
        now(),
        now(),
        'completed',
        'text',
        'On the way home',
        'I keep thinking about that conversation from today. I don''t think I said what I meant.',
        0,
        array['Thoughts'],
        'reflective',
        false
    ),
    (
        '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0002',
        '1d13b3bd-0a67-4004-b0de-035047e82d03',
        now() - interval '1 day',
        now() - interval '1 day' + interval '112 seconds',
        'completed',
        'voice',
        'Morning reflection',
        'The day feels wide open. I want to be intentional about where I put my attention.',
        112,
        array['Personal', 'Mindfulness'],
        'calm',
        true
    ),
    (
        '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0003',
        '1d13b3bd-0a67-4004-b0de-035047e82d03',
        now() - interval '2 day',
        now() - interval '2 day',
        'completed',
        'text',
        'Notes from a walk',
        'Noticed how quiet the street was tonight. The air felt lighter.',
        0,
        array['Gratitude'],
        'content',
        false
    ),
    (
        '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0004',
        '1d13b3bd-0a67-4004-b0de-035047e82d03',
        now() - interval '3 day',
        now() - interval '3 day' + interval '64 seconds',
        'completed',
        'voice',
        'Work in progress',
        'I''m still untangling that project. Tomorrow I want to focus on the smallest next step.',
        64,
        array['Work'],
        'focused',
        false
    ),
    (
        '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0005',
        '1d13b3bd-0a67-4004-b0de-035047e82d03',
        now() - interval '4 day',
        now() - interval '4 day',
        'completed',
        'text',
        'Evening recap',
        'Dinner with friends felt grounding. I should plan more of these.',
        0,
        array['Friends'],
        'warm',
        false
    ),
    (
        '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0006',
        '1d13b3bd-0a67-4004-b0de-035047e82d03',
        now() - interval '5 day',
        now() - interval '5 day' + interval '90 seconds',
        'completed',
        'voice',
        'Soft reset',
        'Today was slow. I gave myself permission to rest and let the list wait.',
        90,
        array['Rest'],
        'relieved',
        false
    )
on conflict (id) do nothing;

insert into journal_entries (session_id, created_at, text, source)
select id, started_at, final_text, 'user'
from journal_sessions
where user_id = '1d13b3bd-0a67-4004-b0de-035047e82d03'
  and not exists (
      select 1 from journal_entries
      where journal_entries.session_id = journal_sessions.id
        and journal_entries.source = 'user'
  );

insert into session_questions (session_id, question, coverage_tag, status)
select id, question, 'follow_up', 'shown'
from (
    values
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0002'::uuid,
            'What would the best version of yourself do?'
        ),
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0004'::uuid,
            'What would the boldest version of you try next?'
        ),
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0006'::uuid,
            'What would the boldest version of you try next?'
        )
) as seed_questions(id, question)
where exists (
    select 1 from journal_sessions
    where journal_sessions.id = seed_questions.id
)
  and not exists (
      select 1 from session_questions
      where session_questions.session_id = seed_questions.id
        and session_questions.question = seed_questions.question
  );

insert into transcript_chunks (session_id, created_at, text, confidence, provider)
select journal_sessions.id, started_at, chunk_text, chunk_confidence, 'on_device'
from (
    values
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0002'::uuid,
            'The day feels wide open.',
            0.93
        ),
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0002'::uuid,
            'I want to be intentional about where I put my attention.',
            0.91
        ),
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0004'::uuid,
            'I''m still untangling that project.',
            0.9
        ),
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0004'::uuid,
            'Tomorrow I want to focus on the smallest next step.',
            0.89
        ),
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0006'::uuid,
            'Today was slow.',
            0.92
        ),
        (
            '3b6f7f2a-3f5f-4e5f-8a6a-0b2c0a1b0006'::uuid,
            'I gave myself permission to rest and let the list wait.',
            0.9
        )
) as seed_chunks(id, chunk_text, chunk_confidence)
join journal_sessions on journal_sessions.id = seed_chunks.id
where not exists (
    select 1 from transcript_chunks
    where transcript_chunks.session_id = seed_chunks.id
      and transcript_chunks.text = seed_chunks.chunk_text
);

insert into daily_summaries (session_id, summary_json)
select id,
    jsonb_build_object(
        'headline', title,
        'bullets', jsonb_build_array(final_text)
    )
from journal_sessions
where user_id = '1d13b3bd-0a67-4004-b0de-035047e82d03'
on conflict (session_id) do nothing;

insert into me_db (user_id, profile_json, state_json, patterns_json, trust_json, updated_at)
values (
    '1d13b3bd-0a67-4004-b0de-035047e82d03',
    '{}'::jsonb,
    '{}'::jsonb,
    '{}'::jsonb,
    '{}'::jsonb,
    now()
)
on conflict (user_id) do nothing;
