# WordPress → Set4u.Biz blog import

The Set4u.Biz blog (`blog_posts` table in the Lovable/Supabase project
`ioqmiwgvotdqqiqgnhdu`) is seeded from the legacy WordPress archive at
**grekai.wpcomstaging.com** ("Set4u.Biz – Tips and Tricks", 241 published posts).

## Why this exists

The original importer tried to pull the whole archive in one edge-function
invocation. With 241 posts that call overloaded / timed out, so only ~50 posts
ever made it into `blog_posts`. The site looked half-empty.

## The mechanism

Instead of a big one-shot job, the import runs **server-side inside Postgres**
in bounded batches, using the `http` extension to call the WordPress REST API
directly (`/wp-json/wp/v2/posts`). See
`supabase/migrations/20260623120000_wordpress_batch_import.sql`.

- `import_wp_page(page, per_page)` fetches one page and upserts it.
- Idempotent: `ON CONFLICT (slug) DO NOTHING`, so re-running is safe and the
  job is resumable if interrupted.
- Bodies are stored as raw WordPress HTML — the front-end already renders that
  through `<BlogMarkdown>` (react-markdown + `rehype-raw` + sanitize).
- `published_at`, `cover_image_url` (`jetpack_featured_media_url`),
  `external_source_url` (original permalink) and a cleaned plain-text `excerpt`
  are all carried over. `sources` is set to `{wordpress}`.

## Run / re-run the full import

```sql
-- 241 posts at per_page=20 = 13 pages; skips anything already imported.
select p as page, (public.import_wp_page(p, 20)).*
from generate_series(1, 13) p
order by p;
```

To pick up new posts published on WordPress later, just run it again — only
new slugs are inserted.

## Result of the initial run (2026-06-23)

- 241 / 241 published WordPress posts imported (191 new + 50 pre-existing).
- All published, HTML entities in titles/excerpts decoded, 0 empty bodies.
- Live immediately — the site reads `blog_posts` from Supabase client-side, so
  no redeploy was required.

## Not carried over

WordPress.com reactions ("likes") and comments are **not** part of this import.
Reviews / likes / comments are a separate feature being built natively on
Set4u.Biz (their own tables + UI), tracked outside this script.
