export type JsonRecord = Record<string, unknown>;

export type CreateSwornDeclarationInput = {
  gestion: number;
  payload: JsonRecord;
};

export type ReviewSwornDeclarationInput = {
  estado: "APROBADO" | "RECHAZADO";
  observacion: string | null;
};
