package dev.dcltdw.catalog

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class CatalogApplication

@Suppress("SpreadOperator")
fun main(args: Array<String>) {
    runApplication<CatalogApplication>(*args)
}
