#!/bin/sh
# usage: deploy.sh <work dir name> : copies the built FactoryProbe.exe to the Sandbox-visible hosts folder (copy, never delete)
set -eu
ssh win "Copy-Item D:\\Claude\\swiftright\\.work\\$1\\scratch-host\\x86_64-unknown-windows-msvc\\${2:-release}\\FactoryProbe.exe D:\\Claude\\swiftright\\.factory-work\\hosts\\pulse-hub-20261015\\package\\scratch\\x86_64-unknown-windows-msvc\\release\\FactoryProbe.exe -Force"
