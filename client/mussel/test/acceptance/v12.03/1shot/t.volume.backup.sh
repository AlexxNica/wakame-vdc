#!/bin/bash
#
# requires:
#  bash
#  cat, ssh-keygen, ping, rm
#

## include files

. ${BASH_SOURCE[0]%/*}/helper_shunit2.sh
. ${BASH_SOURCE[0]%/*}/helper_instance.sh

## variables

description=${description:-}
display_name=${display_name:-}
is_cacheable=${is_cacheable:-}
is_public=${is_public:-}

## hook functions

function after_create_instance() {
  run_cmd instance poweroff ${instance_uuid} >/dev/null
  retry_until "document_pair? instance ${instance_uuid} state halted"
}

last_result_path=""

function setUp() {
  last_result_path=$(mktemp --tmpdir=${SHUNIT_TMPDIR})
}

### step

# GET $base_uri/instances/i-xxxxx/volumes
function test_get_volume() {
  run_cmd instance show_volumes "${instance_uuid}" > /dev/null
  assertEquals $? 0
}

# PUT $base_uri/instances/i-xxxxx/volumes/vol-xxxxxx/backup
#function test_put_/instances/i-xxxxx/volumes/vol-xxxxxx/backup() {
function test_volume_backup_under_instances() {
  run_cmd instance show_volumes "${instance_uuid}"| ydump > $last_result_path
  assertEquals $? 0
  
  local boot_volume_uuid=$(yfind '/0/:uuid:' < $last_result_path)
  test -n "$boot_volume_uuid"
  assertEquals $? 0

  run_cmd instance backup_volume ${instance_uuid} $boot_volume_uuid | ydump > $last_result_path
  assertEquals $? 0


  local backup_obj_uuid=$(yfind '/:backup_object_id:' < $last_result_path)
  test -n "$backup_obj_uuid"
  assertEquals $? 0

  retry_until "document_pair? backup_object ${backup_obj_uuid} state available"
}

# PUT $base_uri/volumes/vol-xxxxxx/backup
function test_volume_backup_under_volumes() {
  run_cmd instance show_volumes "${instance_uuid}" | ydump > $last_result_path
  assertEquals $? 0

  local boot_volume_uuid=$(yfind '/0/:uuid:' < $last_result_path)
  test -n "$boot_volume_uuid"
  assertEquals $? 0

  run_cmd volume backup $boot_volume_uuid | ydump > $last_result_path
  assertEquals $? 0

  local backup_obj_uuid=$(yfind '/:backup_object_id:' < $last_result_path)
  test -n "$backup_obj_uuid"
  assertEquals $? 0

  retry_until "document_pair? backup_object ${backup_obj_uuid} state available"
}

## shunit2

. ${shunit2_file}