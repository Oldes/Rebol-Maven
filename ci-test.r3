Rebol [
	Title: "Maven CI test"
]

maven: import %maven.reb

dependencies: maven/get-dependencies "androidx.activity:activity:1.8.2"

print-horizontal-line
print as-blue "Collected dependencies:"

total: 0
foreach [id pom] dependencies [
	local: pom/local-file
	bytes: size? maven/cache-dir/:local
	print [as-green id as-blue pom/version "bytes:" as-red bytes]
	total: total + bytes
]

print [as-blue "Total" as-yellow total as-blue "bytes!"] 