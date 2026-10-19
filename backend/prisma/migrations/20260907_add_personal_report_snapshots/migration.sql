CREATE TABLE IF NOT EXISTS "personal_report_snapshots" (
  "report_date" DATE NOT NULL,
  "usuario_id" INTEGER NOT NULL,
  "usuario_snapshot" JSONB NOT NULL,
  "created_by_id" INTEGER,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "personal_report_snapshots_pkey" PRIMARY KEY ("report_date", "usuario_id")
);

CREATE INDEX IF NOT EXISTS "idx_personal_report_snapshots_report_date"
  ON "personal_report_snapshots" ("report_date");
