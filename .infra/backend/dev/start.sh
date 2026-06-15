#!/bin/sh
set -eu

migrate_log="$(mktemp)"

if npx prisma migrate deploy > "$migrate_log" 2>&1; then
  cat "$migrate_log"
  rm -f "$migrate_log"
  exec npm run dev
fi

cat "$migrate_log"

if grep -q "P3005" "$migrate_log"; then
  echo "Prisma P3005 detected in dev. Register existing migration history as applied."

  for migration_path in prisma/migrations/*; do
    if [ -d "$migration_path" ]; then
      migration_name="$(basename "$migration_path")"
      npx prisma migrate resolve --applied "$migration_name"
    fi
  done

  npx prisma migrate deploy
  rm -f "$migrate_log"
  exec npm run dev
fi

rm -f "$migrate_log"
exit 1
