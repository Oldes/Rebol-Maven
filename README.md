[![Rebol-Maven CI](https://github.com/Oldes/Rebol-Maven/actions/workflows/main.yml/badge.svg)](https://github.com/Oldes/Rebol-Maven/actions/workflows/main.yml)
# Rebol/Maven
Rebol script resolving (and downloading) Java dependencies from Maven repositories

## Usage
```rebol
maven: import %maven.reb
maven/get-dependencies [
	"androidx.activity:activity:1.8.2"
	"com.google.android.play:asset-delivery:2.2.1"
	"com.google.android.gms:play-services-games:23.1.0"
	"com.google.android.gms:play-services-auth:21.0.0"
]
```
