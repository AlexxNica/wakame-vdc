# -*-Shell-script-*-
#
# requires:
#   bash
#

## system variables

readonly shunit2_file=${BASH_SOURCE[0]%/*}/../../shunit2

## include files

. ${BASH_SOURCE[0]%/*}/../../../functions

## group variables

api_version=11.12
host=localhost
port=9001
base_uri=http://${host}:${port}/api/${api_version}
account_id=a-shpoolxx
format=yml
http_header=X_VDC_ACCOUNT_UUID:${account_id}

dry_run=yes

## group functions
