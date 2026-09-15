package dev.dcltdw.personalization

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
class PersonalizationApplicationTest {
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
        assertThat(response.body()).contains("hello from personalization")
    }

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
}
