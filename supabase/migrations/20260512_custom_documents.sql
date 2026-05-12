-- 2026-05-12 — Vlastní dokumenty vytvořené ve Velíně (mimo 5 pevných smluvních typů
-- v `document_templates`). Buď formátovaný HTML text (bez proměnných), nebo nahrané PDF.
-- Web (motogo-web-php) je vypisuje na /jak-pujcit/dokumenty vedle pevně zadaných karet
-- a /dokumenty/<slug> je vyrenderuje (HTML) nebo přesměruje na PDF (kind='pdf').
-- PDF soubory: bucket `media` (veřejný), v `pdf_path` je rovnou veřejná URL.

create table if not exists public.custom_documents (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  slug         text not null unique,
  description  text,
  kind         text not null default 'html' check (kind in ('html', 'pdf')),
  content_html text,
  pdf_path     text,
  show_on_web  boolean not null default true,
  sort_order   integer not null default 100,
  active       boolean not null default true,
  version      integer not null default 1,
  updated_by   uuid references public.admin_users(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists custom_documents_web_idx
  on public.custom_documents (active, show_on_web, sort_order);

-- updated_at touch
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists trg_custom_documents_updated_at on public.custom_documents;
create trigger trg_custom_documents_updated_at
  before update on public.custom_documents
  for each row execute function public.set_updated_at();

alter table public.custom_documents enable row level security;

-- admin: plný přístup
drop policy if exists custom_documents_admin on public.custom_documents;
create policy custom_documents_admin on public.custom_documents
  for all using (public.is_admin()) with check (public.is_admin());

-- web (anon/authenticated): jen aktivní + povolené k zobrazení na webu
drop policy if exists custom_documents_public_read on public.custom_documents;
create policy custom_documents_public_read on public.custom_documents
  for select using (active = true and show_on_web = true);

notify pgrst, 'reload schema';
