# Federation demo — design

**Status:** approved in conversation on 2026-09-15; awaiting written review.
**Scope:** one implementation plan. Stretch goals are ordered and separable.

## Purpose

A 4–8 hour hands-on introduction to GraphQL Federation, Hive, and Spring for
GraphQL in Kotlin, for a backend engineer joining a team of frontend engineers
whose company is replacing a BFF layer with a federated graph.

The output is three things, in priority order:

1. **Fluency** writing a subgraph — entities, `@key`, reference resolvers —
   with your own hands.
2. **A demo** for the FE team: one federated query, spanning two services,
   replacing what a BFF call used to assemble. Every line of it defensible.
3. **The concept of composition**, seen once locally: two schemas become one
   supergraph, and the tooling rejects what does not compose.

Success is being able to explain every line of the demo to a colleague, not the
demo existing.

## Constraints

- **Hand-written Kotlin.** Schemas and resolvers are typed by the learner.
  Agents do the plumbing — build config, gateway, fixtures, test scaffolding,
  documentation drafts. This is the split that worked in `kotlin-ramp-up`.
- **4–8 hours of the learner's time.** Agent time is not counted.
- **Local only.** Three processes and one container. Nothing deploys.
- **Fresh repo.** No code carried over from `kotlin-ramp-up`. The one thing
  reused is the seeded Contentful *data* — as in-memory fixtures, not via its
  API — because that content model was hand-built and its IDs give the demo a
  real domain.

## Decisions already made, with reasons

### Library: Spring for GraphQL

Versions verified against Maven Central on 2026-09-15.

| | Spring for GraphQL | DGS (Netflix) | graphql-kotlin (Expedia) |
|:--|:--|:--|:--|
| On Spring Boot 4 | 2.0.5, managed by the Boot BOM | 12.0.1 | 10.2.2 stable; 11 is alpha |
| Federation | built in (`FederationSchemaFactory`, `@EntityMapping`) | built in | built in |
| Schema style | schema-first (you write SDL) | schema-first | code-first (SDL generated) |
| Web stack | Spring MVC | Spring MVC | WebFlux only |

Chosen because:

- **Schema-first fits the role.** The SDL file is the contract FE engineers
  read and query against. Authoring it directly keeps the artifact they care
  about in your hands.
- **It transfers whichever way the company's stack resolves.** DGS 12 is built
  *on* Spring for GraphQL, so learning the substrate covers both. Only
  graphql-kotlin is a separate ecosystem, and federation concepts carry over
  regardless.
- **No second programming model.** graphql-kotlin is WebFlux-only; this stays
  on the servlet stack already in use.

**Version pin that matters:** `federation-graphql-java-support` must be
**6.2.1**, not 7.0.0. The 7.0 line targets graphql-java 26; Spring Boot 4.1.1
ships graphql-java 25.

The company's actual stack is unknown at time of writing ("D, weakly B" — no
information, weak suspicion a specific JVM library is in use). Questions to ask
colleagues are recorded in the conversation; if the answer is graphql-kotlin,
syntax will not transfer but concepts will, and a two-subgraph demo is cheap to
re-express.

### Repo: fresh, not `kotlin-ramp-up`

Recreating the Spring Boot skeleton is agent work and cheap. The real costs of
building on the existing repo were: coupling the demo to an evaluator with no
tests and open design decisions; scope gravity toward the sealed AST and `Money`
type, which a federation demo does not need; and a muddled narrative across two
unrelated plans.

### Scope: A, then C, then B

- **A — the federation loop** (core, ~4h): two subgraphs, local composition,
  one federated query. Complete on its own.
- **C — Hive registry** (stretch, +2h): publish, see composition succeed in the
  registry, break a schema, watch the check fail. Teaches the pipeline that
  protects the person on call.
- **B — live Contentful** (stretch, +2h): catalog reads the seeded space over
  HTTP. Realistic, but teaches nothing about federation.

C before B because C teaches something new about federation and B does not.

### Cut, deliberately

- Deploying to the existing `t4g.small`. Local compose demonstrates everything.
- A third subgraph. Two is the minimum that *is* federation.
- Retries, circuit breakers, custom error types, header-based context
  propagation. All real; all week-three.

---

## 1. Repo shape and how the pieces connect

```
graphql-federation-ramp-up/
├── settings.gradle.kts             # includes :catalog, :personalization
├── build.gradle.kts                # shared: Kotlin, Spring Boot BOM, ktlint, detekt, Kover
├── gradle/libs.versions.toml       # spring-graphql via BOM; federation-jvm pinned 6.2.1
├── catalog/                        # Spring Boot, port 8081
│   └── src/main/resources/graphql/catalog.graphqls
├── personalization/                # Spring Boot, port 8082
│   └── src/main/resources/graphql/personalization.graphqls
├── gateway/
│   ├── docker-compose.yml          # Hive Gateway on port 4000
│   └── supergraph.graphql          # composed from the two subgraphs — generated, not hand-written
├── dev.sh                          # start subgraphs → compose → start gateway
├── smoke.sh                        # the federated query, asserted
└── docs/
```

One Gradle build, two Spring Boot applications as modules, and a `gateway/`
directory that is not Kotlin. One repo rather than two because it keeps the
demo self-contained; a real shop would have them separate.

**Request flow.** A query reaches the gateway on 4000. The gateway holds the
composed supergraph, so it knows `Product.name` lives in catalog and
`Product.cta` in personalization. It queries catalog for products, then calls
personalization's `_entities` with the product keys, and stitches the result.
Neither subgraph knows the other exists.

**Building the supergraph.** Each subgraph exposes its federated SDL at
`_service { sdl }` — Spring for GraphQL adds that once `FederationSchemaFactory`
is wired. The Hive CLI's `hive dev` composes from the two subgraph URLs into
`supergraph.graphql` with no registry involved; the gateway loads that file.
`dev.sh` does all three steps.

**Verify first:** `hive dev` is the hinge of the local loop and the one step
here I have not personally run against this exact stack. It is the first thing
the implementation plan should confirm. Fallback if it misbehaves: compose with
Apollo's `rover supergraph compose` instead, which changes nothing else.

## 2. The two schemas

The learner writes both files. This section is the design — ownership and the
federation-specific parts — not the finished SDL.

### Catalog owns `Product`

```graphql
extend schema @link(url: "https://specs.apollo.dev/federation/v2.3", import: ["@key"])

type Query {
  products: [Product!]!
  product(id: ID!): Product
}

type Product @key(fields: "id") {
  id: ID!            # the SKU — product identity in the seed is the SKU, not Contentful's opaque id
  name: String!
  priceMinor: Int!
  currency: Currency!
  category: Category!
  tags: [String!]!
}
```

`@key(fields: "id")` makes `Product` an **entity**: something another subgraph
may extend.

### Personalization extends it

```graphql
extend schema @link(url: "https://specs.apollo.dev/federation/v2.3", import: ["@key"])

type Query {
  segments: [Segment!]!    # lets the FE discover valid values; also keeps the schema valid
}

type Product @key(fields: "id") {
  id: ID!
  cta(segment: Segment!): CallToAction
}

enum Segment { VIP NEWSLETTER FIRST_TIME_BUYER }

type CallToAction {
  ctaId: String!
  variantKey: String!
  headline: String!
}
```

Personalization declares `Product` with the same key and adds one field. It
never sees `name` or `price`. Two services contribute fields to one type;
neither owns the other.

### Three decisions

- **Segment as a field argument** — `cta(segment: VIP)`. Simple for the demo.
  In production it arrives as a header the gateway forwards; that is a footnote
  in the explainer, and it is also what would make `@BatchMapping` on `cta`
  clean (see §3).
- **`Segment` is an enum.** Two lines; gives the FE team autocomplete and
  validation in every query. If the company's segments turn out to be dynamic
  content, a string is the honest choice instead.
- **`headline` lives on `CallToAction`.** Personalization resolves the actual
  copy, not just a key, because that is what the FE renders. In-memory for the
  core loop; it is exactly where stretch goal B plugs in.

## 3. Data flow: one query, two services

The FE-shaped query, sent to the gateway:

```graphql
query CatalogForShopper($segment: Segment!) {
  products {
    id
    name
    priceMinor
    cta(segment: $segment) { variantKey headline }
  }
}
```

The gateway makes **two** calls, not twelve:

1. To catalog: `{ products { id name priceMinor } }`
2. To personalization, one call carrying all twelve keys:
   ```graphql
   { _entities(representations: [{ __typename: "Product", id: "CAT-TREE-DLX" }, ...]) {
       ... on Product { cta(segment: VIP) { variantKey headline } }
   } }
   ```

Then it merges by `id`. `_entities` is the mechanism everything rests on: the
gateway hands a subgraph just the keys, the subgraph resolves what it owns, and
the join happens at the gateway.

### What the learner writes in Kotlin

| Annotation | Subgraph | What it is |
|:--|:--|:--|
| `@QueryMapping products()` | catalog | an ordinary query resolver |
| `@EntityMapping product(idList: List<String>)` | personalization | the **reference resolver** — turns keys from `_entities` into `Product` stubs |
| `@SchemaMapping cta(product, segment)` | personalization | resolves the extended field |

The reference resolver is the federation-specific concept. Personalization has
no product data, so it wraps each id — but it is the hook that lets a service
extend a type it does not own. Spring hands it the whole key list at once.

### N+1, honestly

Two layers, and the demo shows both:

- **Across services**, the gateway already batches: twelve products became one
  `_entities` call. That is the protocol, not code you write.
- **Within personalization**, `cta` runs once per product. In-memory, that is
  free. Against a real data source, `@BatchMapping` is the fix.

Known wrinkle: `@BatchMapping` does not take field arguments cleanly, and `cta`
has one. That is the cost of putting `segment` on the field. With a header
instead, `cta` has no argument and batching is trivial — worth saying to the
FE team as "here is what changes in production" rather than hiding.

## 4. Who writes what

Plumbing is agent work; domain code is the learner's. The agent goes first and
leaves a **walking skeleton** — placeholder schemas, everything running end to
end — so the learner is never debugging Gradle or Docker while learning
federation.

### Agent, before the learner starts

| What | Why plumbing |
|:--|:--|
| Multi-module Gradle, version catalog, `federation-jvm` 6.2.1, ktlint/detekt/Kover carried over | setup tax; verified versions |
| Both `Application.kt` mains; `application.yml` per module (8081 / 8082) | boilerplate |
| The `FederationSchemaFactory` `@Bean` in each subgraph, **with a written explainer** | five lines of federation-specific wiring — see the reminder below |
| `SeedData.kt` — 12 products, 4 categories, 2 CTAs, 4 variants, lifted from `kotlin-ramp-up/contentful/seed.json` | fixture; real data, no HTTP client |
| Placeholder SDL in both modules (`type Query { hello: String }`) so composition succeeds on commit 1 | the walking skeleton |
| `gateway/docker-compose.yml`, gateway config, `dev.sh`, `smoke.sh` | the loop |
| Test scaffolding: `HttpGraphQlTester` setup, **one** example test per module | proves the wiring; the learner owns the rest |
| `README.md`; a draft of the FE-facing explainer in `docs/` | drafts, for the learner to edit |

**Reminder, recorded at the learner's request:** the `FederationSchemaFactory`
bean is the one piece of agent-written code that encodes a federation concept.
When it is written, it gets its own explainer, and the learner is to be
reminded to **study it carefully rather than skim it**.

### Learner, roughly in order

| What | Est. | Concept |
|:--|--:|:--|
| `catalog.graphqls` | 30m | authoring the FE contract; `@key`; nullability as blast radius |
| Data classes: `Product`, `Category`, `CallToAction`, `Segment` | 20m | Kotlin data classes and enums, chosen deliberately |
| `CatalogController` — `@QueryMapping products`, `product(id)` | 30m | ordinary resolvers |
| `personalization.graphqls` | 15m | extending an entity you do not own |
| `PersonalizationController` — `@EntityMapping`, `@SchemaMapping cta`, segment→variant lookup | 45m | **the reference resolver** — the genuinely new idea |
| Run the loop; watch `_entities` arrive in the logs; fix what breaks | 45m | seeing it work |
| Tests: VIP gets urgency; unknown id gives null; the federated query returns merged rows | 45m | Spring GraphQL testing |
| Edit the explainer until every sentence is defensible | 30m | the demo |

About four hours — the budget's floor.

### Stretch goals run alongside

Both C and B are mostly plumbing again. If the core lands, the agent scaffolds
C while the learner reads what it produced; the learner then decides where the
remaining time goes.

## 5. Error handling

Minimal by design. Three cases matter because the FE team will ask.

**Personalization is down.** Stop the container and re-run the query: every
product returns with `cta: null` plus an entry in `errors[]`. Catalog data still
arrives. A BFF would have returned a 500 for the page. Do this *on purpose* in
the demo — it is federation's most persuasive thirty seconds.

**Nullability is the blast radius.** That degradation works because
`cta: CallToAction` is nullable. A null in a non-null field propagates upward to
the nearest nullable ancestor; had it been `CallToAction!`, a personalization
failure would null the parent `Product`, and via `products: [Product!]!`, the
whole list. Rule: catalog's own fields stay non-null; every field a *different*
service contributes is nullable. This is a schema-design responsibility the
learner now owns, and it goes in the explainer explicitly.

**The cheap ones.** Unknown id in `_entities` → null `cta`, no error. Invalid
segment → validation error at the gateway before any subgraph is called (the
enum earning its two lines). Composition conflict — add `name` to
personalization's `Product` — → `hive dev` fails naming the field both services
claim; five minutes, and it is the composition concept made visible without a
registry.

## 6. Testing

Three layers, each testing a different thing.

**Per-subgraph, in Gradle — the learner's tests.** `HttpGraphQlTester` boots
the subgraph and sends real queries.

- catalog: `products` returns 12 and a known SKU has the right name and price;
  `product(id:)` for an unknown id returns null, not an error.
- personalization: `_entities` with a `Product` representation and
  `segment: VIP` returns the urgency variant; `NEWSLETTER` returns `control`; an
  unknown id yields null `cta`, no error.

The `_entities` test exercises the reference resolver **without a gateway** —
the federation-specific code is unit-testable in isolation.

**Composition — one command, asserted.** `dev.sh` runs `hive dev` and fails
loudly if composition rejects the schemas.

**Gateway smoke test — a script.** `smoke.sh` runs the federated query with
`curl` and asserts 12 products and at least one non-null `cta`. Spinning the
gateway up inside JUnit would need Testcontainers plus a way to hand it the
subgraph jars; not in four hours.

**Carried over:** Kover 80% line floor, ktlint, detekt.

**Not tested, on purpose:** `FederationSchemaFactory` wiring, query planning,
`_service { sdl }` beyond "it responds."

---

## Ticket breakdown

Each ticket is one reviewable PR and carries: acceptance criteria, **the
concept it teaches** (so expected confusion is distinguishable from a real
problem), and **what may be assumed to exist**. Agent tickets land first so
every learner ticket starts from a running system.

| # | Ticket | Who | Teaches |
|:--|:--|:--|:--|
| **Phase 0 — scaffold** | | | |
| 1 | Repo skeleton, catalog, gates, placeholder SDLs, walking skeleton | agent | — |
| 2 | `FederationSchemaFactory` bean + explainer *(study, don't skim)* | agent | what turns a server into a subgraph |
| 3 | `SeedData.kt` from `contentful/seed.json` | agent | — |
| 4 | Gateway: compose, `hive dev`, `dev.sh`, `smoke.sh` | agent | — |
| 5 | Test scaffolding + one example per module | agent | — |
| **Phase 1 — catalog** | | | |
| 6 | Catalog schema | learner | FE contract; `@key`; nullability |
| 7 | Catalog resolvers + tests | learner | `@QueryMapping`; data classes |
| **Phase 2 — personalization** | | | |
| 8 | Personalization schema | learner | extending an entity |
| 9 | Reference resolver, `cta`, lookup, tests | learner | **`@EntityMapping`** |
| **Phase 3 — integrate** | | | |
| 10 | Loop green; `_entities` in logs; degradation demo | learner | partial results |
| 11 | FE explainer | both | the demo |
| **Stretch** | | | |
| 12 | Hive registry: publish, break, watch the check fail | agent scaffolds, learner drives | the pipeline |
| 13 | Live Contentful behind catalog | agent scaffolds, learner wires | data source behind a subgraph |

Ticket 9 is the point of the project. Ticket 1 must also create the issues for
2–13 on the board before any other branch exists, per the repo's rules — with
12 and 13 labeled `deferred`, so the stretch goals are visible without
pretending they are scheduled.

## Open questions, carried

None block the core loop. Answers from colleagues would sharpen the demo:

1. Which library the company's subgraphs use (could change §"Library").
2. Apollo Federation v1 or v2 (changes the `@link` line and available directives).
3. Whether Hive is the gateway or only the registry (changes what runs locally).
4. What a typical BFF endpoint assembles today (changes the demo query).
