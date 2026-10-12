-- My_CRM SQLite schema
-- Location columns live on messages; location_samples is the trail used to fill them.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS contacts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    name            TEXT,
    phone           TEXT,
    imessage_id     TEXT,
    notes           TEXT,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    UNIQUE(phone),
    UNIQUE(imessage_id)
);

CREATE TABLE IF NOT EXISTS location_samples (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    latitude        REAL NOT NULL,
    longitude       REAL NOT NULL,
    accuracy_m      REAL,
    altitude_m      REAL,
    speed_mps       REAL,
    recorded_at     TEXT NOT NULL,
    received_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    source          TEXT NOT NULL DEFAULT 'ios',
    device_id       TEXT
);

CREATE INDEX IF NOT EXISTS idx_location_samples_recorded_at
    ON location_samples(recorded_at);

CREATE TABLE IF NOT EXISTS messages (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    external_id           TEXT UNIQUE,
    contact_id            INTEGER REFERENCES contacts(id) ON DELETE SET NULL,
    direction             TEXT NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    body                  TEXT,
    sent_at               TEXT NOT NULL,
    imported_at           TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    -- Filled by joining nearest location_samples row at/near sent_at
    latitude              REAL,
    longitude             REAL,
    accuracy_m            REAL,
    located_at            TEXT,
    location_sample_id    INTEGER REFERENCES location_samples(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_sent_at ON messages(sent_at);
CREATE INDEX IF NOT EXISTS idx_messages_contact_id ON messages(contact_id);
CREATE INDEX IF NOT EXISTS idx_messages_missing_location
    ON messages(sent_at) WHERE latitude IS NULL;
