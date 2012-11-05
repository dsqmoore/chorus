#!/bin/bash

export RAILS_ENV=test
GPDB_HOST=chorus-gpdb42
HADOOP_HOST=chorus-gphd02

. script/ci/setup.sh

set -e

targets=${@}
possible_targets="jasmine ruby legacy_migrations api_docs"

for target in $possible_targets; do
    set run_${target}=true
done

if [[ -nz "$targets" ]]; then
    for target in $possible_targets; do
        declare run_${target}=false
    done
    for target in "$targets"; do
        for possible_target in $possible_targets; do
           if [[ "$target" == "$possible_target" ]] ; then
                declare run_${target}=true
           fi
        done
    done
fi

if $run_ruby; then
   b/rake assets:precompile --trace

    echo "starting gpfdist (Linux RHEL5 only)"
    export LD_LIBRARY_PATH=vendor/gpfdist-rhel5/lib:${LD_LIBRARY_PATH}
    ./vendor/gpfdist-rhel5/bin/gpfdist -p 8000 -d /tmp &
    ./vendor/gpfdist-rhel5/bin/gpfdist -p 8001 -d /tmp &
fi

# start jasmine
if $run_jasmine ; then
    b/rake jasmine > $WORKSPACE/jasmine.log 2>&1 &
    jasmine_pid=$!
    echo "Jasmine process id is : $jasmine_pid"
    echo $jasmine_pid > tmp/pids/jasmine-$RAILS_ENV.pid

    sleep 30
fi

set +e

unset RAILS_ENV

if $run_ruby ; then
    echo "Running unit tests"
    mv .rspec-ci .rspec
    GPDB_HOST=$GPDB_HOST HADOOP_HOST=$HADOOP_HOST b/rake -f `bundle show ci_reporter`/stub.rake ci:setup:rspec spec 2>&1
    RUBY_TESTS_RESULT=$?
else
    RUBY_TESTS_RESULT=0
fi

if $run_ruby ; then
    echo "Running unit tests"
    mv .rspec-ci .rspec
    GPDB_HOST=$GPDB_HOST HADOOP_HOST=$HADOOP_HOST b/rake -f `bundle show ci_reporter`/stub.rake ci:setup:rspec spec 2>&1
    RUBY_TESTS_RESULT=$?
else
    RUBY_TESTS_RESULT=0
fi

if $run_jasmine ; then
    echo "Running javascript tests"
    CI_REPORTS=spec/javascripts/reports b/rake -f `bundle show ci_reporter`/stub.rake ci:setup:rspec phantom 2>&1
    JS_TESTS_RESULT=$?

    echo "Cleaning up jasmine process $jasmine_pid"
    kill -s SIGTERM $jasmine_pid
else
    JS_TESTS_RESULT=0
fi

if $run_ruby ; then
    echo "Cleaning up gpfdist"
    killall gpfdist
fi

if $run_legacy_migrations; then
    echo "Running legacy migration tests"
    b/rake db:test:prepare
    CI_REPORTS=spec/legacy_migration/reports b/rake -f `bundle show ci_reporter`/stub.rake ci:setup:rspec spec:legacy_migration
    LEGACY_MIGRATION_TESTS_RESULT=$?
else
    LEGACY_MIGRATION_TESTS_RESULT=0
end

if $run_api_docs ; then
    echo "Running API docs check"
    b/rake api_docs:check
    API_DOCS_CHECK_RESULT=$?
else
    API_DOCS_CHECK_RESULT=0
fi

if $run_ruby ; then
  echo "RSpec exit code: $RUBY_TESTS_RESULT"
end

if $run_jasmine ; then
    echo "Jasmine exit code: $JS_TESTS_RESULT"
fi

if $run_legacy_migrations ; then
  echo "Legacy migration exit code: $LEGACY_MIGRATION_TESTS_RESULT"
end

if $run_api_docs ; then
  echo "API docs check exit code: $API_DOCS_CHECK_RESULT"
end

SUCCESS=`expr $RUBY_TESTS_RESULT + $JS_TESTS_RESULT + $LEGACY_MIGRATION_TESTS_RESULT + $API_DOCS_CHECK_RESULT`
exit $SUCCESS
