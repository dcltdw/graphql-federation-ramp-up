package dev.dcltdw.catalog

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.graphql.test.autoconfigure.tester.AutoConfigureHttpGraphQlTester
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
