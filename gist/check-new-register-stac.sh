#!/bin/bash
# This script is meant for being called regularly by cron

mkdir -p /var/tmp/sentinel/

SCRIPTNAME="`basename -s .sh $0`"
LOCK="/var/tmp/sentinel/$SCRIPTNAME.lock"
LIST="/var/tmp/sentinel/gen_new_list_processed.txt"
ERR_FILE_PATTERN="/var/tmp/sentinel/register-stac-error-"

if [ -e $LOCK ]; then
	1>&2 printf "Exiting: Lock file exists: $LOCK\n\"$SCRIPTNAME\" is only meant to be run once at a time.\n\n"
	exit 1
else
	touch $LOCK
	trap "rm \"$LOCK\"" EXIT
fi

NEWEST_ERR_FILE=$(ls -1t ${ERR_FILE_PATTERN}* 2>/dev/null | head -n1)

echo "Fetching products"
python3 gen_new_list.py  # todo - check paths
if [ $? -ne 0 ]; then
  echo "Failed to fetch products."
  exit 1
fi
echo "Fetched $(wc -l < $LIST) products"

cat "$LIST" | while read id; do
	python3 register_stac.py -p -i $id  # todo - check paths
done

if [ -z "$NEWEST_ERR_FILE" ]; then
  echo "No previous error file found."
else
  echo "Previously created error file contains $(wc -l < $NEWEST_ERR_FILE) products"

  # for each entry ending with http error code which is not 409 (already exists), retry push
  while IFS=, read -r _ id error_info;
  do
    error_code=${error_info%%:*}
    # check if the error code is >= 400 but not 409
    if [[ "$error_code" -ge 400 && "$error_code" -ne 409 ]]; then
      python3 register_stac.py -p -i "$id"  # todo - check paths
    fi
  done < "$NEWEST_ERR_FILE"
fi
