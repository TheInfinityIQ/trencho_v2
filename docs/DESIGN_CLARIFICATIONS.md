# Designer clarifications applied to requirements v0.1

These clarify the original package without modifying the supplied reference. They were read from the latest response in the `Game Design Expert` chat after the user directed this chat to that response. No prompts or messages were sent to other chats.

## 1. Message-failure demonstration

Original §48 disabled the edge before the second send. Corrected demonstration sends while a valid communication route exists, disables a required route edge before scheduled delivery, then expects `MESSAGE_FAILED` and no recipient information update. Attempting to send without an enabled route remains a separate immediate `NO_COMMUNICATION_ROUTE` case.

## 2. Reservation fulfilment and actual consumption

Dispatch is a stock-to-cargo transfer. It retires the claim with `RESERVATION_FULFILLED` and reservation state `FULFILLED`, followed by `SHIPMENT_DISPATCHED`; it never increments consumed totals or emits `RESOURCE_CONSUMED`.

Actual stock consumption is a separate validated `ConsumeResource` input. It requires available stock, removes on-hand quantity, increases the consumed ledger and emits `RESOURCE_CONSUMED`. Standalone reservation consumption is also supported and explicitly consumes physical stock; shipment-linked claims cannot be independently retired.

## 3. Mid-edge rerouting and exact fixture behavior

During traversal, a shipment's authoritative location remains its last fully reached location. Blocking preserves partial edge progress. Explicit rerouting computes a replacement path from that location, resets partial progress to zero, and records the abandoned edge/progress in `SHIPMENT_REROUTED`.

The demonstration explicitly reroutes the B shipment through the fixture's alternate logistics path; it does not rely on automatic resumption when an edge is re-enabled.
