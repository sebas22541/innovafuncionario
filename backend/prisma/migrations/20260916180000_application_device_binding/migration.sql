CREATE TABLE IF NOT EXISTS aplicacion_dispositivos (
  usuario_id INTEGER PRIMARY KEY REFERENCES usuarios(id) ON DELETE CASCADE,
  device_id VARCHAR(120) UNIQUE,
  secret_hash VARCHAR(64),
  plataforma VARCHAR(20),
  vinculado_en TIMESTAMPTZ,
  cambio_hash VARCHAR(64),
  cambio_expira TIMESTAMPTZ,
  biometric_hash VARCHAR(64),
  biometric_password_hash VARCHAR(64),
  biometric_expira TIMESTAMPTZ,
  CHECK ((device_id IS NULL) = (secret_hash IS NULL))
);
CREATE TABLE IF NOT EXISTS aplicacion_cambios (
  id BIGSERIAL PRIMARY KEY,
  usuario_id INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  administrador_id INTEGER REFERENCES usuarios(id) ON DELETE SET NULL,
  dispositivo_anterior VARCHAR(120),
  motivo TEXT NOT NULL,
  creado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
