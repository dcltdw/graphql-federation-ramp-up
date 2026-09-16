dependencies {
    implementation(libs.spring.boot.starter.web)
    implementation(libs.spring.boot.starter.graphql)
    implementation(libs.jackson.module.kotlin)
    implementation(libs.kotlin.reflect)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.federation.jvm)

    testImplementation(libs.spring.boot.starter.test)
}
