export type EventJobTitleCandidate = {
  code: string | null;
  name: string | null;
};

// Names are normalized by the caller. A shared word or leadership category
// does not make different jobs eligible for the same event.
export function matchesCargoSelection(
  userJobTitles: EventJobTitleCandidate[],
  allowedCargoCodigos: Set<string>,
  allowedCargoNames: Set<string>,
) {
  return userJobTitles.some((jobTitle) =>
    (jobTitle.code != null && allowedCargoCodigos.has(jobTitle.code)) ||
    (jobTitle.name != null && allowedCargoNames.has(jobTitle.name)),
  );
}
