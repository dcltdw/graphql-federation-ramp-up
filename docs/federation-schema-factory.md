# How a Spring GraphQL server becomes a federation subgraph

Read this carefully before you start #7. It explains the machinery that
`FederationConfig.kt` switches on in both modules. You will write the schemas
and resolvers yourself (#7–#10). This page is here so that you understand what
the gateway is going to ask your code for, and why.

Everything below was checked against Spring for GraphQL 2.0.5 and
federation-graphql-java-support 6.2.1, both from this build, or observed by
running the apps. Where the placeholder schema and the real schema behave
differently, both are shown.

## 1. What a subgraph is

A subgraph is an ordinary GraphQL server. It has a schema, resolvers, and a
`/graphql` endpoint, and you can query it directly with curl or GraphiQL. There
is nothing special about it except **two extra root fields on `Query`** that
the gateway relies on and a normal client never uses:

- `_service` lets the gateway ask "what is your schema?"
- `_entities` lets the gateway say "here are some keys; give me the fields you
  own for them."

Neither field appears in your `.graphqls` file. They get added when the schema
is built. Catalog and personalization never call each other. The gateway talks
to each one separately, and these two fields are the whole protocol between
the gateway and a subgraph.

## 2. `_service { sdl }`: "what is your schema?"

`_service { sdl }` returns this subgraph's schema as a string, **with the
federation directives still in it** (`@link`, `@key`, and so on). Standard
introspection (`__schema`) cannot do this job, because introspection does not
carry directive usages. Composition needs them: it has to know that `Product`
is an entity keyed by `id`. So `hive dev` (#5) and the Hive registry read
`_service { sdl }`, not introspection.

Here is the real response from catalog right now, still on the placeholder
schema:

```console
$ curl -s -X POST localhost:8081/graphql \
    -H 'Content-Type: application/json' \
    -d '{"query":"{ _service { sdl } }"}'
{"data":{"_service":{"sdl":"schema {\n  query: Query\n}\n\n\"\"\"\n PLACEHOLDER. Replaced by the real catalog schema in issue #7.\n It exists so that composition (issue #5) succeeds before any real schema does.\n\"\"\"\ntype Query {\n  hello: String\n}"}}}
```

With the `sdl` string unescaped:

```graphql
schema {
  query: Query
}

"""
 PLACEHOLDER. Replaced by the real catalog schema in issue #7.
 It exists so that composition (issue #5) succeeds before any real schema does.
"""
type Query {
  hello: String
}
```

Three things to notice:

- **There are no federation directives, because the placeholder has none.**
  Once a schema has an `extend schema @link(url: ".../federation/v2.x", ...)`
  line, the SDL is printed differently: the output also contains the `@link`
  on `schema`, definitions for the federation directives, `_service` and
  `_entities` on `Query`, and the `_Entity` union. That was observed on a
  throwaway schema with one `@key` type, which was deleted afterwards.
- **The `#` comments at the top of the file came back as a `"""` description.**
  What you get back is a printed schema, not the file.
- **`_service` is not in this SDL**, even though it is now on the live `Query`.
  On the placeholder, `Query` has exactly two fields when you introspect it:
  `hello` and `_service`.

## 3. `_entities(representations: [...])`: "resolve these keys"

This is the field everything else rests on.

A **representation** is a small JSON object that identifies one entity. It has
`__typename` plus the key fields named in `@key`. For `Product @key(fields: "id")`
that is:

```json
{ "__typename": "Product", "id": "CAT-TREE-DLX" }
```

Once #9 and #10 land, the gateway answers a client query for products with
their CTAs in two steps. First it asks catalog for the products, and gets back
their ids among other fields. Then it sends personalization **one** request
with a representation for every product, selecting only the field
personalization owns. The shape of that second request is:

```graphql
query ($representations: [_Any!]!) {
  _entities(representations: $representations) {
    ... on Product {
      cta(segment: VIP) {
        variantKey
        headline
      }
    }
  }
}
```

```json
{
  "representations": [
    { "__typename": "Product", "id": "CAT-TREE-DLX" },
    { "__typename": "Product", "id": "LASER-POINTER" }
  ]
}
```

Read it slowly:

- **`representations` is typed `[_Any!]!`.** `_Any` is a scalar that accepts
  any JSON object, so the subgraph's schema does not need an input type for
  every entity.
- **`_entities` returns `[_Entity]!`.** `_Entity` is a union of every entity
  type in this subgraph, which is why the selection needs `... on Product`.
- **The answer is a list in the same order as the representations**, one
  element per representation. An element can be `null`. On a throwaway schema,
  a key the resolver returned `null` for came back as `null` in that position,
  and the response had no `errors` entry.
- **What the gateway puts in `...on Product { }`** comes from the client's
  query: only the fields this subgraph owns. Personalization is never asked for
  `name` or `priceMinor`.

You will see these requests for real in #11. Gateways usually pass the
representations as a variable, as shown above, but the query text is theirs
and may be formatted differently. The shape is the part to learn. Both the
variable form and an inline list literal were tried against Spring on the
throwaway schema, and both work.

**What happens today, on the placeholder schema.** `_entities` does not exist
yet. Sending the query above to catalog returns only validation errors:

```json
{"errors":[
  {"message":"Validation error (UnknownType) : Unknown type '_Any'", ...},
  {"message":"Validation error (FieldUndefined@[_entities]) : Field '_entities' in type 'Query' is undefined", ...}
]}
```

This is expected, not broken. `_entities`, `_Any` and `_Entity` are only added
when the schema contains at least one entity, meaning a type with `@key`. The
placeholder has none. Section 4 covers this in more detail.

## 4. What `FederationSchemaFactory` does

Here are the five lines in `FederationConfig.kt` that matter:

```kotlin
    @Bean
    fun federationSchemaFactory(): FederationSchemaFactory = FederationSchemaFactory()

    @Bean
    fun federationCustomizer(factory: FederationSchemaFactory): GraphQlSourceBuilderCustomizer =
        GraphQlSourceBuilderCustomizer { builder -> builder.schemaFactory(factory::createGraphQLSchema) }
```

To see what they change, start with how Spring builds a schema without them.

**Without them.** Spring Boot's GraphQL auto-configuration finds every
`graphql/**/*.graphqls` file and parses each one into a type registry.
**Parsing is Spring's job, not the factory's.** It merges the files and builds
a runtime wiring from your `@QueryMapping` and `@SchemaMapping` controller
methods. Then it hands the registry and the wiring to graphql-java to produce
the executable schema.

**With them.** That last step is replaced. The first bean creates the factory
as a Spring bean. This matters: at startup the factory scans your controllers
for `@EntityMapping` methods, and if it is not a bean, it throws "Not
initialized" when used. The second bean is a Boot customizer. It tells the
builder to call `factory.createGraphQLSchema(registry, wiring)` instead of
calling graphql-java directly. Boot applies every `GraphQlSourceBuilderCustomizer`
bean it finds. Boot 4.1.1 has no federation auto-configuration of its own,
which is why these lines have to exist.

Inside `createGraphQLSchema`, the factory does four things.

1. **Checks that every entity has a resolver.** For every type with a
   resolvable `@key` (the default), there must be a matching `@EntityMapping`
   method. If one is missing, the app **fails to start**. It does not wait for
   the first request. A throwaway schema with a `@key` type and no
   `@EntityMapping` stopped at boot with:

   ```text
   java.lang.IllegalStateException: Unmapped entity types: 'Product'
   ```

   The type name comes from the method name, capitalised: a method called
   `product` maps `Product`. You can override it with
   `@EntityMapping(name = "...")`.

2. **Reads the federation directives.** It hands the registry to federation-jvm
   (`Federation.transform`). That reads the `@link(url: ".../federation/v2.x",
   import: [...])` on your schema, throws if the version or an import is
   unsupported, and adds the definitions for the federation directives. Your
   SDL can then use `@key` without declaring it, and graphql-java accepts it.
   This checks that the directives are *known and well-formed*. It does **not**
   check whether your schema will compose with the other subgraph. That is
   composition's job (#5).

3. **Adds the federation fields.** `_service { sdl }` is always added, along
   with `_Service`. `_entities(representations: [_Any!]!): [_Entity]!`, `_Any`
   and the `_Entity` union are added **only if at least one entity type
   exists**. That is why today's placeholder has `_service` but no `_entities`.

4. **Wires `_entities` to your `@EntityMapping` methods.** When an `_entities`
   request arrives, the factory's data fetcher groups the representations by
   `__typename` and calls the `@EntityMapping` method registered for that type:
   - **If the method returns a list**, it is called **once** with every
     representation of that type.
   - **Otherwise** it is called once per representation.

   To decide which `_Entity` member each returned object is, Spring's default
   type resolver looks at the object's class name. A Kotlin class named
   `Product` resolves to the GraphQL type `Product`.

## 5. What you write against it

In #10 you write one method on a personalization controller with exactly this
signature:

```kotlin
@EntityMapping
fun product(@Argument idList: List<String>): List<Product?>
```

Here is what each part connects to:

- **`@EntityMapping` on a method named `product`** registers it for the
  `Product` entity. That satisfies the startup check in §4 step 1.
- **The parameter name `idList` is not arbitrary.** For a list parameter,
  Spring strips a trailing `List` from the name and reads that key from each
  representation. So `idList` means "the `id` of every representation", in
  order. On the throwaway schema, three representations arrived as one call
  with `idList=[CAT-TREE-DLX, UNKNOWN, LASER-POINTER]`.
- **The return type `List<Product?>`** is one element per id, in the same
  order. It is nullable because a key you cannot resolve is a `null` in that
  slot, not an exception.

**Why a *list*.** The gateway does not send one `_entities` request per
product. It collects every `Product` key it needs from that step of the plan
and sends them all in one request, as in §3. With the list form, Spring passes
all those keys to your method in **one call**. You then resolve twelve products
with one lookup instead of twelve calls to the same method. The single-key
form, `fun product(@Argument id: String): Product?`, also works, but Spring
then calls it once per key, even though the keys all arrived together.
Declaring the list form keeps the batch the gateway already built.

## 6. What it does not do

`FederationSchemaFactory` only makes this server *answerable* by a gateway. It
does not:

- **Plan queries.** It does not know that a client query spans two services.
  The gateway splits the query, decides that personalization needs product ids
  from catalog, and orders the calls.
- **Compose schemas.** It does not know what the other subgraph's schema looks
  like, or whether the two conflict. Composition (`hive dev` in #5, the
  registry later) reads both `_service { sdl }` outputs and does that.
- **Talk to the other subgraph.** Nothing in it makes an outbound call.
  Personalization never learns a product's name. It gets keys in `_entities`
  and returns the fields it owns. Merging those back into the client's response
  is the gateway's job.

If something federation-shaped goes wrong across both services, look at the
gateway or at composition. If a single subgraph misbehaves, look at its
`_service` output or at its `_entities` answers, which you can test on their
own with curl.

## Check yourself

Answer these from memory before starting #7:

1. What does the gateway send to `_entities`, and what does it expect back,
   including order and what a missing key looks like?
2. Why does the gateway read `_service { sdl }` instead of running an
   introspection query?
3. Today, catalog has `_service` but no `_entities`. Why, and what change to a
   schema makes `_entities` appear?
4. If personalization's schema has a `@key` type and no `@EntityMapping` for
   it, when do you find out, and what does the failure say?
5. Why does the reference resolver take `idList: List<String>` rather than
   `id: String`, and how does Spring know which representation field to put in
   `idList`?
