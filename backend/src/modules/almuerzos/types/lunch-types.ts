export type LunchScanInput = {
  qrValue: string;
  latitud: number | null;
  longitud: number | null;
  accuracy: number | null;
};

export type LunchReportQuery = {
  fechaDesde: Date;
  fechaHasta: Date;
  search: string | null;
  status: "ABIERTOS" | "CERRADOS" | null;
  scannerId: number | null;
  userId: number | null;
  officeId: number | null;
  placeId: number | null;
  jobTitle: string | null;
  linkType: "ITEM" | "EVENTUAL" | "CONSULTOR" | "SERVICIOS" | null;
};
