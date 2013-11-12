#!/bin/bash

export RAILS_ENV=packaging

if [ "$HOSTNAME" = chorus-ci ]; then
  export GPDB_HOST=chorus-gpdb-ci
  export ORACLE_HOST=chorus-oracle
  export HAWQ_HOST=chorus-gphd20-2
fi

. script/ci/setup.sh

echo "checking for an alpine package"
if [[ "${ALPINE_PACKAGE}" ]]; then
    echo "fetching alpine package from ${ALPINE_PACKAGE}"
    (mkdir -p vendor/alpine; cd vendor/alpine; wget --quiet "${ALPINE_PACKAGE}")
    echo "1234version" > vendor/alpine/version_build
    chmod +x vendor/alpine/*.sh
fi

rm -fr .bundle
bundle exec rake package:installer --trace
