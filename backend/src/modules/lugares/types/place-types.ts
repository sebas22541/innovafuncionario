export type PlaceInput = {
  nombre: string;
  oficinaId: number | null;
  oficinaIds: number[];
  usuarioIdsExcluidos: number[];
  pisos: PlaceFloorInput[];
  latitud: number;
  longitud: number;
  radioMetros: number;
  activo: boolean;
};

export type PlaceFloorInput = {
  id: number | null;
  nombre: string;
};
