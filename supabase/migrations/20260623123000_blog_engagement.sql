-- Blog engagement: comments, likes, reviews
-- ---------------------------------------------------------------------------
-- Native engagement features for the Set4u.Biz blog (the WordPress import does
-- NOT carry over WordPress.com likes/comments, so these are first-class here).
--
-- Moderation model:
--   * comments & reviews are submitted by anyone (anon) but land unapproved;
--     only an admin (public.has_role(auth.uid(),'admin')) can approve/edit/delete.
--   * the public can only read APPROVED comments/reviews.
--   * likes are anonymous reactions keyed by a client-generated visitor_id;
--     the public can read counts, add a like, and toggle it off.
-- ---------------------------------------------------------------------------

create table if not exists public.blog_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.blog_posts(id) on delete cascade,
  parent_id uuid references public.blog_comments(id) on delete cascade,
  author_name text not null,
  author_email text,
  content text not null check (length(btrim(content)) > 0),
  approved boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists blog_comments_post_idx on public.blog_comments(post_id, created_at);

create table if not exists public.blog_likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.blog_posts(id) on delete cascade,
  visitor_id text not null,
  created_at timestamptz not null default now(),
  unique (post_id, visitor_id)
);
create index if not exists blog_likes_post_idx on public.blog_likes(post_id);

create table if not exists public.blog_reviews (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.blog_posts(id) on delete cascade,
  author_name text not null,
  rating int not null check (rating between 1 and 5),
  content text,
  approved boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists blog_reviews_post_idx on public.blog_reviews(post_id, created_at);

alter table public.blog_comments enable row level security;
alter table public.blog_likes enable row level security;
alter table public.blog_reviews enable row level security;

-- Comments
drop policy if exists blog_comments_select on public.blog_comments;
create policy blog_comments_select on public.blog_comments for select
  using (approved or public.has_role(auth.uid(), 'admin'));
drop policy if exists blog_comments_insert on public.blog_comments;
create policy blog_comments_insert on public.blog_comments for insert
  with check (approved = false or public.has_role(auth.uid(), 'admin'));
drop policy if exists blog_comments_admin_update on public.blog_comments;
create policy blog_comments_admin_update on public.blog_comments for update
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop policy if exists blog_comments_admin_delete on public.blog_comments;
create policy blog_comments_admin_delete on public.blog_comments for delete
  using (public.has_role(auth.uid(), 'admin'));

-- Reviews
drop policy if exists blog_reviews_select on public.blog_reviews;
create policy blog_reviews_select on public.blog_reviews for select
  using (approved or public.has_role(auth.uid(), 'admin'));
drop policy if exists blog_reviews_insert on public.blog_reviews;
create policy blog_reviews_insert on public.blog_reviews for insert
  with check (approved = false or public.has_role(auth.uid(), 'admin'));
drop policy if exists blog_reviews_admin_update on public.blog_reviews;
create policy blog_reviews_admin_update on public.blog_reviews for update
  using (public.has_role(auth.uid(), 'admin')) with check (public.has_role(auth.uid(), 'admin'));
drop policy if exists blog_reviews_admin_delete on public.blog_reviews;
create policy blog_reviews_admin_delete on public.blog_reviews for delete
  using (public.has_role(auth.uid(), 'admin'));

-- Likes (anonymous)
drop policy if exists blog_likes_select on public.blog_likes;
create policy blog_likes_select on public.blog_likes for select using (true);
drop policy if exists blog_likes_insert on public.blog_likes;
create policy blog_likes_insert on public.blog_likes for insert with check (true);
drop policy if exists blog_likes_delete on public.blog_likes;
create policy blog_likes_delete on public.blog_likes for delete using (true);
