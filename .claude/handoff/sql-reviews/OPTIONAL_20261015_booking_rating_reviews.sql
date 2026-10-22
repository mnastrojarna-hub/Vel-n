-- SUPERSEDED 2026-10-15 → 20261015_velin_rating_handled.sql (stejná tabulka + rated_at_seen, který Velín potřebuje). NEAPLIKOVAT tento soubor.
-- =====================================================================
-- OPTIONAL DRAFT (NOT REQUIRED for the feature, NOT approved by owner)
-- Hodnocení jízd — interní stav „vyřízeno“ ve Velíně bez kontaktu zákazníka.
--
-- The recommended architecture needs NO schema change: rating stays in
-- bookings.rating/rated_at and the private text goes into the customer's own
-- chat thread (message_threads/messages). „Vyřízeno“ is derived there
-- (admin reply in the feedback thread or thread status resolved/closed).
--
-- Only if the owner wants an explicit „Označit jako vyřízené“ for a low
-- rating WITHOUT writing to the customer, this adds an admin-only table.
-- Nothing is visible to customers or anon. Idempotent, one transaction.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.booking_rating_reviews (
  booking_id  uuid PRIMARY KEY REFERENCES public.bookings(id) ON DELETE CASCADE,
  handled_at  timestamptz NOT NULL DEFAULT now(),
  handled_by  uuid DEFAULT auth.uid() REFERENCES public.admin_users(id) ON DELETE SET NULL,
  note        text CHECK (note IS NULL OR char_length(note) <= 2000)
);

COMMENT ON TABLE public.booking_rating_reviews IS
  'Velín → Zprávy → Hodnocení: interní „vyřízeno“ u hodnocení jízdy (bookings.rating). Jen admin.';

ALTER TABLE public.booking_rating_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS booking_rating_reviews_admin_all ON public.booking_rating_reviews;
CREATE POLICY booking_rating_reviews_admin_all ON public.booking_rating_reviews
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

REVOKE ALL ON public.booking_rating_reviews FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.booking_rating_reviews TO authenticated;

-- Realtime (Velín badge / tab refresh), guarded like other migrations
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'booking_rating_reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.booking_rating_reviews;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'booking_rating_reviews realtime: %', SQLERRM;
END $$;
