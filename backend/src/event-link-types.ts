export const USER_LINK_TYPES = ["ITEM", "EVENTUAL", "CONSULTOR", "SERVICIOS"] as const;
export type UserLinkType = (typeof USER_LINK_TYPES)[number];

export function isUserLinkType(value: string): value is UserLinkType {
  return USER_LINK_TYPES.some((type) => type === value);
}

export function readEventLinkTypes(event: { tipos_vinculo?: unknown }): UserLinkType[] {
  if (!Array.isArray(event.tipos_vinculo)) return [];
  return [...new Set(event.tipos_vinculo
    .map((value: unknown) => typeof value === "string" ? value.trim().toUpperCase() : "")
    .filter(isUserLinkType))];
}

export function eventAllowsUserLinkType(
  event: { tipos_vinculo?: unknown },
  linkedUser?: { tipo_vinculo?: unknown } | null,
) {
  const types = readEventLinkTypes(event);
  if (types.length === 0) return true;
  const value = linkedUser?.tipo_vinculo;
  return typeof value === "string" && types.some((type) => type === value.trim().toUpperCase());
}

export function eventLinkTypeRestrictionMessage(
  event: { tipos_vinculo?: unknown },
  linkedUser?: { tipo_vinculo?: unknown } | null,
) {
  if (eventAllowsUserLinkType(event, linkedUser)) return null;
  return `Este evento solo permite asistencia de: ${readEventLinkTypes(event).join(", ")}. El tipo de funcionario no esta incluido.`;
}
