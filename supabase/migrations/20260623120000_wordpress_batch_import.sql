-- WordPress → Set4u.Biz batched blog import
-- ---------------------------------------------------------------------------
-- Problem: importing the whole WordPress archive (241 published posts from
-- grekai.wpcomstaging.com) in a single edge-function call overloaded / timed
-- out, so only ~50 posts ever landed in `blog_posts`.
--
-- Fix: pull the posts server-side, INSIDE Postgres, one small page at a time
-- using the `http` extension against the WordPress REST API. Each call handles
-- a bounded batch (default 20 posts) so nothing times out, and the upsert is
-- idempotent (ON CONFLICT (slug) DO NOTHING) so it is safe to re-run and to
-- resume. Post bodies are stored as raw WordPress HTML — exactly the shape the
-- front-end already renders via <BlogMarkdown> (react-markdown + rehype-raw).
--
-- Usage (run as many times as you like — already-imported slugs are skipped):
--   select * from public.import_wp_page(1, 20);            -- one page
--   select p, (public.import_wp_page(p, 20)).*             -- a range
--     from generate_series(1, 13) p order by p;
-- ---------------------------------------------------------------------------

create extension if not exists http with schema extensions;

-- Decode the handful of HTML entities WordPress emits in plain-text fields
-- (title / excerpt are rendered as React text nodes, so they must be decoded;
-- the HTML body keeps its entities because the browser decodes them).
create or replace function public.decode_wp_entities(t text)
returns text language sql immutable as $fn$
  select case when t is null then null else
    regexp_replace(
    replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
      t,
      '&#8211;','–'),'&ndash;','–'),'&#8212;','—'),'&mdash;','—'),'&#8217;','’'),'&rsquo;','’'),'&#8216;','‘'),'&lsquo;','‘'),
      '&#8220;','“'),'&ldquo;','“'),'&#8221;','”'),'&rdquo;','”'),'&#8230;','…'),'&hellip;','…'),
      '&#038;','&'),'&amp;','&'),'&#39;','’'),'&quot;','"'),'&gt;','>'),'&lt;','<'),'&#160;',' '),'&nbsp;',' ')
    , '\s+$', '')
  end
$fn$;

-- Import one page of published WordPress posts. Returns (seen, inserted).
create or replace function public.import_wp_page(p_page int, p_per int default 20)
returns table(seen int, inserted int) language plpgsql as $fn$
declare
  resp text;
  arr jsonb;
  rec jsonb;
  ins int := 0;
  cnt int := 0;
  v_excerpt text;
begin
  select content into resp from extensions.http_get(
    'https://grekai.wpcomstaging.com/wp-json/wp/v2/posts?status=publish&orderby=date&order=desc'
    || '&per_page=' || p_per || '&page=' || p_page
    || '&_fields=id,slug,date,link,title,excerpt,content,jetpack_featured_media_url'
  );
  if resp is null or left(btrim(resp), 1) <> '[' then
    raise exception 'WP fetch failed for page %: %', p_page, left(coalesce(resp, '<null>'), 200);
  end if;
  arr := resp::jsonb;
  for rec in select * from jsonb_array_elements(arr) loop
    cnt := cnt + 1;
    v_excerpt := btrim(regexp_replace(public.decode_wp_entities(rec->'excerpt'->>'rendered'), '<[^>]+>', '', 'g'));
    v_excerpt := btrim(regexp_replace(v_excerpt, '\s*(\[…\]|…)\s*$', ''));
    insert into public.blog_posts(
      title, slug, excerpt, content, cover_image_url,
      published, published_at, sources, external_source_url
    )
    values(
      public.decode_wp_entities(rec->'title'->>'rendered'),
      rec->>'slug',
      nullif(v_excerpt, ''),
      rec->'content'->>'rendered',
      nullif(rec->>'jetpack_featured_media_url', ''),
      true,
      (rec->>'date')::timestamptz,
      array['wordpress'],
      rec->>'link'
    )
    on conflict (slug) do nothing;
    if found then ins := ins + 1; end if;
  end loop;
  return query select cnt, ins;
end $fn$;
