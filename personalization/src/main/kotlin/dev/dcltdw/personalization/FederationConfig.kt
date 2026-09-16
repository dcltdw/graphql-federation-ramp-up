package dev.dcltdw.personalization

import org.springframework.boot.graphql.autoconfigure.GraphQlSourceBuilderCustomizer
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.graphql.data.federation.FederationSchemaFactory

/**
 * Turns this ordinary GraphQL server into a federation subgraph.
 *
 * Two things get added to the schema that the SDL file never mentions:
 *  - `_service { sdl }` — how composition (`hive dev`, later the registry)
 *    learns this subgraph's schema, with the federation directives intact.
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
