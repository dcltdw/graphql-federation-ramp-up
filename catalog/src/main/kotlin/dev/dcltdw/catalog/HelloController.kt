package dev.dcltdw.catalog

import org.springframework.graphql.data.method.annotation.QueryMapping
import org.springframework.stereotype.Controller

/** Placeholder resolver for the placeholder schema. Deleted in issue #7. */
@Controller
class HelloController {
    @QueryMapping
    @Suppress("FunctionOnlyReturningConstant")
    fun hello(): String = "hello from catalog"
}
