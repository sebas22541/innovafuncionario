type Scan = {
  id: number;
  registradoEn: string;
  registradoPorEmail?: string | null;
  registradoPorNombre?: string | null;
};

export function scannerDisplayName(user: {
  nombres?: string | null;
  nombre_completo?: string | null;
  primer_apellido?: string | null;
}): string {
  const firstName = (user.nombres?.trim() || user.nombre_completo?.trim() || "")
    .split(/\s+/)[0];
  return [firstName, user.primer_apellido?.trim()].filter(Boolean).join(" ");
}

// Call with scans from one event only. Original authorship remains unchanged.
export function previousScannerReferences(scans: Scan[]): Map<number, string> {
  const dayFormat = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/La_Paz", year: "numeric", month: "2-digit", day: "2-digit",
  });
  const sorted = [...new Map(scans.map(scan => [scan.id, scan])).values()]
    .filter(scan => Number.isFinite(Date.parse(scan.registradoEn)))
    .sort((a, b) => Date.parse(a.registradoEn) - Date.parse(b.registradoEn) || a.id - b.id);
  const previous = new Map<string, string>();
  const result = new Map<number, string>();
  for (let start = 0; start < sorted.length;) {
    let end = start + 1;
    const timestamp = Date.parse(sorted[start].registradoEn);
    while (end < sorted.length && Date.parse(sorted[end].registradoEn) === timestamp) end++;
    const day = dayFormat.format(new Date(timestamp));
    // Equal timestamps do not establish which scan happened first.
    for (const scan of sorted.slice(start, end)) {
      if (scan.registradoPorEmail?.trim().toLowerCase() === "admin@admin.com") {
        const name = previous.get(day);
        if (name) result.set(scan.id, name);
      }
    }
    for (const scan of sorted.slice(start, end)) {
      const email = scan.registradoPorEmail?.trim().toLowerCase();
      const name = scan.registradoPorNombre?.trim();
      if (email && email !== "admin@admin.com" && name) previous.set(day, name);
    }
    start = end;
  }
  return result;
}
