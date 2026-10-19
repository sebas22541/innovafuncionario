import { rol_usuario } from "./generated/prisma/enums.ts";

type Role = (typeof rol_usuario)[keyof typeof rol_usuario];

export function normalizeControlPeriod(start: Date, end: Date) {
  return {
    controlInicio: new Date(Math.floor(start.getTime() / 60000) * 60000),
    controlFin: new Date(Math.floor(end.getTime() / 60000) * 60000),
  };
}

export function buildControlRoleAssignment(input: {
  rol: Role;
  controlTemporal: boolean | null;
  controlInicio: Date | null;
  controlFin: Date | null;
}, existing?: {
  rol: Role;
  control_rol_anterior?: Role | null;
}, now = Date.now()) {
  if (input.controlTemporal == null && existing && input.rol === existing.rol) {
    return { rol: existing.rol };
  }
  if (input.rol !== rol_usuario.CONTROL || input.controlTemporal !== true) {
    return { rol: input.rol, control_rol_anterior: null, control_inicio: null, control_fin: null };
  }
  const originalRole = existing?.control_rol_anterior ?? existing?.rol;
  const previousRole = originalRole && originalRole !== rol_usuario.CONTROL
    ? originalRole
    : rol_usuario.OPERADOR;
  if (input.controlFin!.getTime() <= now) {
    return { rol: previousRole, control_rol_anterior: null, control_inicio: null, control_fin: null };
  }
  return {
    rol: input.controlInicio!.getTime() <= now ? rol_usuario.CONTROL : previousRole,
    control_rol_anterior: previousRole,
    control_inicio: input.controlInicio,
    control_fin: input.controlFin,
  };
}
