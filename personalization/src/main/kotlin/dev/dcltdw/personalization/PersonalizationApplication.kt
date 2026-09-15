package dev.dcltdw.personalization

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class PersonalizationApplication

@Suppress("SpreadOperator")
fun main(args: Array<String>) {
    runApplication<PersonalizationApplication>(*args)
}
