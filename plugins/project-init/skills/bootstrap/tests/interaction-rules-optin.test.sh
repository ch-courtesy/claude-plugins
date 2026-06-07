#!/usr/bin/env bash
exec bash "$(cd "$(dirname "$0")" && pwd)/../../../shared/bootstrap/tests/bootstrap-contract.test.sh"
