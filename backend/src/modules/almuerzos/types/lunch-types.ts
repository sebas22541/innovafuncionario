export type LunchScanInput = {
  qrValue: string;
};

export type LunchReportQuery = {
  fecha: Date;
  search: string | null;
  status: "ABIERTOS" | "CERRADOS" | null;
  scannerId: number | null;
  officeId: number | null;
};
