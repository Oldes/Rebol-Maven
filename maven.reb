Rebol [
	Title: "Maven"
	Name:   maven
	Type:   module
	Date:   11-Mar-2024 
	Version: 1.0.0
	Author:  @Oldes
	Purpose: {To resolve Java dependencies from Maven repositories.}
	Needs: [xml]
	Usage: [
		get-dependencies [
			"androidx.activity:activity:1.8.2"
			"com.google.android.play:asset-delivery:2.2.1"
			"com.google.android.gms:play-services-games:23.1.0"
			"com.google.android.gms:play-services-auth:21.0.0"
		]
	]
	Note: {
	This script was inspired by this info: https://stackoverflow.com/a/47751231/494472
	POM file specification:  https://maven.apache.org/pom.html
	Group index URL example: https://dl.google.com/dl/android/maven2/androidx/core/group-index.xml
	}
]

repositories: [
	https://repo.maven.apache.org/maven2/
	https://dl.google.com/dl/android/maven2/
	https://maven.google.com/
	https://repo1.maven.org/maven2/
]

cache-dir: rejoin [system/options/data %maven/]
que: make block! 10      ;; main que for requested artifacts
resources: make map! 64  ;; map of collected dependency IDs and its POMs
exclusions: copy []      ;; dependecy exclusions

;-- POM file loading --------------------------------------------------------
xml-to-blk: function[xml][
	map: make block! 8
	forall xml [
		unless block? tag: first xml [continue]
		key: to set-word! tag/1
		val: tag/3
		unless val [continue]
		val: either string? tmp: first val [tmp][xml-to-blk val]
		append/only append map key val
	]
	new-line/skip map true 2
	map
]
decode-pom: function [pom [binary! file! url!]][
	unless binary? pom [pom: read pom]
	;; decodes POM file as XML (ignoring formating)
	xml: codecs/xml/decode/trim pom
	if "project" <> xml/3/1/1 [return none]
	;; convert result to a simplified representation
	to map! xml-to-blk xml/3/1/3
]
load-pom: function[pom-file][
	local: cache-dir/:pom-file
	unless exists? local [
		;; try to download the POM file from any of known repositories
		foreach url repositories [
			if binary? try [
				bin: read/binary url/:pom-file
			][	break ]
		]
		unless bin [
			print [as-purple "*** POM file not found:" as-red pom-file]
			cause-error 'access 'read-error reduce [pom-file 'load-pom]
		]
		try/with [
			make-dir/deep first split-path local
			write local bin
		][
			print [as-purple "*** Failed to write POM file to cache:" as-red pom-file]
			cause-error 'access 'write-error reduce [pom-file 'load-pom]
		]
		local: :bin
	]
	decode-pom local 
]

;-- Semantic versions -------------------------------------------------------

numeric: system/catalog/bitsets/numeric
exceptions: #[
    ""          <release>
    "release"   <release>
    "ga"        <release>
    "sp"        <sp>
    "cr"        "rc"
    "alpha"     "a"
    "beta"      "b"
    "milestone" "m"
]
num-padding: 4           ;; used to pad Maven's version numbers (before string qualifier part)
split-cache: make map! 8 ;; used to cache parsed and padded versions

split-version: function [
    "Split semantic version into block with numbers and a qualifier with applied Maven exceptions"
    version [string!]
][
    if tmp: split-cache/:version [return tmp]
    tmp: make block! 8
    parse version [
        some [
            copy val: some numeric (append tmp to integer! val) opt #"."
        ]
        opt [#"-"]
        copy val: to end (
            if num-padding > len: length? tmp [append/dup tmp 0 num-padding - len]
            append tmp any [exceptions/:val val]
        )
    ]
    split-cache/:version: tmp
]
compare-versions: function[a [string!] b [string!]][
    a: split-version a
    b: split-version b
    case [
        a = b [return 0]
        a > b [return 1]
    ]
    -1
]
sort-versions: function [
    "Sorts block of semantic versioning strings with applied Maven exceptions"
    ;; https://maven.apache.org/pom.html#version-order-specification
    versions [block!] "Block of version strings"
][
    sort/compare versions :compare-versions
]

;-- Artifacts resolver ------------------------------------------------------

request-artifact: function [
	"Compare if artifacts does not exists or needs higher version; load its POM file with other dependencies."
	spec [block! string!] {[groupId artifactId version] or "groupId:artifactId:version"}
][
	if string? spec [
		;; string as used in Gradle, like: "androidx.appcompat:appcompat:1.6.1"
		unless all [
			block? spec: split spec #":"
			3 = length? spec
		][
			print [as-purple "*** Invalid spec:" as-red spec]
			halt
		]
	]
	set [groupId: artifactId: version:] spec
	;print ["Request-artifact:" groupId artifactId version]

	groupId: as file! replace/all groupId #"." #"/"
	id: groupId/:artifactId
	if exists-artifact? id version [ exit ]

	pom-file: ajoin [id #"/" version #"/" artifactId #"-" version %.pom]
	pom: load-pom pom-file
	unless map? :pom [
		print [as-purple "*** POM file not decoded:" as-red pom-file]
		cause-error 'access 'no-codec reduce [pom-file 'decode-pom]
	]
	resources/:id: pom
]
exists-artifact?: function [
	"Check if artifact already exists with hight enough version"
	artifact    [file!]   "dependency artifact"
	version     [string!] "requested version"
][
	prin ["Artifact:" as-green artifact "version:" as-green version]
	either pom: resources/:artifact [
		; there is already such an artifact
		either 0 <= compare-versions pom/version version [
			; and its version is high enough
			print [" exists:" as-green pom/version] true
		][	print [as-yellow " [UPDATE]" "from:" as-green pom/version] false]
	][ print as-yellow " [NEW]" false]
]
download-artifact: function[file [file!]][
	foreach url repositories [
		print ["Trying to download" as-yellow url/:file]
		if binary? bin: attempt [read url/:file][
			return bin
		]
	]
]

get-dependencies: function/extern [
	"Recursively collect all dependency requirements."
	names [block! string!] "Dependency names"
	/no-download
][
	append clear que to block! names
	either map? resources [clear resources][resources: make map! 64]
	
	while [not empty? que][
		while [not empty? que][
			request-artifact take que
		]
		foreach [id pom] resources [
			unless pom/dependencies [continue]
			foreach [k dep] pom/dependencies [
				if k <> 'dependency [continue]
				;?? dep
				if find ["compile" "runtime"] dep/scope [
					unless empty? exclusions [
						;?? exclusions ask ""
						if catch [
							foreach ex exclusions [
								if all [
									tmp: find/any/tail dep/groupId ex/1
									tail? tmp
									tmp: find/any/tail dep/artifactId ex/2
									tail? tmp
								][ throw true ]
							]
						][
							print as-red reform ["Excluded:" dep/groupId dep/artifactId]
							continue
						]
					]
					if dep/exclusions [
						;?? dep/exclusions ask ""
						foreach [k ex] dep/exclusions [
							if k = 'exclusion [
								tmp: reduce [ex/groupId ex/artifactId]
								unless find/only exclusions tmp [append/only exclusions tmp]
							]
						]
					]
					;@@ TODO: Version requirements syntax is much more complex!!
					;- https://maven.apache.org/pom.html#dependency-version-requirement-specification 
					parse version: dep/version [#"[" copy version to #"]"]
					repend/only que [dep/groupId dep/artifactId version]
				]
			]
			pom/dependencies: none ;; not needed anymore
		]
	]
	;foreach [id pom] resources [ print [id pom/version] ]
	if no-download [return resources]

	print-horizontal-line
	print [as-blue "Downloading resources to cache direcory:" as-yellow cache-dir]

	foreach [id pom] resources [
		type: any [pom/packaging "jar"]
		file:  rejoin [id #"/" pom/version #"/" pom/artifactId #"-" pom/version #"." type]
		local: cache-dir/:file
		unless exists? local [
			unless bin: download-artifact file [
				print [as-purple "*** Artifact file not found:" as-red file]
				cause-error 'access 'read-error reduce [file 'download-artifact]
			]
			try/with [
				write local bin
			][
				print ["*** Failed to write artifact to cache:" as-red local]
				cause-error 'access 'write-error reduce [file 'download-artifact]
			]
		]
	]
	resources
][	resources]
