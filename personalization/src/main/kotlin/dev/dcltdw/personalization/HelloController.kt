package dev.dcltdw.personalization

import org.springframework.graphql.data.method.annotation.QueryMapping
import org.springframework.stereotype.Controller

/** Placeholder resolver for the placeholder schema. Deleted in issue #9. */
@Controller
class HelloController {
    @QueryMapping
    @Suppress("FunctionOnlyReturningConstant")
    fun hello(): String = "hello from personalization"
}
