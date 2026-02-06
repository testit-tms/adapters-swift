#!/bin/bash

VERSION=0.5.0
API_CLIENT_VERSION=0.5.0

# Update testit-api-client version in Package.swift using sed
sed -i "s/\.exact(\"[^\"]*\")/.exact(\"$API_CLIENT_VERSION\")/g" Package.swift
