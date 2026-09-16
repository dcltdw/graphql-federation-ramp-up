plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

rootProject.name = "graphql-federation-ramp-up"

include("catalog", "personalization")
