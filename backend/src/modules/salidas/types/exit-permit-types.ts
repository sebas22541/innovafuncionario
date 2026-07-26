import type {
  estado_salida,
  motivo_salida,
} from "../../../generated/prisma/enums.ts";

export type CreateExitPermitInput = {
  motivo: (typeof motivo_salida)[keyof typeof motivo_salida];
  lugarDestino: string;
  descripcion: string | null;
  fechaPermiso: Date;
};

export type UpdateExitPermitStatusInput = {
  estado: typeof estado_salida.APROBADO | typeof estado_salida.RECHAZADO;
};

export type UpdateExitPermitArrivalInput = {
  horaLlegada: string;
};
