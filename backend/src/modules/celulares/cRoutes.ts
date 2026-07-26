export const CELULARES_ROUTES = {
  heartbeat: "/api/celulares/heartbeat",
  list: "/api/celulares",
  cerrarSesion: "/api/celulares/:deviceId/cerrar-sesion",
  iniciarSesion: "/api/celulares/:deviceId/iniciar-sesion",
} as const;
