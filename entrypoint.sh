#!/usr/bin/env sh

apk add go

go mod init codeminders.com/drone-helper
go mod tidy
go run ./drone-helper.go "$@"
