-- =========================================================
-- CineStream / MLWBD Supabase PostgreSQL Database Schema
-- Includes Role-Based Access Control (RBAC) & RLS Policies
-- =========================================================

-- 1. Create Profiles Table (Linked to Supabase Auth)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  name TEXT,
  role TEXT DEFAULT 'user' CHECK (role IN ('user', 'admin')),
  avatar TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS on profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public profiles are viewable by everyone."
  ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Users can update own profile."
  ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Trigger for automatic profile creation when user signs up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name, role, avatar)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    COALESCE(new.raw_user_meta_data->>'role', 'user'),
    COALESCE(new.raw_user_meta_data->>'avatar_url', '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. Create Categories Table
CREATE TABLE IF NOT EXISTS public.categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  slug TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS on categories
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read-access on categories"
  ON public.categories FOR SELECT USING (true);

CREATE POLICY "Allow admin all on categories"
  ON public.categories FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- 3. Create Movies Table
CREATE TABLE IF NOT EXISTS public.movies (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tmdb_id INTEGER UNIQUE NOT NULL,
  title TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  overview TEXT,
  poster_path TEXT,
  backdrop_path TEXT,
  release_date TEXT,
  rating NUMERIC(3, 1) DEFAULT 7.0,
  vote_count INTEGER DEFAULT 0,
  genres TEXT[] DEFAULT '{}',
  language TEXT DEFAULT 'EN',
  quality_tag TEXT DEFAULT '1080p Web-DL',
  content_type TEXT DEFAULT 'movie' CHECK (content_type IN ('movie', 'series')),
  duration TEXT,
  trailer_key TEXT,
  is_featured BOOLEAN DEFAULT false,
  is_published BOOLEAN DEFAULT true,
  views INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS on movies
ALTER TABLE public.movies ENABLE ROW LEVEL SECURITY;

-- Public can only read published movies
CREATE POLICY "Allow public read-access on published movies"
  ON public.movies FOR SELECT
  USING (
    is_published = true OR EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- Only admins can insert, update, or delete movies
CREATE POLICY "Allow admin all operations on movies"
  ON public.movies FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- 4. Create Media Links Table (Streaming & Download Mirrors)
CREATE TABLE IF NOT EXISTS public.media_links (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  movie_id UUID REFERENCES public.movies(id) ON DELETE CASCADE NOT NULL,
  server_name TEXT NOT NULL,
  link_type TEXT NOT NULL CHECK (link_type IN ('stream', 'download')),
  quality TEXT NOT NULL CHECK (quality IN ('480p', '720p', '1080p', '4K HDR', 'Direct HD')),
  file_size TEXT,
  url TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS on media_links
ALTER TABLE public.media_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read-access on media_links"
  ON public.media_links FOR SELECT USING (true);

CREATE POLICY "Allow admin all operations on media_links"
  ON public.media_links FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_movies_slug ON public.movies(slug);
CREATE INDEX IF NOT EXISTS idx_movies_tmdb_id ON public.movies(tmdb_id);
CREATE INDEX IF NOT EXISTS idx_movies_content_type ON public.movies(content_type);
CREATE INDEX IF NOT EXISTS idx_movies_is_featured ON public.movies(is_featured);
CREATE INDEX IF NOT EXISTS idx_movies_is_published ON public.movies(is_published);
CREATE INDEX IF NOT EXISTS idx_media_links_movie_id ON public.media_links(movie_id);
CREATE INDEX IF NOT EXISTS idx_categories_slug ON public.categories(slug);

