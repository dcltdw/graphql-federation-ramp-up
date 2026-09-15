# Federation Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two Spring for GraphQL subgraphs in Kotlin, composed locally by Hive Gateway, answering one federated query — with every schema and resolver hand-written by the learner, and every piece of plumbing built by the agent first.

**Architecture:** One Gradle build, two Spring Boot modules (`catalog` on 8081, `personalization` on 8082), a `gateway/` directory holding Hive Gateway in Docker Compose. Subgraphs expose federated SDL at `_service { sdl }`; the Hive CLI composes both into `supergraph.graphql`; the gateway loads it. Catalog owns `Product`; personalization extends it with `cta`. Neither knows the other exists.

**Tech Stack:** Kotlin 2.4.10 · Spring Boot 4.1.1 · Spring for GraphQL 2.0.5 (BOM-managed) · `federation-graphql-java-support` 6.2.1 · kotlinx.serialization 1.11.0 · Hive CLI 0.63.x · Hive Gateway 2.14.x · Java 21 toolchain · ktlint / detekt / Kover

**Spec:** `docs/superpowers/specs/2026-09-15-federation-demo-design.md`

## Global Constraints

- **The agent/learner split is the point.** Tasks 1–5 and 11 are agent work. Tasks 6–10 are the learner's hand-written Kotlin; the executor's role there is to verify prerequisites, **stop**, and later review. An executor that writes the learner's resolvers has failed the plan, however good the code.
- `federation-graphql-java-support` is **6.2.1**. Not 7.x — that line targets graphql-java 26; Spring Boot 4.1.1 ships 25.
- Java **21** toolchain, and the Gradle daemon pinned to 21 via `gradle/gradle-daemon-jvm.properties` — detekt 1.23.8 runs in-process and cannot run on 25.
- Ports: catalog **8081**, personalization **8082**, gateway **4000**.
- Kover line-coverage floor **80%** per module; ktlint and detekt in `build`, same settings as `kotlin-ramp-up`.
- `gateway/supergraph.graphql` is **generated** and gitignored. Never hand-edit it.
- Nothing deploys. Local only.
- Every task maps to a GitHub issue on board #11. Move the card to **In Progress** when starting and **Done** when the PR merges. PR bodies use the `dcltdw:opening-a-pr` skill; merges use `dcltdw:cleaning-up-after-pr-merge`.
- Commits carry the `Co-Authored-By` trailer given in the session.
- **Verify, don't assert.** Every "Expected:" line in this plan is a claim to be checked against actual output. A task is not done until its `./gradlew build` has been watched succeed.

---

## File Structure

```
graphql-federation-ramp-up/
├── settings.gradle.kts                          # Task 1 — includes :catalog, :personalization
├── build.gradle.kts                             # Task 1 — shared config applied to subprojects
├── gradle/
│   ├── libs.versions.toml                       # Task 1 — all versions, one place
│   ├── gradle-daemon-jvm.properties             # Task 1 — daemon on Java 21
│   └── wrapper/                                 # Task 1 — Gradle 9.x wrapper
├── config/detekt/detekt.yml                     # Task 1 — copied from kotlin-ramp-up
├── catalog/
│   ├── build.gradle.kts                         # Task 1
│   └── src/
│       ├── main/kotlin/dev/dcltdw/catalog/
│       │   ├── CatalogApplication.kt            # Task 1 — main
│       │   ├── FederationConfig.kt              # Task 2 — the FederationSchemaFactory bean
│       │   ├── HelloController.kt               # Task 1 — placeholder; learner deletes in Task 7
│       │   └── (Product.kt, Category.kt, CatalogController.kt — learner, Tasks 6–7)
│       ├── main/resources/
│       │   ├── application.yml                  # Task 1 — port 8081
│       │   ├── graphql/catalog.graphqls          # Task 1 placeholder; learner rewrites in Task 6
│       │   └── seed/products.json               # Task 3 — from Contentful
│       └── test/kotlin/dev/dcltdw/catalog/
│           ├── CatalogApplicationTest.kt        # Task 1 — plain HTTP smoke; Task 5 upgrades
│           └── (CatalogControllerTest.kt — learner, Task 7)
├── personalization/                             # mirror of catalog, package dev.dcltdw.personalization
│   └── src/main/resources/seed/ctas.json        # Task 3
├── gateway/
│   ├── docker-compose.yml                       # Task 4
│   ├── sdl/                                     # Task 4 — fetched SDL, gitignored
│   └── supergraph.graphql                       # Task 4 — generated, gitignored
├── dev.sh                                       # Task 4
├── smoke.sh                                     # Task 4
└── docs/
    ├── federation-schema-factory.md             # Task 2 — the explainer to study
    ├── for-the-fe-team.md                       # Task 11 — draft for the learner to finish
    └── queries/*.graphql                        # Task 11
```

Split by responsibility: each module owns its schema, its resolvers, its seed. `gateway/` holds nothing Kotlin. `docs/` holds nothing the build reads.

---

### Task 1: Repo skeleton and walking skeleton — issue #2

**Files:**
- Create: `settings.gradle.kts`, `build.gradle.kts`, `gradle/libs.versions.toml`, `gradle/gradle-daemon-jvm.properties`, `config/detekt/detekt.yml`
- Create: `catalog/build.gradle.kts`, `catalog/src/main/kotlin/dev/dcltdw/catalog/CatalogApplication.kt`, `catalog/src/main/kotlin/dev/dcltdw/catalog/HelloController.kt`, `catalog/src/main/resources/application.yml`, `catalog/src/main/resources/graphql/catalog.graphqls`
- Create: the same five files under `personalization/`, package `dev.dcltdw.personalization`, port 8082
- Test: `catalog/src/test/kotlin/dev/dcltdw/catalog/CatalogApplicationTest.kt` and the personalization mirror
- Modify: `.gitignore` — add `gateway/sdl/` and `gateway/supergraph.graphql`

**Interfaces:**
- Consumes: nothing.
- Produces: two runnable Spring Boot apps answering `{ hello }` at `/graphql`; the version catalog aliases `libs.spring.boot.starter.graphql`, `libs.federation.jvm`, `libs.kotlinx.serialization.json` that every later task depends on.

- [ ] **Step 1: Bootstrap the Gradle wrapper**

The repo has no wrapper yet. Use the Gradle already on this machine via `kotlin-ramp-up`'s wrapper to generate one:

```bash
cd ~/Github/graphql-federation-ramp-up
~/Github/kotlin-ramp-up/gradlew wrapper --gradle-version 9.7.1 --distribution-type bin
ls gradle/wrapper/   # expect gradle-wrapper.jar and gradle-wrapper.properties
```

- [ ] **Step 2: Version catalog**

`gradle/libs.versions.toml`:

```toml
[versions]
kotlin = "2.4.10"
springBoot = "4.1.1"
springDependencyManagement = "1.1.7"
detekt = "1.23.8"
kover = "0.9.9"
ktlint = "14.2.0"
kotlinxSerialization = "1.11.0"
# 6.2.1 targets graphql-java 25, which the Spring Boot 4.1.1 BOM ships.
# 7.x targets graphql-java 26. Do not bump without bumping Boot.
federationJvm = "6.2.1"

[libraries]
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-starter-graphql = { module = "org.springframework.boot:spring-boot-starter-graphql" }
spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }
spring-boot-starter-graphql-test = { module = "org.springframework.boot:spring-boot-starter-graphql-test" }
jackson-module-kotlin = { module = "com.fasterxml.jackson.module:jackson-module-kotlin" }
kotlin-reflect = { module = "org.jetbrains.kotlin:kotlin-reflect" }
kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "kotlinxSerialization" }
federation-jvm = { module = "com.apollographql.federation:federation-graphql-java-support", version.ref = "federationJvm" }

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-spring = { id = "org.jetbrains.kotlin.plugin.spring", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
spring-boot = { id = "org.springframework.boot", version.ref = "springBoot" }
spring-dependency-management = { id = "io.spring.dependency-management", version.ref = "springDependencyManagement" }
detekt = { id = "io.gitlab.arturbosch.detekt", version.ref = "detekt" }
kover = { id = "org.jetbrains.kotlinx.kover", version.ref = "kover" }
ktlint = { id = "org.jlleitschuh.gradle.ktlint", version.ref = "ktlint" }
```

- [ ] **Step 3: Settings, daemon pin, detekt config**

`settings.gradle.kts`:

```kotlin
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "graphql-federation-ramp-up"

include("catalog", "personalization")
```

`gradle/gradle-daemon-jvm.properties`:

```properties
# detekt 1.23.8 runs in-process in the daemon and its bundled compiler
# throws on a JDK 25 runtime. Pin the daemon; Gradle provisions the JDK.
toolchainVersion=21
```

Copy `config/detekt/detekt.yml` verbatim from `~/Github/kotlin-ramp-up/config/detekt/detekt.yml`.

- [ ] **Step 4: Root build — shared config for both modules**

`build.gradle.kts`:

```kotlin
import io.gitlab.arturbosch.detekt.Detekt
import io.gitlab.arturbosch.detekt.DetektCreateBaselineTask
import io.gitlab.arturbosch.detekt.getSupportedKotlinVersion
import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.gradle.api.tasks.testing.logging.TestLogEvent

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.spring) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.spring.boot) apply false
    alias(libs.plugins.spring.dependency.management) apply false
    alias(libs.plugins.detekt) apply false
    alias(libs.plugins.kover) apply false
    alias(libs.plugins.ktlint) apply false
}

subprojects {
    apply(plugin = "org.jetbrains.kotlin.jvm")
    apply(plugin = "org.jetbrains.kotlin.plugin.spring")
    apply(plugin = "org.jetbrains.kotlin.plugin.serialization")
    apply(plugin = "org.springframework.boot")
    apply(plugin = "io.spring.dependency-management")
    apply(plugin = "io.gitlab.arturbosch.detekt")
    apply(plugin = "org.jetbrains.kotlinx.kover")
    apply(plugin = "org.jlleitschuh.gradle.ktlint")

    group = "dev.dcltdw"
    version = "0.1.0"

    repositories { mavenCentral() }

    extensions.configure<JavaPluginExtension> {
        toolchain { languageVersion = JavaLanguageVersion.of(21) }
    }

    extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension> {
        compilerOptions { freeCompilerArgs.addAll("-Xjsr305=strict") }
    }

    extensions.configure<io.gitlab.arturbosch.detekt.extensions.DetektExtension> {
        buildUponDefaultConfig = true
        config.setFrom(files("$rootDir/config/detekt/detekt.yml"))
    }

    // detekt 1.23.8 is built against Kotlin 2.0.21; pin only its own analysis classpath.
    configurations.matching { it.name == "detekt" }.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "org.jetbrains.kotlin") useVersion(getSupportedKotlinVersion())
        }
    }
    tasks.withType<Detekt>().configureEach { jvmTarget = "21" }
    tasks.withType<DetektCreateBaselineTask>().configureEach { jvmTarget = "21" }

    extensions.configure<kotlinx.kover.gradle.plugin.dsl.KoverProjectExtension> {
        reports {
            filters { excludes { classes("dev.dcltdw.*.*ApplicationKt") } }
            verify {
                rule {
                    minBound(minValue = 80, coverageUnits = kotlinx.kover.gradle.plugin.dsl.CoverageUnit.LINE)
                }
            }
        }
    }

    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
        testLogging {
            events(TestLogEvent.FAILED)
            exceptionFormat = TestExceptionFormat.FULL
            showExceptions = true
            showCauses = true
            showStackTraces = false
        }
    }

    tasks.named<Jar>("jar") { enabled = false }
}
```

- [ ] **Step 5: Catalog module**

`catalog/build.gradle.kts`:

```kotlin
dependencies {
    implementation(libs.spring.boot.starter.web)
    implementation(libs.spring.boot.starter.graphql)
    implementation(libs.jackson.module.kotlin)
    implementation(libs.kotlin.reflect)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.federation.jvm)

    testImplementation(libs.spring.boot.starter.test)
}
```

`catalog/src/main/kotlin/dev/dcltdw/catalog/CatalogApplication.kt`:

```kotlin
package dev.dcltdw.catalog

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class CatalogApplication

@Suppress("SpreadOperator")
fun main(args: Array<String>) {
    runApplication<CatalogApplication>(*args)
}
```

`catalog/src/main/resources/application.yml`:

```yaml
spring:
  application:
    name: catalog
  graphql:
    graphiql:
      enabled: true      # http://localhost:8081/graphiql — handy while hand-writing schemas

server:
  port: 8081
```

`catalog/src/main/resources/graphql/catalog.graphqls` — the placeholder the learner replaces in Task 6:

```graphql
# PLACEHOLDER. Replaced by the real catalog schema in issue #7.
# It exists so that composition (issue #5) succeeds before any real schema does.
type Query {
  hello: String
}
```

`catalog/src/main/kotlin/dev/dcltdw/catalog/HelloController.kt`:

```kotlin
package dev.dcltdw.catalog

import org.springframework.graphql.data.method.annotation.QueryMapping
import org.springframework.stereotype.Controller

/** Placeholder resolver for the placeholder schema. Deleted in issue #7. */
@Controller
class HelloController {
    @QueryMapping
    fun hello(): String = "hello from catalog"
}
```

- [ ] **Step 6: Personalization module — mirror with three substitutions**

Same five files under `personalization/`, with: package `dev.dcltdw.personalization`; class `PersonalizationApplication`; `application.yml` name `personalization`, port **8082**; `HelloController.hello()` returns `"hello from personalization"`; schema file named `personalization.graphqls`.

- [ ] **Step 7: Write the failing walking-skeleton test (catalog)**

`catalog/src/test/kotlin/dev/dcltdw/catalog/CatalogApplicationTest.kt`:

```kotlin
package dev.dcltdw.catalog

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.test.context.SpringBootTest
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse

/**
 * Proves the module boots and serves GraphQL over plain HTTP. Issue #6 replaces
 * this with HttpGraphQlTester; until then this is the walking skeleton's pulse.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CatalogApplicationTest {
    @field:Value("\${local.server.port}")
    private var port: Int = 0

    @Test
    fun `the placeholder query answers over HTTP`() {
        val request =
            HttpRequest
                .newBuilder(URI.create("http://localhost:$port/graphql"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("""{"query":"{ hello }"}"""))
                .build()
        val response = HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.ofString())

        assertThat(response.statusCode()).isEqualTo(200)
        assertThat(response.body()).contains("hello from catalog")
    }
}
```

Mirror for personalization with `"hello from personalization"`.

- [ ] **Step 8: Run to verify it fails**

Run: `./gradlew :catalog:test --console=plain`
Expected: FAIL — compilation error, `HelloController` or the schema not yet present if steps were done out of order; otherwise the test runs and passes. If it passes on first run, that is fine: the step exists to prove the harness reports failures. Break the expected string to `"nope"`, watch it fail, restore it.

- [ ] **Step 9: Run both modules' tests and the full build**

Run: `./gradlew build --console=plain`
Expected: `BUILD SUCCESSFUL`; both `:catalog:test` and `:personalization:test` pass; `koverVerify` passes for both (the placeholder resolver is fully covered); ktlint and detekt clean.

- [ ] **Step 10: Boot both and check by hand**

```bash
./gradlew :catalog:bootRun &     # wait for "Started CatalogApplication"
curl -s localhost:8081/graphql -H 'Content-Type: application/json' -d '{"query":"{ hello }"}'
# expect {"data":{"hello":"hello from catalog"}}
```

Same on 8082. Stop both.

- [ ] **Step 11: gitignore additions, then commit**

Append to `.gitignore`:

```
# Generated by dev.sh — never hand-edit
gateway/sdl/
gateway/supergraph.graphql
```

```bash
git add -A
git commit -m "Add the multi-module skeleton with placeholder schemas

Two Spring Boot modules, catalog on 8081 and personalization on 8082,
each serving a placeholder { hello } query. The placeholders exist so
composition can succeed before any real schema does; the learner replaces
them in #7 and #9.

federation-jvm is pinned to 6.2.1 because 7.x targets graphql-java 26 and
the Spring Boot 4.1.1 BOM ships 25. Java 21 toolchain and daemon pin
carried over from kotlin-ramp-up for detekt.

Refs #2"
```

Open the PR with the `dcltdw:opening-a-pr` skill, `Closes #2`.

---

### Task 2: FederationSchemaFactory and its explainer — issue #3

**Files:**
- Create: `catalog/src/main/kotlin/dev/dcltdw/catalog/FederationConfig.kt`, personalization mirror
- Create: `docs/federation-schema-factory.md`
- Test: add one test to each `*ApplicationTest.kt`

**Interfaces:**
- Consumes: Task 1's modules.
- Produces: `_service { sdl }` on both modules — which Task 4's `dev.sh` fetches. `_entities` on both — which the learner's `@EntityMapping` in Task 9 serves.

- [ ] **Step 1: Write the failing test**

Add to `CatalogApplicationTest.kt`:

```kotlin
    @Test
    fun `the federation service endpoint exposes the SDL`() {
        val request =
            HttpRequest
                .newBuilder(URI.create("http://localhost:$port/graphql"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString("""{"query":"{ _service { sdl } }"}"""))
                .build()
        val response = HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.ofString())

        assertThat(response.statusCode()).isEqualTo(200)
        assertThat(response.body()).contains("type Query")
        assertThat(response.body()).doesNotContain("\"errors\"")
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `./gradlew :catalog:test --tests '*federation*' --console=plain`
Expected: FAIL — the body contains `"errors"` because `_service` is not a field on the placeholder schema.

- [ ] **Step 3: The bean**

`catalog/src/main/kotlin/dev/dcltdw/catalog/FederationConfig.kt`:

```kotlin
package dev.dcltdw.catalog

import org.springframework.boot.graphql.autoconfigure.GraphQlSourceBuilderCustomizer
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.graphql.data.federation.FederationSchemaFactory

/**
 * Turns this ordinary GraphQL server into a federation subgraph.
 *
 * Two things get added to the schema that the SDL file never mentions:
 *  - `_service { sdl }` — how the gateway (and `hive dev`) learns this
 *    subgraph's schema, with the federation directives intact.
 *  - `_entities(representations:)` — how the gateway hands this subgraph a
 *    list of entity KEYS and asks it to resolve the fields it owns. Served by
 *    `@EntityMapping` methods in controllers.
 *
 * Read docs/federation-schema-factory.md before writing any schema.
 */
@Configuration
class FederationConfig {
    @Bean
    fun federationSchemaFactory(): FederationSchemaFactory = FederationSchemaFactory()

    @Bean
    fun federationCustomizer(factory: FederationSchemaFactory): GraphQlSourceBuilderCustomizer =
        GraphQlSourceBuilderCustomizer { builder -> builder.schemaFactory(factory::createGraphQLSchema) }
}
```

If the import `org.springframework.boot.graphql.autoconfigure.GraphQlSourceBuilderCustomizer` does not resolve under Spring Boot 4.1.1, the class lives at `org.springframework.boot.autoconfigure.graphql.GraphQlSourceBuilderCustomizer` — try that second. Record which in the PR.

Mirror in personalization.

- [ ] **Step 4: Run to verify it passes**

Run: `./gradlew build --console=plain`
Expected: PASS on both modules. If Kover drops below 80% because `FederationConfig` is uncovered, the `_service` test covers it — check the Kover report before adjusting anything.

- [ ] **Step 5: The explainer**

`docs/federation-schema-factory.md`. This is what the learner is to study carefully before issue #7. It must cover, in this order and in plain prose:

1. **What a subgraph is** — an ordinary GraphQL server plus two extra queries the gateway relies on.
2. **`_service { sdl }`** — returns the schema *with* federation directives. This is what `hive dev` and the registry read. Show the actual output from running the query against catalog after this task.
3. **`_entities(representations: [...])`** — the gateway sends a list of `{ __typename, <key fields> }` objects and asks for fields this subgraph owns. Show the exact query shape the gateway will send to personalization in Task 9, using `Product` and `id`.
4. **What `FederationSchemaFactory` does** — parses the SDL, validates the federation directives, adds `_service` and `_entities` to `Query`, and wires `_entities` to `@EntityMapping` methods. Point at the five lines in `FederationConfig.kt`.
5. **What the learner writes against it** — `@EntityMapping fun product(@Argument idList: List<String>): List<Product?>` in Task 9, with one paragraph on why it takes a *list*: the gateway batches all keys into one call.
6. **What it does not do** — no query planning, no composition, no talking to the other subgraph. That is the gateway's job.

End with a short "check yourself" list of five questions the learner should be able to answer from memory — e.g. *"What does the gateway send to `_entities`, and what does it expect back?"*

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Wire FederationSchemaFactory in both subgraphs

Adds _service { sdl } and _entities to each schema, which is what makes an
ordinary GraphQL server a federation subgraph. The explainer in docs/ is
the one piece of agent-written code that encodes a federation concept, and
is to be studied before the learner writes any schema.

Refs #3"
```

PR with `Closes #3`. **In the PR body, and in the merge report, remind the learner to read `docs/federation-schema-factory.md` carefully before starting #7.**

---

### Task 3: Seed data from the Contentful space — issue #4

**Files:**
- Create: `catalog/src/main/resources/seed/products.json`, `catalog/src/main/resources/seed/categories.json`
- Create: `personalization/src/main/resources/seed/ctas.json`
- Create: `scripts/extract-seed.py` (kept in the repo so the extraction is reproducible)

**Interfaces:**
- Consumes: `~/Github/kotlin-ramp-up/contentful/seed.json`.
- Produces: JSON resources with **these exact shapes**, which the learner's data classes in Tasks 7 and 9 deserialize with kotlinx.serialization:

```json
// products.json — array of:
{ "id": "CAT-TREE-DLX", "name": "Deluxe Cat Tree", "priceMinor": 18900,
  "currency": "USD", "category": "cats", "tags": ["premium"], "regions": ["US"] }

// categories.json — array of:
{ "key": "cats", "name": "Cats" }

// ctas.json:
{ "segments": ["vip", "newsletter", "firstTimeBuyer"],
  "ctas": [ { "ctaId": "free-shipping", "name": "Free Shipping Banner",
              "variants": [ { "variantKey": "control", "headline": "Free shipping on orders over $50" }, ... ] } ] }
```

Decision recorded for issue #4's "pick and say which": **JSON resources, not Kotlin values.** The learner writes the data classes and the loader — they already know kotlinx.serialization from `kotlin-ramp-up` — so the agent producing typed Kotlin would pre-empt Tasks 7 and 9.

- [ ] **Step 1: The extraction script**

`scripts/extract-seed.py`:

```python
#!/usr/bin/env python3
"""Extract seed fixtures from the kotlin-ramp-up Contentful export.

Run from the repo root:  python3 scripts/extract-seed.py
Reads ~/Github/kotlin-ramp-up/contentful/seed.json; writes the three JSON
resources the subgraphs load. Product identity is the SKU.
"""
import json
from pathlib import Path

SRC = Path.home() / "Github/kotlin-ramp-up/contentful/seed.json"
CATALOG = Path("catalog/src/main/resources/seed")
PERSONALIZATION = Path("personalization/src/main/resources/seed")


def v(field):
    return field.get("en-US") if isinstance(field, dict) else field


seed = json.loads(SRC.read_text())
by_id = {e["sys"]["id"]: e for e in seed["entries"]}
of_type = lambda t: [e for e in seed["entries"] if e["sys"]["contentType"]["sys"]["id"] == t]

categories = [{"key": v(e["fields"]["key"]), "name": v(e["fields"]["name"])} for e in of_type("category")]
category_key = {e["sys"]["id"]: v(e["fields"]["key"]) for e in of_type("category")}

products = []
for e in of_type("product"):
    f = e["fields"]
    products.append({
        "id": v(f["sku"]),
        "name": v(f["name"]),
        "priceMinor": v(f["priceMinor"]),
        "currency": v(f["currency"]),
        "category": category_key[v(f["category"])["sys"]["id"]],
        "tags": v(f.get("tags")) or [],
        "regions": v(f.get("regions")) or [],
    })
products.sort(key=lambda p: p["id"])

variants = {e["sys"]["id"]: e for e in of_type("ctaVariant")}
ctas = []
for e in of_type("cta"):
    f = e["fields"]
    ctas.append({
        "ctaId": v(f["ctaId"]),
        "name": v(f["name"]),
        "variants": [
            {"variantKey": v(variants[l["sys"]["id"]]["fields"]["variantKey"]),
             "headline": v(variants[l["sys"]["id"]]["fields"]["headline"])}
            for l in v(f["variants"])
        ],
    })
segments = sorted(v(e["fields"]["segmentId"]) for e in of_type("segment"))

CATALOG.mkdir(parents=True, exist_ok=True)
PERSONALIZATION.mkdir(parents=True, exist_ok=True)
(CATALOG / "products.json").write_text(json.dumps(products, indent=2) + "\n")
(CATALOG / "categories.json").write_text(json.dumps(categories, indent=2) + "\n")
(PERSONALIZATION / "ctas.json").write_text(json.dumps({"segments": segments, "ctas": ctas}, indent=2) + "\n")
print(f"{len(products)} products, {len(categories)} categories, {len(ctas)} ctas, {len(segments)} segments")
```

- [ ] **Step 2: Run it and check the counts**

Run: `python3 scripts/extract-seed.py`
Expected: `12 products, 4 categories, 2 ctas, 3 segments`

- [ ] **Step 3: Verify the shapes by eye and by parse**

```bash
python3 -c "import json; p=json.load(open('catalog/src/main/resources/seed/products.json')); print(p[0]); assert all(set(x)=={'id','name','priceMinor','currency','category','tags','regions'} for x in p)"
python3 -c "import json; c=json.load(open('personalization/src/main/resources/seed/ctas.json')); print(c['segments']); print([ (x['ctaId'],[y['variantKey'] for y in x['variants']]) for x in c['ctas']])"
```

Expected: first product printed with all seven keys; segments `['firstTimeBuyer', 'newsletter', 'vip']`; ctas `[('free-shipping', ['control','urgency']), ('vip-early-access', ['control','personalized'])]`.

- [ ] **Step 4: Build still green, then commit**

Run: `./gradlew build --console=plain` — Expected: PASS (resources only; nothing reads them yet).

```bash
git add -A
git commit -m "Extract seed fixtures from the Contentful space

JSON resources rather than Kotlin values, so the learner writes the data
classes and the loader in #8 and #10 rather than inheriting them. Product
identity is the SKU. The extraction script stays in the repo so the
fixtures are reproducible from the source export.

Refs #4"
```

PR with `Closes #4`.

---

### Task 4: Gateway, local composition, dev.sh and smoke.sh — issue #5

**Files:**
- Create: `gateway/docker-compose.yml`, `dev.sh`, `smoke.sh`
- Modify: `README.md` — the three-command loop

**Interfaces:**
- Consumes: `_service { sdl }` from Task 2 on 8081 and 8082.
- Produces: a gateway on 4000 serving the composed supergraph; `dev.sh` and `smoke.sh` that Tasks 10 and 11 run.

- [ ] **Step 1: VERIFY FIRST — does `hive dev` do what the design assumes?**

This is the hinge of the local loop and the one step not yet run against this stack. Do it before writing anything else in this task.

```bash
cd gateway && npm init -y >/dev/null && npm install --save-dev @graphql-hive/cli @graphql-hive/gateway
npx hive dev --help
```

Expected: `--service`, `--url`, `--schema` and `--write` options are listed. Confirm `--schema <file>` lets you supply the SDL from a file while `--url` sets the *routing* URL the gateway will call — those need to differ (see step 3). **If `--schema` is absent or `hive dev` cannot compose from files:** fall back to Apollo's `rover supergraph compose` with a `supergraph.yaml` listing both subgraphs; everything downstream is unchanged. Record which path shipped in the PR body.

- [ ] **Step 2: Compose file**

`gateway/docker-compose.yml`:

```yaml
services:
  gateway:
    image: ghcr.io/graphql-hive/gateway:latest
    command: supergraph /gateway/supergraph.graphql
    ports:
      - "4000:4000"
    volumes:
      - ./supergraph.graphql:/gateway/supergraph.graphql:ro
    # The subgraphs run on the host. Inside the container, "localhost" is the
    # container, so the supergraph's routing URLs use host.docker.internal.
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

- [ ] **Step 3: dev.sh**

```bash
#!/usr/bin/env bash
# Bring the whole local loop up: both subgraphs, composition, the gateway.
#
# Composition needs each subgraph's SDL (fetched from localhost, where the
# subgraphs actually are) but must write ROUTING urls the gateway container
# can reach (host.docker.internal). Hence: fetch SDL to a file, then compose
# with --schema for the SDL and --url for routing.
set -euo pipefail
cd "$(dirname "$0")"

CATALOG=http://localhost:8081/graphql
PERSONALIZATION=http://localhost:8082/graphql
ROUTE_CATALOG=http://host.docker.internal:8081/graphql
ROUTE_PERSONALIZATION=http://host.docker.internal:8082/graphql

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

step "Building"
./gradlew -q assemble

step "Starting subgraphs"
java -jar catalog/build/libs/catalog-0.1.0.jar >gateway/catalog.log 2>&1 &
java -jar personalization/build/libs/personalization-0.1.0.jar >gateway/personalization.log 2>&1 &
trap 'kill $(jobs -p) 2>/dev/null; docker compose -f gateway/docker-compose.yml down >/dev/null 2>&1' EXIT

wait_for() {
  for _ in $(seq 1 60); do
    curl -sf "$1" -H 'Content-Type: application/json' -d '{"query":"{ __typename }"}' >/dev/null 2>&1 && return 0
    sleep 1
  done
  fail "$1 did not come up in 60s — see gateway/*.log"
}
wait_for "$CATALOG"; wait_for "$PERSONALIZATION"

step "Fetching federated SDL"
mkdir -p gateway/sdl
sdl() {
  curl -sf "$1" -H 'Content-Type: application/json' -d '{"query":"{ _service { sdl } }"}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["_service"]["sdl"])'
}
sdl "$CATALOG" > gateway/sdl/catalog.graphql
sdl "$PERSONALIZATION" > gateway/sdl/personalization.graphql

step "Composing the supergraph"
(cd gateway && npx hive dev \
  --service catalog --url "$ROUTE_CATALOG" --schema sdl/catalog.graphql \
  --service personalization --url "$ROUTE_PERSONALIZATION" --schema sdl/personalization.graphql \
  --write supergraph.graphql) || fail "composition failed — the two schemas do not compose"

step "Starting the gateway"
docker compose -f gateway/docker-compose.yml up -d
wait_for http://localhost:4000/graphql

step "Up"
echo "  gateway          http://localhost:4000/graphql"
echo "  catalog          $CATALOG"
echo "  personalization  $PERSONALIZATION"
echo "Ctrl-C to stop everything."
wait
```

`chmod +x dev.sh`. Adjust the `hive dev` flags to whatever step 1 showed; the *structure* — SDL from files, routing URLs separate — is the design.

- [ ] **Step 4: smoke.sh**

```bash
#!/usr/bin/env bash
# Prove the cross-service join happened: products from catalog, each with a
# cta from personalization, in ONE response from the gateway.
set -euo pipefail

QUERY='query { products { id name cta(segment: VIP) { variantKey headline } } }'
body=$(curl -sf http://localhost:4000/graphql -H 'Content-Type: application/json' \
  -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$QUERY")") \
  || { echo "gateway not reachable on 4000 — run ./dev.sh first"; exit 1; }

python3 - "$body" <<'EOF'
import json, sys
r = json.loads(sys.argv[1])
if "errors" in r and not r.get("data"):
    print("FAIL — gateway returned errors and no data:")
    print(json.dumps(r["errors"], indent=2)); sys.exit(1)
products = (r.get("data") or {}).get("products")
if products is None:
    print("FAIL — no `products` in the response. With the placeholder schemas this is EXPECTED until issue #8 lands."); sys.exit(1)
with_cta = [p for p in products if p.get("cta")]
print(f"products: {len(products)}   with a cta: {len(with_cta)}")
if not products:            print("FAIL — zero products"); sys.exit(1)
if not with_cta:            print("FAIL — no product carried a cta: the join did not happen. Expected until issue #10 lands."); sys.exit(1)
print("OK — the federated join works")
EOF
```

`chmod +x smoke.sh`.

- [ ] **Step 5: Run the loop with the placeholder schemas**

Run: `./dev.sh` in one terminal; in another:

```bash
curl -s localhost:4000/graphql -H 'Content-Type: application/json' -d '{"query":"{ hello }"}'
./smoke.sh
```

Expected: composition succeeds (two placeholder `Query.hello` fields — if composition *rejects* two `hello` fields as a conflict, rename personalization's to `helloPersonalization` and note it); `{ hello }` answers at 4000; `smoke.sh` prints the "EXPECTED until issue #8" line and exits 1. That failure is correct.

- [ ] **Step 6: README**

Replace the README's placeholder loop with:

````markdown
## Run it

```sh
./dev.sh        # build, start both subgraphs, compose, start the gateway
./smoke.sh      # in another terminal: prove the federated join
```

GraphiQL: `http://localhost:8081/graphiql`, `:8082/graphiql`. Gateway: `http://localhost:4000/graphql`.
````

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Add the gateway and the local composition loop

Hive Gateway in Compose on 4000, loading a supergraph that dev.sh composes
from both subgraphs' federated SDL. SDL is fetched from localhost but the
routing URLs are host.docker.internal, because inside the container
localhost is the container.

smoke.sh proves the join rather than liveness: it asserts products AND a
non-null cta in one response, and says so when either is expected to be
missing because a later issue has not landed.

Refs #5"
```

PR with `Closes #5`. State in the body which composition path shipped — `hive dev` or the `rover` fallback.

---

### Task 5: HttpGraphQlTester scaffolding — issue #6

**Files:**
- Modify: `catalog/build.gradle.kts`, `personalization/build.gradle.kts` — add the test starter
- Modify: both `*ApplicationTest.kt` — replace the JDK-client tests with `HttpGraphQlTester`

**Interfaces:**
- Produces: the test harness the learner copies in Tasks 7 and 9 — `@SpringBootTest(webEnvironment = RANDOM_PORT)` + `@AutoConfigureHttpGraphQlTester` + an injected `HttpGraphQlTester`.

- [ ] **Step 1: Dependency**

Add to both modules' `build.gradle.kts`:

```kotlin
    testImplementation(libs.spring.boot.starter.graphql.test)
```

- [ ] **Step 2: Rewrite the catalog test on the idiomatic harness**

Replace `CatalogApplicationTest.kt` entirely:

```kotlin
package dev.dcltdw.catalog

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.graphql.tester.AutoConfigureHttpGraphQlTester
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.graphql.test.tester.HttpGraphQlTester

/**
 * Proves the GraphQL test harness is wired: HttpGraphQlTester boots the module
 * and sends real queries over HTTP.
 *
 * DELETE the `hello` test once real tests exist (issue #8). Keep the `_service`
 * one — it guards the federation wiring from issue #3.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureHttpGraphQlTester
class CatalogApplicationTest {
    @Autowired
    private lateinit var graphQl: HttpGraphQlTester

    @Test
    fun `the placeholder query answers`() {
        graphQl
            .document("{ hello }")
            .execute()
            .path("hello")
            .entity(String::class.java)
            .isEqualTo("hello from catalog")
    }

    @Test
    fun `the federation service endpoint exposes the SDL`() {
        graphQl
            .document("{ _service { sdl } }")
            .execute()
            .path("_service.sdl")
            .entity(String::class.java)
            .matches { it.contains("type Query") }
    }
}
```

Mirror for personalization.

- [ ] **Step 3: Run and verify**

Run: `./gradlew build --console=plain`
Expected: PASS, four tests across two modules, Kover still ≥ 80%.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Move the walking-skeleton tests onto HttpGraphQlTester

The JDK HTTP client proved the module served GraphQL; HttpGraphQlTester is
the harness the learner's tests will use, with path-based assertions on
the response. The hello test is marked for deletion once real tests exist;
the _service test stays as the guard on federation wiring.

Refs #6"
```

PR with `Closes #6`.

**Phase 0 is complete when #2–#6 are merged.** Before handing over, the executor confirms on `main`: `./gradlew build` green, `./dev.sh` composes and serves `{ hello }` on 4000, `./smoke.sh` fails with the "EXPECTED until issue #8" message. Report that state, then **stop**.

---

### Task 6: Catalog schema — issue #7 — LEARNER

**The executor does not write this.** The executor's role:

- [ ] **Step 1: Confirm prerequisites** — #2–#6 merged; `main` builds; `dev.sh` runs. Move #7 to In Progress on the board **only when the learner says they are starting**.
- [ ] **Step 2: Remind** — before the learner starts: *read `docs/federation-schema-factory.md` carefully.*
- [ ] **Step 3: Wait.** The learner writes `catalog/src/main/resources/graphql/catalog.graphqls` per spec §2 and issue #7's acceptance criteria.
- [ ] **Step 4: Review the learner's PR** against:
  - `@link` line present with `import: ["@key"]`
  - `type Product @key(fields: "id")` with `id: ID!` and every catalog-owned field non-null
  - `product(id: ID!): Product` nullable; `products: [Product!]!` non-null
  - `dev.sh` still composes with the new schema
  - Nothing in the SDL that a resolver could not serve from `seed/products.json`
- [ ] **Step 5: Run the gates** — `./gradlew build`. The app must start with the schema loaded even though resolvers are absent; note that Spring for GraphQL tolerates unmapped fields at startup.

Questions the learner is likely to ask, and where the answer is: *"What fields should `Product` have?"* → `seed/products.json` is the answer. *"Why is `product(id:)` nullable?"* → spec §5, nullability as blast radius.

---

### Task 7: Catalog resolvers and tests — issue #8 — LEARNER

**The executor does not write this.** Executor's role:

- [ ] **Step 1: Confirm** #7 merged.
- [ ] **Step 2: Wait.** The learner writes `Product`, `Category`, `Currency`, a `SeedData` loader over `seed/products.json` and `seed/categories.json` using kotlinx.serialization, `CatalogController` with `@QueryMapping products()` and `product(@Argument id: String)`, and tests on `HttpGraphQlTester`.
- [ ] **Step 3: Review** against:
  - `Product` and `Category` are `data class`; `Currency` is an `enum class` with entries matching the JSON strings (`USD`, `GBP`, `EUR`) — or `@SerialName` if the learner chose other names
  - Kotlin property names match the SDL field names exactly, so no `@SchemaMapping` is needed on plain fields
  - Tests: `products` returns 12; a known SKU (`CAT-TREE-DLX`) has name `Deluxe Cat Tree` and `priceMinor` 18900; `product(id: "NOPE")` returns null with no errors
  - The `hello` placeholder and `HelloController` are deleted
  - `./gradlew build` green including Kover
- [ ] **Step 4: Run `dev.sh` and query catalog directly** at 8081 to confirm the seed loads outside the test JVM.

---

### Task 8: Personalization schema — issue #9 — LEARNER

**The executor does not write this.** Executor's role:

- [ ] **Step 1: Confirm** #8 merged.
- [ ] **Step 2: Wait.** The learner writes `personalization.graphqls` per spec §2.
- [ ] **Step 3: Review** against:
  - `type Product @key(fields: "id") { id: ID!  cta(segment: Segment!): CallToAction }` — `cta` **nullable**; `id` matches catalog's key byte-for-byte
  - `enum Segment { VIP NEWSLETTER FIRST_TIME_BUYER }`, `type CallToAction` with three non-null strings, `type Query { segments: [Segment!]! }`
  - `dev.sh` composes — two subgraphs now both declare `Product`, and composition accepts it because the keys agree
- [ ] **Step 4:** If composition fails, the most likely cause is a key mismatch; the second is a missing `@link`. Point, don't fix.

---

### Task 9: Reference resolver, `cta`, and the lookup — issue #10 — LEARNER

**The executor does not write this. This ticket is the point of the project.** Executor's role:

- [ ] **Step 1: Confirm** #9 merged. Remind: *re-read `docs/federation-schema-factory.md`, especially the `_entities` section.*
- [ ] **Step 2: Wait.** The learner writes a `Product` stub, `CallToAction`, `Segment`, a loader over `seed/ctas.json`, `PersonalizationController` with `@EntityMapping product(@Argument idList: List<String>): List<Product?>`, `@SchemaMapping cta(product: Product, @Argument segment: Segment): CallToAction?`, `@QueryMapping segments()`, and tests that send `_entities` queries directly.
- [ ] **Step 3: Review** against:
  - The `@EntityMapping` method takes `idList: List<String>` — the *batch* form — and returns one stub per key
  - The segment→variant lookup yields **different** variants for at least two segments, and reads headlines from the seed rather than hardcoding them
  - Tests, through `HttpGraphQlTester`, **with no gateway**: `_entities` + `segment: VIP` → `urgency`; `NEWSLETTER` → `control`; unknown id → null `cta`, no `errors`
  - `./gradlew build` green
- [ ] **Step 4: Expected confusion.** The learner has been told this is the ticket where "I don't understand what I'm supposed to do" is the correct first reaction. When they ask, answer with the explainer's §3 and §5, and with the exact `_entities` query shape — not with the code.

---

### Task 10: Integrate — issue #11 — LEARNER

**The executor supports; the learner drives.**

- [ ] **Step 1: Confirm** #10 merged.
- [ ] **Step 2:** The learner runs `./dev.sh` then `./smoke.sh`. Expected: `OK — the federated join works`.
- [ ] **Step 3:** The learner finds the `_entities` request in `gateway/personalization.log`. If nothing shows, the executor points at `logging.level.org.springframework.graphql: DEBUG` in `application.yml` — the learner adds it.
- [ ] **Step 4:** `docker compose -f gateway/docker-compose.yml stop` is the wrong target — the subgraphs are host processes. The learner stops **personalization** by killing its Java process, re-runs the query at 4000, and confirms: products return, `cta` is null, `errors[]` names the failure. Restarts it.
- [ ] **Step 5:** The learner adds `name: String` to personalization's `Product`, runs `./dev.sh`, watches composition **fail** naming the conflict, reverts.
- [ ] **Step 6: Review** the learner's README PR documenting the three demonstrations as the demo script.

**The core loop is complete when #11 merges.** Report: `smoke.sh` output, the observed `_entities` payload, and the degradation and composition-failure outputs. Then continue to Task 11.

---

### Task 11: FE explainer draft and sample queries — issue #12 — agent drafts, learner finishes

**Files:**
- Create: `docs/for-the-fe-team.md`, `docs/queries/catalog-with-ctas.graphql`, `docs/queries/one-product.graphql`, `docs/queries/segments.graphql`

- [ ] **Step 1: The three queries**

`docs/queries/catalog-with-ctas.graphql`:
```graphql
# The demo. One query, two services, one response.
query CatalogForShopper($segment: Segment!) {
  products {
    id
    name
    priceMinor
    currency
    cta(segment: $segment) { ctaId variantKey headline }
  }
}
```

`docs/queries/one-product.graphql`:
```graphql
query OneProduct($id: ID!, $segment: Segment!) {
  product(id: $id) { id name cta(segment: $segment) { headline } }
}
```

`docs/queries/segments.graphql`:
```graphql
{ segments }
```

- [ ] **Step 2: The explainer draft** — `docs/for-the-fe-team.md`, for engineers who are good at their jobs and new to federation. Do not explain GraphQL. Sections, each a short paragraph plus one concrete example from this repo:

  1. **What changed** — one graph, two services, and the gateway does the join a BFF used to do by hand. Show the query and the two subgraph calls it becomes.
  2. **Who owns which field, and how to tell** — the supergraph. Show the relevant lines of `gateway/supergraph.graphql`.
  3. **N+1, in two layers** — the gateway batches keys into one `_entities` call across services; `@BatchMapping` exists for within-service batching. Say which layer they get for free.
  4. **When a service is down** — partial results: `data` with `cta: null` *and* `errors[]`. **The client must read `errors[]`.** This is the silent-failure trap from the BFF world, in a new place — a page can look fine while personalization has been down for a week.
  5. **Nullability is the blast radius** — why `cta` is nullable and `name` is not. What `!` actually means.
  6. **What changes in production** — segment via header, not argument; the registry and breaking-change checks (issue #13).
  7. A request-flow diagram (Mermaid, since GitHub renders it).

- [ ] **Step 3: Commit and PR**, `Refs #12` — not `Closes`. The issue closes when the learner has edited every paragraph and can defend it; that is their half.

---

### Tasks 12–13: Stretch goals — issues #13 and #14 — DEFERRED

Not in this plan. Both are labeled `deferred` on the board. When the learner un-defers one, write a follow-up plan for it from its issue and spec §"Scope"; do not improvise it from this document.

---

## Self-Review

**Spec coverage.** §1 repo shape → Task 1. §1 composition and `hive dev` verify-first → Task 4 step 1. §2 schemas → Tasks 6, 8 (learner) with review criteria. §3 data flow and the three annotations → Task 9 review criteria; `_entities` test without a gateway → Task 9. §4 agent/learner split → the task structure itself; the `FederationSchemaFactory` explainer and study reminder → Task 2 and Tasks 6/9 step 1. §5 error handling — degradation, nullability, composition conflict → Task 10 steps 4–5, Task 11 §4–5. §6 testing — per-subgraph, composition asserted in `dev.sh`, `smoke.sh` → Tasks 4, 5, 7, 9. Gates carried over → Task 1. Ticket breakdown → one task per issue, #2–#14. Nothing in the spec lacks a task.

**Placeholders.** None: every code step carries its code; every learner task carries review criteria rather than "review the PR"; the two genuinely unverifiable points (`hive dev` flags, the `GraphQlSourceBuilderCustomizer` package) name the fallback and require the PR to record which shipped.

**Type consistency.** `idList: List<String>` in Task 2's explainer, Task 9's review, and the spec. `Product`/`Category`/`Currency`/`CallToAction`/`Segment` names match the SDL in spec §2 and the seed JSON keys in Task 3. Ports 8081/8082/4000 throughout. The JSON shapes in Task 3 use the same field names the SDL uses (`id`, `name`, `priceMinor`, `currency`, `tags`; `ctaId`, `variantKey`, `headline`), so the learner's data classes need no `@SerialName` unless they rename.
