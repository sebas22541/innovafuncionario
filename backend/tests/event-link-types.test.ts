import assert from "node:assert/strict";
import test from "node:test";
import { USER_LINK_TYPES, eventAllowsUserLinkType, eventLinkTypeRestrictionMessage, readEventLinkTypes } from "../src/event-link-types.ts";

for (const selected of USER_LINK_TYPES) {
  test(`an event restricted to ${selected} rejects all other employee types`, () => {
    const event = { tipos_vinculo: [selected] };
    for (const actual of USER_LINK_TYPES) {
      assert.equal(eventAllowsUserLinkType(event, { tipo_vinculo: actual }), actual === selected);
      assert.equal(eventLinkTypeRestrictionMessage(event, { tipo_vinculo: actual }) === null, actual === selected);
    }
    assert.equal(eventAllowsUserLinkType(event, null), false);
    assert.equal(eventAllowsUserLinkType(event, { tipo_vinculo: "" }), false);
  });
}

test("multiple selected types are allowed without admitting other types", () => {
  const event = { tipos_vinculo: ["ITEM", "CONSULTOR"] };
  assert.equal(eventAllowsUserLinkType(event, { tipo_vinculo: "item" }), true);
  assert.equal(eventAllowsUserLinkType(event, { tipo_vinculo: " CONSULTOR " }), true);
  assert.equal(eventAllowsUserLinkType(event, { tipo_vinculo: "EVENTUAL" }), false);
  assert.equal(eventAllowsUserLinkType(event, { tipo_vinculo: "SERVICIOS" }), false);
});

test("no selection includes every employee type", () => {
  for (const actual of USER_LINK_TYPES) {
    assert.equal(eventAllowsUserLinkType({ tipos_vinculo: [] }, { tipo_vinculo: actual }), true);
    assert.equal(eventLinkTypeRestrictionMessage({}, { tipo_vinculo: actual }), null);
  }
});

test("the persisted selection is normalized without adding other types", () => {
  assert.deepEqual(readEventLinkTypes({ tipos_vinculo: [" item ", "ITEM", "CONSULTOR"] }), ["ITEM", "CONSULTOR"]);
});
