type ReportServiceConfig = {
  resolveLinkedOfficeName: (user: any) => string | null;
  resolveLinkedOfficeId: (user: any) => number | null;
  resolveLinkedOfficeCode: (user: any) => string | null;
  serializeAttendanceControlRecord: (record: any) => any;
  buildSerializedControlSummary: (controls: any[]) => any;
  buildResolvedPersonDisplayName: (person: any) => string;
  serializeLocalEventDate: (date: Date) => string;
  buildUserDisplayName: (user: any) => string;
  resolveEffectiveJobTitleName: (user: any) => string | null;
  buildUserQrCode: (user: any) => string;
};

let reportServiceConfig: ReportServiceConfig | null = null;

export function configureReportService(config: ReportServiceConfig) {
  reportServiceConfig = config;
}

export function serializeAttendanceReportRecord(attendance: any, person: any) {
  const config = getConfig();
  const linkedUser = person.usuario ?? null;
  const officeName = config.resolveLinkedOfficeName(linkedUser);
  const serializedControls = (attendance.asistencia_controles ?? []).map(
    config.serializeAttendanceControlRecord,
  );
  const controlSummary =
    config.buildSerializedControlSummary(serializedControls);
  const resolvedState =
    serializedControls.length > 0 ? controlSummary.state : attendance.estado;

  return {
    id: attendance.id,
    personaId: person.id,
    ci: linkedUser?.ci ?? person.ci,
    nombreCompleto: config.buildResolvedPersonDisplayName(person),
    oficina: officeName,
    oficinaId: config.resolveLinkedOfficeId(linkedUser),
    oficinaCodigo: config.resolveLinkedOfficeCode(linkedUser),
    estado: resolvedState,
    observacion: attendance.observacion,
    eventoId: attendance.eventos.id,
    eventoNombre: attendance.eventos.nombre,
    eventoFecha: config.serializeLocalEventDate(
      attendance.eventos.fecha_evento,
    ),
    eventoDireccion:
      attendance.eventos.direccion ?? attendance.eventos.descripcion,
    registradoEn: attendance.registrado_en.toISOString(),
    controles: controlSummary.controls,
    controlesRegistrados: controlSummary.registeredCount,
    controlesAsistidos: controlSummary.attendedCount,
    controlesObservados: controlSummary.observedCount,
    controlesRetrasados: controlSummary.lateCount,
  };
}

export function serializeReportPerson(source: {
  user: any | null;
  person: any | null;
}) {
  const config = getConfig();
  const linkedUser = source.user ?? source.person?.usuario ?? null;
  const linkedPerson = source.person ?? linkedUser?.persona ?? null;
  const officeName = config.resolveLinkedOfficeName(linkedUser);

  return {
    id: linkedUser?.id ?? linkedPerson?.id ?? 0,
    personaId: linkedPerson?.id ?? null,
    usuarioId: linkedUser?.id ?? null,
    ci: linkedUser?.ci ?? linkedPerson?.ci ?? "",
    nombreCompleto: linkedUser
      ? config.buildUserDisplayName(linkedUser)
      : (linkedPerson?.nombre_completo ?? ""),
    oficina: officeName,
    oficinaId: config.resolveLinkedOfficeId(linkedUser),
    oficinaCodigo: config.resolveLinkedOfficeCode(linkedUser),
    unidad: officeName,
    cargo: config.resolveEffectiveJobTitleName(linkedUser),
    tipoVinculo: linkedUser?.tipo_vinculo ?? null,
    numeroItem: linkedUser?.numero_item ?? null,
    email: linkedUser?.email ?? null,
    activo: linkedUser?.activo ?? linkedPerson?.activo ?? true,
    fotoUrl: linkedUser?.foto_url ?? null,
    codigoQr:
      linkedPerson?.codigo_qr ??
      (linkedUser ? config.buildUserQrCode(linkedUser) : null),
  };
}

function getConfig() {
  if (reportServiceConfig == null) {
    throw new Error("El servicio de reportes no esta configurado.");
  }

  return reportServiceConfig;
}
