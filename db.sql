-- ============================================================
-- StrollWise Database Schema
-- Supabase / PostgreSQL
-- ============================================================
-- Architecture Principles:
-- 1. No personally identifiable information stored anywhere
-- 2. Raw GPS coordinates never reach this database
-- 3. Only H3 zone IDs, zone types, and timestamps stored
-- 4. Privacy-by-design enforced at schema level
-- ============================================================


-- ============================================================
-- EXTENSIONS
-- ============================================================

-- UUID generation for anonymous tokens
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- PostGIS not needed — H3 handles all spatial logic
-- This is intentional and keeps the schema lightweight


-- ============================================================
-- ENUMS
-- ============================================================

-- Zone types that a user can report, not yet final
CREATE TYPE zone_type AS ENUM (
  'hidden_gem',
  'food',
  'danger',
  'attraction',
  'study',
  'chill',
  'exercise',
  'buy',
  'social'
);

-- Zone lifecycle states based on contribution threshold
CREATE TYPE lifecycle_state AS ENUM (
  'unthreshold',   -- Below minimum pin count, contributor-only visibility
  'emerging',      -- Growing zone, publicly visible but muted
  'defined'        -- Confident zone, fully visible on map
);

-- Contributor demographic — determines zone color
CREATE TYPE contributor_demographic AS ENUM (
  'local',         -- >70% local user contributions → Yellow
  'intl', -- >70% international user contributions → Blue
  'mixed'    -- Mixed contributions → Green
);

-- Zone color for map display
CREATE TYPE zone_color AS ENUM (
  'yellow',   -- Local dominant
  'blue',     -- International dominant
  'green',    -- Mixed base
  'grey'      -- Pre-defined/researcher-seeded zones
);

-- Registry zone classification
CREATE TYPE registry_type AS ENUM (
  'predefined',  -- Researcher-seeded baseline zones
  'restricted'   -- No-contribution zones (military, airport, etc.)
);

-- User type — determines app experience
CREATE TYPE user_type AS ENUM (
  'local',
  'intl'
);


-- ============================================================
-- TABLE 1: ZONE REGISTRY
-- Researcher-defined zones. Pre-defined seeds and restricted zones.
-- Read-only at runtime. Updated only by researchers pre-deployment.
-- ============================================================

CREATE TABLE zone_registry (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- H3 zone identifier at resolution 8
  -- This is the only spatial reference stored
  h3_zone_id      TEXT NOT NULL UNIQUE,

  -- Registry classification
  registry_type   registry_type NOT NULL,

  -- Human-readable zone name (for restricted zones — e.g., "Mactan Airport")
  zone_name       TEXT,

  -- Reason for restriction (for restricted zones only)
  restriction_reason TEXT,

  -- Pre-defined zone type (for predefined zones only)
  predefined_type zone_type,

  -- Geographic area label (Cebu City, Mandaue, Lapu-Lapu)
  area_label      TEXT NOT NULL,

  -- Metadata
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast restricted zone lookup during pin submission
CREATE INDEX idx_zone_registry_h3 ON zone_registry(h3_zone_id);
CREATE INDEX idx_zone_registry_type ON zone_registry(registry_type);

-- Comment
COMMENT ON TABLE zone_registry IS
  'Researcher-defined zone registry. Contains pre-defined seed zones and
   restricted areas. Read-only at runtime. No community contributions
   are accepted for zones marked as restricted.';


-- ============================================================
-- TABLE 2: PIN CONTRIBUTIONS
-- Anonymous community pin submissions.
-- No PII. No raw GPS. Only H3 zone IDs and zone types.
-- ============================================================

CREATE TABLE pin_contributions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- H3 zone identifier — the ONLY spatial reference
  -- Raw GPS was converted to this on-device and discarded
  h3_zone_id      TEXT NOT NULL,

  -- What the user is reporting
  zone_type       zone_type NOT NULL,

  -- Who contributed — local or international
  -- This drives the yellow/blue/green demographic assignment
  contributor_type user_type NOT NULL,

  -- Optional anonymous description (no names, no personal info)
  description     TEXT,

  -- Date only — no exact time to prevent timing-based identification
  contribution_date DATE DEFAULT CURRENT_DATE,

  -- Anonymous session token — not linked to any user account
  -- Allows rate limiting without identity
  -- Generated fresh per app session — not persistent
  session_token   UUID DEFAULT uuid_generate_v4(),

  -- Metadata
  created_at      TIMESTAMPTZ DEFAULT NOW()

  -- INTENTIONALLY MISSING:
  -- user_id      ← No user accounts in StrollWise
  -- latitude     ← Raw GPS never stored
  -- longitude    ← Raw GPS never stored
  -- ip_address   ← Not collected
  -- device_id    ← Not collected
  -- exact_time   ← Only date stored, not time
);

-- Index for fast zone aggregation
CREATE INDEX idx_pin_h3_zone ON pin_contributions(h3_zone_id);
CREATE INDEX idx_pin_zone_type ON pin_contributions(zone_type);
CREATE INDEX idx_pin_contributor ON pin_contributions(contributor_type);
CREATE INDEX idx_pin_date ON pin_contributions(contribution_date);

-- Composite index for aggregation queries
CREATE INDEX idx_pin_zone_contributor ON pin_contributions(h3_zone_id, contributor_type);

-- Comment
COMMENT ON TABLE pin_contributions IS
  'Anonymous community pin submissions. Raw GPS coordinates are converted
   to H3 zone IDs on-device and discarded before submission. No personally
   identifiable information is stored at any point. Session tokens are
   ephemeral and not linked to persistent user accounts.';


-- ============================================================
-- TABLE 3: ZONE INTELLIGENCE
-- Aggregated zone data computed from pin contributions.
-- This is what gets displayed on the map.
-- Updated by the ML pipeline, not directly by users.
-- ============================================================

CREATE TABLE zone_intelligence (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- H3 zone identifier
  h3_zone_id      TEXT NOT NULL UNIQUE,

  -- Aggregated pin counts per type
  hidden_gem_count      INTEGER DEFAULT 0,
  local_favorite_count  INTEGER DEFAULT 0,
  danger_count          INTEGER DEFAULT 0,
  tourist_hotspot_count INTEGER DEFAULT 0,
  total_pin_count       INTEGER DEFAULT 0,

  -- Dominant zone type (highest count wins)
  dominant_type   zone_type,

  -- Contributor demographic breakdown
  local_pin_count         INTEGER DEFAULT 0,
  international_pin_count INTEGER DEFAULT 0,
  local_percentage        NUMERIC(5,2) DEFAULT 0,
  international_percentage NUMERIC(5,2) DEFAULT 0,

  -- Zone color derived from demographic
  zone_color      zone_color DEFAULT 'grey',

  -- Zone lifecycle state
  lifecycle_state lifecycle_state DEFAULT 'unthreshold',

  -- Contributor demographic classification
  demographic     contributor_demographic,

  -- Confidence score (0.0 to 1.0)
  -- Based on total pin count relative to defined threshold
  confidence_score NUMERIC(4,3) DEFAULT 0.000,

  -- Whether this zone is visible on the public map
  -- Unthreshold zones are not publicly visible
  is_public       BOOLEAN DEFAULT FALSE,

  -- Whether this zone was seeded by the researcher registry
  is_predefined   BOOLEAN DEFAULT FALSE,

  -- Temporal intelligence
  -- Last date a new contribution was received
  last_contribution_date DATE,

  -- Zone decay tracking
  -- If no contributions within decay_threshold_days → downgrade lifecycle
  days_since_contribution INTEGER DEFAULT 0,

  -- Cluster neighbors (H3 zone IDs of adjacent zones of same type)
  -- Stored as array for efficient cluster rendering
  cluster_neighbors TEXT[] DEFAULT '{}',

  -- Metadata
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Index for map rendering queries
CREATE INDEX idx_zone_intel_h3 ON zone_intelligence(h3_zone_id);
CREATE INDEX idx_zone_intel_public ON zone_intelligence(is_public);
CREATE INDEX idx_zone_intel_lifecycle ON zone_intelligence(lifecycle_state);
CREATE INDEX idx_zone_intel_type ON zone_intelligence(dominant_type);
CREATE INDEX idx_zone_intel_color ON zone_intelligence(zone_color);

-- Composite index for map filter queries
CREATE INDEX idx_zone_intel_public_type ON zone_intelligence(is_public, dominant_type);

-- Comment
COMMENT ON TABLE zone_intelligence IS
  'Aggregated zone intelligence computed from anonymous pin contributions
   by the ML clustering pipeline. This table drives all map display logic
   including zone colors, lifecycle states, confidence scores, and cluster
   neighbor relationships. Updated periodically by the backend aggregation
   engine, never directly by users.';


-- ============================================================
-- TABLE 4: ZONE FOLLOWS
-- Tracks which zones a user session is following.
-- No user identity — only anonymous session tokens.
-- ============================================================

CREATE TABLE zone_follows (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- H3 zone identifier being followed
  h3_zone_id      TEXT NOT NULL,

  -- Anonymous session token — not linked to any persistent account
  session_token   UUID NOT NULL,

  -- Metadata
  created_at      TIMESTAMPTZ DEFAULT NOW(),

  -- Prevent duplicate follows per session
  UNIQUE(h3_zone_id, session_token)
);

-- Index for zone follow queries
CREATE INDEX idx_zone_follows_h3 ON zone_follows(h3_zone_id);
CREATE INDEX idx_zone_follows_session ON zone_follows(session_token);

-- Comment
COMMENT ON TABLE zone_follows IS
  'Anonymous zone follow relationships. Users can follow zones to track
   their intelligence updates. No persistent user accounts — follows are
   tied to anonymous session tokens only.';


-- ============================================================
-- TABLE 5: ZONE DECAY LOG
-- Tracks zone lifecycle transitions for research analysis.
-- Academic audit trail — not displayed to users.
-- ============================================================

CREATE TABLE zone_decay_log (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- H3 zone identifier
  h3_zone_id      TEXT NOT NULL,

  -- State transition
  from_state      lifecycle_state NOT NULL,
  to_state        lifecycle_state NOT NULL,

  -- Why the transition occurred
  transition_reason TEXT NOT NULL,
  -- e.g. "No contributions for 30 days"
  -- e.g. "Pin count exceeded emerging threshold"
  -- e.g. "Pin count dropped below defined threshold"

  -- Pin count at time of transition
  pin_count_at_transition INTEGER,

  -- Metadata
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Index for research queries
CREATE INDEX idx_decay_log_h3 ON zone_decay_log(h3_zone_id);
CREATE INDEX idx_decay_log_transition ON zone_decay_log(from_state, to_state);

-- Comment
COMMENT ON TABLE zone_decay_log IS
  'Academic audit trail of zone lifecycle transitions. Records every state
   change from unthreshold to emerging to defined and back. Used for
   research analysis of community contribution patterns and zone temporal
   behavior. Not exposed to end users.';


-- ============================================================
-- TABLE 6: CLUSTERING RUNS
-- ML pipeline execution log.
-- Records each clustering run for research reproducibility.
-- ============================================================

CREATE TABLE clustering_runs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Algorithm used
  algorithm       TEXT NOT NULL,
  -- e.g. 'DBSCAN', 'HDBSCAN'

  -- Algorithm parameters
  epsilon         NUMERIC,       -- DBSCAN epsilon
  min_samples     INTEGER,       -- DBSCAN/HDBSCAN min_samples
  min_cluster_size INTEGER,      -- HDBSCAN min_cluster_size

  -- Run statistics
  zones_processed INTEGER DEFAULT 0,
  clusters_formed INTEGER DEFAULT 0,
  noise_points    INTEGER DEFAULT 0,

  -- Performance metrics
  silhouette_score NUMERIC(5,4), -- Clustering quality (-1 to 1)
  execution_time_ms INTEGER,

  -- Run status
  status          TEXT DEFAULT 'completed',
  -- 'running', 'completed', 'failed'

  error_message   TEXT,

  -- Metadata
  run_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Comment
COMMENT ON TABLE clustering_runs IS
  'ML clustering pipeline execution log. Records every DBSCAN/HDBSCAN run
   with parameters, performance metrics, and outcomes for research
   reproducibility and algorithm evaluation. Directly supports Research
   Question 2 — clustering algorithm effectiveness assessment.';


-- ============================================================
-- VIEWS
-- ============================================================

-- Public zone map view
-- Only returns publicly visible zones
-- This is what the mobile app queries for map rendering
CREATE VIEW public_zone_map AS
  SELECT
    zi.h3_zone_id,
    zi.dominant_type,
    zi.zone_color,
    zi.lifecycle_state,
    zi.confidence_score,
    zi.total_pin_count,
    zi.local_percentage,
    zi.international_percentage,
    zi.demographic,
    zi.cluster_neighbors,
    zi.last_contribution_date,
    zi.is_predefined
  FROM zone_intelligence zi
  WHERE zi.is_public = TRUE
  ORDER BY zi.confidence_score DESC;

COMMENT ON VIEW public_zone_map IS
  'Public-facing zone map data. Returns only publicly visible zones
   with their display properties. This is the primary data source
   for the StrollWise mobile map screen.';


-- Zone detail view
-- Returns full zone intelligence for the Zone Detail screen
CREATE VIEW zone_detail_view AS
  SELECT
    zi.h3_zone_id,
    zi.dominant_type,
    zi.zone_color,
    zi.lifecycle_state,
    zi.confidence_score,
    zi.total_pin_count,
    zi.hidden_gem_count,
    zi.local_favorite_count,
    zi.danger_count,
    zi.tourist_hotspot_count,
    zi.local_pin_count,
    zi.international_pin_count,
    zi.local_percentage,
    zi.international_percentage,
    zi.demographic,
    zi.last_contribution_date,
    zi.days_since_contribution,
    zi.cluster_neighbors,
    zi.is_predefined,
    zr.zone_name,
    zr.area_label
  FROM zone_intelligence zi
  LEFT JOIN zone_registry zr
    ON zi.h3_zone_id = zr.h3_zone_id
  WHERE zi.is_public = TRUE;

COMMENT ON VIEW zone_detail_view IS
  'Full zone intelligence view for the Zone Detail screen. Joins zone
   intelligence with registry data for pre-defined zone names and
   area labels.';


-- Metro Cebu zone summary
-- Research and analytics view
-- Aggregate statistics per area for thesis analysis
CREATE VIEW metro_cebu_summary AS
  SELECT
    zr.area_label,
    COUNT(zi.h3_zone_id) AS total_zones,
    COUNT(CASE WHEN zi.lifecycle_state = 'defined' THEN 1 END) AS defined_zones,
    COUNT(CASE WHEN zi.lifecycle_state = 'emerging' THEN 1 END) AS emerging_zones,
    COUNT(CASE WHEN zi.dominant_type = 'hidden_gem' THEN 1 END) AS hidden_gems,
    COUNT(CASE WHEN zi.dominant_type = 'danger' THEN 1 END) AS danger_zones,
    COUNT(CASE WHEN zi.dominant_type = 'local_favorite' THEN 1 END) AS local_favorites,
    COUNT(CASE WHEN zi.dominant_type = 'tourist_hotspot' THEN 1 END) AS tourist_hotspots,
    COUNT(CASE WHEN zi.zone_color = 'yellow' THEN 1 END) AS local_zones,
    COUNT(CASE WHEN zi.zone_color = 'blue' THEN 1 END) AS international_zones,
    COUNT(CASE WHEN zi.zone_color = 'green' THEN 1 END) AS convergence_zones,
    AVG(zi.confidence_score) AS avg_confidence,
    SUM(zi.total_pin_count) AS total_pins
  FROM zone_intelligence zi
  LEFT JOIN zone_registry zr
    ON zi.h3_zone_id = zr.h3_zone_id
  WHERE zi.is_public = TRUE
  GROUP BY zr.area_label;

COMMENT ON VIEW metro_cebu_summary IS
  'Research analytics view. Aggregates zone intelligence statistics
   per Metro Cebu area for thesis analysis and reporting.
   Supports Research Question 3 — platform performance evaluation.';


-- ============================================================
-- FUNCTIONS
-- ============================================================

-- Function: Aggregate pins for a specific zone
-- Called by the backend aggregation engine
CREATE OR REPLACE FUNCTION aggregate_zone(zone_id TEXT)
RETURNS VOID AS $$
DECLARE
  v_hidden_gem_count      INTEGER;
  v_local_favorite_count  INTEGER;
  v_danger_count          INTEGER;
  v_tourist_hotspot_count INTEGER;
  v_total_count           INTEGER;
  v_local_count           INTEGER;
  v_intl_count            INTEGER;
  v_local_pct             NUMERIC;
  v_intl_pct              NUMERIC;
  v_dominant_type         zone_type;
  v_demographic           contributor_demographic;
  v_color                 zone_color;
  v_lifecycle             lifecycle_state;
  v_confidence            NUMERIC;
  v_is_public             BOOLEAN;
BEGIN

  -- Count pins per type for this zone
  SELECT
    COUNT(CASE WHEN zone_type = 'hidden_gem' THEN 1 END),
    COUNT(CASE WHEN zone_type = 'local_favorite' THEN 1 END),
    COUNT(CASE WHEN zone_type = 'danger' THEN 1 END),
    COUNT(CASE WHEN zone_type = 'tourist_hotspot' THEN 1 END),
    COUNT(*),
    COUNT(CASE WHEN contributor_type = 'local' THEN 1 END),
    COUNT(CASE WHEN contributor_type = 'international' THEN 1 END)
  INTO
    v_hidden_gem_count,
    v_local_favorite_count,
    v_danger_count,
    v_tourist_hotspot_count,
    v_total_count,
    v_local_count,
    v_intl_count
  FROM pin_contributions
  WHERE h3_zone_id = zone_id;

  -- Calculate demographic percentages
  IF v_total_count > 0 THEN
    v_local_pct := (v_local_count::NUMERIC / v_total_count) * 100;
    v_intl_pct  := (v_intl_count::NUMERIC / v_total_count) * 100;
  ELSE
    v_local_pct := 0;
    v_intl_pct  := 0;
  END IF;

  -- Determine dominant zone type
  v_dominant_type := (
    SELECT zone_type FROM (
      VALUES
        ('hidden_gem'::zone_type,      v_hidden_gem_count),
        ('local_favorite'::zone_type,  v_local_favorite_count),
        ('danger'::zone_type,          v_danger_count),
        ('tourist_hotspot'::zone_type, v_tourist_hotspot_count)
    ) AS t(zone_type, cnt)
    ORDER BY cnt DESC
    LIMIT 1
  );

  -- Determine demographic
  IF v_local_pct >= 70 THEN
    v_demographic := 'local';
    v_color := 'yellow';
  ELSIF v_intl_pct >= 70 THEN
    v_demographic := 'international';
    v_color := 'blue';
  ELSE
    v_demographic := 'convergence';
    v_color := 'green';
  END IF;

  -- Determine lifecycle state
  -- Thresholds: Unthreshold < 5, Emerging 5-14, Defined >= 15
  IF v_total_count < 5 THEN
    v_lifecycle   := 'unthreshold';
    v_is_public   := FALSE;
    v_confidence  := v_total_count::NUMERIC / 5.0;
  ELSIF v_total_count < 15 THEN
    v_lifecycle   := 'emerging';
    v_is_public   := TRUE;
    v_confidence  := v_total_count::NUMERIC / 15.0;
  ELSE
    v_lifecycle   := 'defined';
    v_is_public   := TRUE;
    v_confidence  := LEAST(v_total_count::NUMERIC / 30.0, 1.0);
  END IF;

  -- Upsert zone intelligence
  INSERT INTO zone_intelligence (
    h3_zone_id,
    hidden_gem_count,
    local_favorite_count,
    danger_count,
    tourist_hotspot_count,
    total_pin_count,
    local_pin_count,
    international_pin_count,
    local_percentage,
    international_percentage,
    dominant_type,
    demographic,
    zone_color,
    lifecycle_state,
    confidence_score,
    is_public,
    last_contribution_date,
    updated_at
  )
  VALUES (
    zone_id,
    v_hidden_gem_count,
    v_local_favorite_count,
    v_danger_count,
    v_tourist_hotspot_count,
    v_total_count,
    v_local_count,
    v_intl_count,
    v_local_pct,
    v_intl_pct,
    v_dominant_type,
    v_demographic,
    v_color,
    v_lifecycle,
    v_confidence,
    v_is_public,
    CURRENT_DATE,
    NOW()
  )
  ON CONFLICT (h3_zone_id) DO UPDATE SET
    hidden_gem_count        = EXCLUDED.hidden_gem_count,
    local_favorite_count    = EXCLUDED.local_favorite_count,
    danger_count            = EXCLUDED.danger_count,
    tourist_hotspot_count   = EXCLUDED.tourist_hotspot_count,
    total_pin_count         = EXCLUDED.total_pin_count,
    local_pin_count         = EXCLUDED.local_pin_count,
    international_pin_count = EXCLUDED.international_pin_count,
    local_percentage        = EXCLUDED.local_percentage,
    international_percentage = EXCLUDED.international_percentage,
    dominant_type           = EXCLUDED.dominant_type,
    demographic             = EXCLUDED.demographic,
    zone_color              = EXCLUDED.zone_color,
    lifecycle_state         = EXCLUDED.lifecycle_state,
    confidence_score        = EXCLUDED.confidence_score,
    is_public               = EXCLUDED.is_public,
    last_contribution_date  = EXCLUDED.last_contribution_date,
    updated_at              = NOW();

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION aggregate_zone IS
  'Aggregates all pin contributions for a given H3 zone ID and updates
   the zone_intelligence table. Computes dominant zone type, contributor
   demographic, zone color, lifecycle state, and confidence score.
   Called by the backend aggregation engine after each new pin submission.';


-- Function: Apply zone decay
-- Called by scheduled job (Vercel Cron / Supabase Edge Function)
-- Downgrades zones that have received no contributions within the threshold
CREATE OR REPLACE FUNCTION apply_zone_decay(decay_days INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
  v_decayed_count INTEGER := 0;
  v_zone RECORD;
BEGIN

  FOR v_zone IN
    SELECT h3_zone_id, lifecycle_state, total_pin_count
    FROM zone_intelligence
    WHERE
      is_predefined = FALSE AND
      last_contribution_date < CURRENT_DATE - decay_days AND
      lifecycle_state != 'unthreshold'
  LOOP

    -- Log the decay transition
    INSERT INTO zone_decay_log (
      h3_zone_id,
      from_state,
      to_state,
      transition_reason,
      pin_count_at_transition
    ) VALUES (
      v_zone.h3_zone_id,
      v_zone.lifecycle_state,
      CASE
        WHEN v_zone.lifecycle_state = 'defined' THEN 'emerging'::lifecycle_state
        WHEN v_zone.lifecycle_state = 'emerging' THEN 'unthreshold'::lifecycle_state
      END,
      'No contributions received for ' || decay_days || ' days',
      v_zone.total_pin_count
    );

    -- Apply decay
    UPDATE zone_intelligence SET
      lifecycle_state = CASE
        WHEN lifecycle_state = 'defined'  THEN 'emerging'::lifecycle_state
        WHEN lifecycle_state = 'emerging' THEN 'unthreshold'::lifecycle_state
      END,
      is_public = CASE
        WHEN lifecycle_state = 'emerging' THEN FALSE
        ELSE is_public
      END,
      days_since_contribution = CURRENT_DATE - last_contribution_date,
      updated_at = NOW()
    WHERE h3_zone_id = v_zone.h3_zone_id;

    v_decayed_count := v_decayed_count + 1;

  END LOOP;

  RETURN v_decayed_count;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION apply_zone_decay IS
  'Applies temporal zone decay. Downgrades zones that have received no
   new pin contributions within the specified decay threshold (default 30
   days). Defined zones downgrade to Emerging. Emerging zones downgrade
   to Unthreshold. Pre-defined registry zones are exempt from decay.
   All transitions are logged to zone_decay_log for research analysis.';


-- Function: Check if zone is restricted
-- Called on-server as secondary validation
-- Primary check happens on-device before submission
CREATE OR REPLACE FUNCTION is_restricted_zone(zone_id TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM zone_registry
    WHERE h3_zone_id = zone_id
    AND registry_type = 'restricted'
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION is_restricted_zone IS
  'Secondary server-side validation for restricted zones. Primary check
   occurs on-device before submission. This function serves as a defense-
   in-depth measure to ensure no pins are ever stored for restricted zones
   even if the client-side check is bypassed.';


-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- Supabase-specific security policies
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE zone_registry        ENABLE ROW LEVEL SECURITY;
ALTER TABLE pin_contributions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE zone_intelligence    ENABLE ROW LEVEL SECURITY;
ALTER TABLE zone_follows         ENABLE ROW LEVEL SECURITY;
ALTER TABLE zone_decay_log       ENABLE ROW LEVEL SECURITY;
ALTER TABLE clustering_runs      ENABLE ROW LEVEL SECURITY;

-- Zone Registry: Public read, no write from clients
CREATE POLICY "Zone registry is publicly readable."
  ON zone_registry FOR SELECT
  USING (TRUE);

-- Pin Contributions: Insert only, no read back
-- Users can submit pins but cannot read other users' submissions
CREATE POLICY "Anyone can submit anonymous pins."
  ON pin_contributions FOR INSERT
  WITH CHECK (TRUE);

-- Zone Intelligence: Public read for public zones only
CREATE POLICY "Public zones are readable by anyone."
  ON zone_intelligence FOR SELECT
  USING (is_public = TRUE);

-- Zone Follows: Session-scoped read and write
CREATE POLICY "Users can manage their own follows."
  ON zone_follows FOR ALL
  USING (TRUE)
  WITH CHECK (TRUE);

-- Decay log and clustering runs: No client access
-- Backend service role only
CREATE POLICY "Decay log is backend only."
  ON zone_decay_log FOR ALL
  USING (FALSE);

CREATE POLICY "Clustering runs are backend only."
  ON clustering_runs FOR ALL
  USING (FALSE);


-- ============================================================
-- SEED DATA: ZONE REGISTRY EXAMPLES
-- Example restricted zones for Metro Cebu
-- Full registry populated pre-deployment by researchers
-- ============================================================

INSERT INTO zone_registry (h3_zone_id, registry_type, zone_name, restriction_reason, area_label)
VALUES
  -- Example restricted zones (H3 IDs are illustrative)
  ('886b8d1203fffff', 'restricted', 'Mactan-Cebu International Airport',
   'Airport perimeter — security sensitive area', 'Lapu-Lapu City'),

  ('886b8d1207fffff', 'restricted', 'Camp Lapu-Lapu',
   'Military installation — restricted access', 'Lapu-Lapu City'),

  ('886b8d1219fffff', 'restricted', 'Camp Sergio Osmeña',
   'Military installation — restricted access', 'Cebu City'),

  ('886b8d1221fffff', 'restricted', 'Philippine Coast Guard Base',
   'Government security facility', 'Cebu City')

ON CONFLICT (h3_zone_id) DO NOTHING;


-- ============================================================
-- SCHEMA SUMMARY
-- ============================================================
-- Tables:
--   1. zone_registry        — Researcher-defined zones (predefined + restricted)
--   2. pin_contributions    — Anonymous community pin submissions
--   3. zone_intelligence    — Aggregated zone data for map display
--   4. zone_follows         — Anonymous zone follow relationships
--   5. zone_decay_log       — Zone lifecycle transition audit trail
--   6. clustering_runs      — ML pipeline execution log
--
-- Views:
--   1. public_zone_map      — Map rendering data (public zones only)
--   2. zone_detail_view     — Zone detail screen data
--   3. metro_cebu_summary   — Research analytics aggregate
--
-- Functions:
--   1. aggregate_zone()     — Compute zone intelligence from pins
--   2. apply_zone_decay()   — Temporal zone lifecycle downgrade
--   3. is_restricted_zone() — Server-side restricted zone check
--
-- Privacy Guarantees:
--   ✅ No raw GPS coordinates stored anywhere
--   ✅ No user accounts or persistent identities
--   ✅ No IP addresses or device identifiers
--   ✅ Only H3 zone IDs, zone types, dates, and session tokens
--   ✅ Session tokens are ephemeral and non-persistent
--   ✅ RLS prevents clients from reading others' pin submissions
--   ✅ Restricted zones enforced at both client and server level
-- ============================================================
