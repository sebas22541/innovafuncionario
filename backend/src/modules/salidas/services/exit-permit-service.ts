import { estado_salida } from "../../../generated/prisma/enums.ts";

type ExitPermitServiceConfig = {
  buildUserDisplayName: (user: any) => string;
  toDateOnlyText: (date: Date) => string;
};

let exitPermitServiceConfig: ExitPermitServiceConfig | null = null;

export function configureExitPermitService(config: ExitPermitServiceConfig) {
  exitPermitServiceConfig = config;
}

export function serializeExitPermit(salida: any) {
  const config = getExitPermitServiceConfig();
  const salidaRegistrador = salida.registrador_salida ?? null;
  const llegadaRegistrador = salida.registrador_llegada ?? null;

  return {
    id: salida.id,
    usuarioId: salida.usuario_id,
    motivo: salida.motivo,
    estado: salida.estado ?? estado_salida.PENDIENTE,
    lugarDestino: salida.lugar_destino,
    descripcion: salida.descripcion ?? "",
    fechaPermiso: config.toDateOnlyText(salida.fecha_permiso),
    horaInicio: salida.hora_inicio ?? "",
    horaFinal: salida.hora_final ?? "",
    horaLlegada: salida.hora_llegada ?? "",
    salidaEn: salida.salida_en?.toISOString() ?? null,
    llegadaEn: salida.llegada_en?.toISOString() ?? null,
    registradoSalidaPorId: salida.registrado_salida_por_id ?? null,
    registradoSalidaPorNombre:
      salidaRegistrador == null
        ? ""
        : config.buildUserDisplayName(salidaRegistrador),
    registradoLlegadaPorId: salida.registrado_llegada_por_id ?? null,
    registradoLlegadaPorNombre:
      llegadaRegistrador == null
        ? ""
        : config.buildUserDisplayName(llegadaRegistrador),
    solicitanteNombreCompleto: salida.solicitante_nombre_completo,
    solicitanteCi: salida.usuarios?.ci ?? "",
    solicitanteNumeroItem: salida.solicitante_numero_item ?? "",
    solicitanteCargo: salida.solicitante_cargo ?? "",
    solicitanteOficinaId: salida.solicitante_oficina_id ?? null,
    solicitanteOficina: salida.solicitante_oficina ?? "",
    aprobadoPorId: salida.aprobado_por_id ?? null,
    aprobadoPorNombre: salida.aprobado_por_nombre ?? "",
    aprobadoEn: salida.aprobado_en?.toISOString() ?? null,
    createdAt: salida.created_at.toISOString(),
    updatedAt: salida.updated_at.toISOString(),
  };
}

function getExitPermitServiceConfig() {
  if (exitPermitServiceConfig == null) {
    throw new Error("El servicio de salidas no esta configurado.");
  }

  return exitPermitServiceConfig;
}
