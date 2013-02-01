#!/bin/bash
#
# requires:
#   bash
#

## include files

. $(cd ${BASH_SOURCE[0]%/*} && pwd)/helper_shunit2.sh

## variables

## functions

function setUp() {
  :
}

function test_cmd_index() {
  local namespace=instance
  local cmd=index
  local args="-X GET ${base_uri}/${namespace}s.${format}?${xquery}"

  assertEquals "$(cmd_index ${namespace} ${cmd})" "curl ${args}"
}

## shunit2

. ${shunit2_file}
