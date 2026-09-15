# graphql-federation-ramp-up

A two-subgraph GraphQL Federation demo in Kotlin and Spring for GraphQL,
composed by Hive Gateway. Built to learn entity resolution, `@key` and
reference resolvers, and composition end to end before working on production
subgraphs.

**The project.** A **catalog** service owns products; a **personalization**
service extends `Product` with which call-to-action to show a given shopper.
Neither knows the other exists. The gateway composes both into one graph and
answers a single query — *products, each with its CTA* — that a BFF used to
assemble by hand.

**Constraints.** The Kotlin schemas and resolvers are hand-written; agents do
the plumbing. Runs locally in three processes and one container; nothing is
deployed. Time budget is 4–8 hours of hand-written work.

**Stack.** Kotlin 2.4 · Spring Boot 4.1 · Spring for GraphQL 2.0 ·
Apollo Federation v2 via `federation-graphql-java-support` 6.2.1 ·
Hive Gateway · Hive CLI for local composition.

**Stretch goals, in order.** Publish both schemas to the Hive registry and
watch a breaking-change check fail; then back the catalog with live Contentful
data from the `kotlin-ramp-up` space.

## Run it

```sh
./dev.sh        # build, start both subgraphs, compose, start the gateway
./smoke.sh      # in another terminal: prove the federated join
```

GraphiQL: `http://localhost:8081/graphiql`, `:8082/graphiql`. Gateway: `http://localhost:4000/graphql`.

Stop the running loop with Ctrl-C before starting `./dev.sh` again: it refuses to
start while 8081, 8082 or 4000 is busy, so it can never compose against a
subgraph still running stale code.

Design: [docs/superpowers/specs/2026-09-15-federation-demo-design.md](docs/superpowers/specs/2026-09-15-federation-demo-design.md).
