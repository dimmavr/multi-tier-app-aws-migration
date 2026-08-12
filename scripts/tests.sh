#!/bin/bash
 
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  description=$1
  expected=$2
  shift 2
  
     # Εκτέλεση της εντολής χωρίς output
  "$@" >/dev/null 2>&1
  rc=$?
  if { [ $rc -eq 0 ] && [ "$expected" = "ok" ]; } || { [ $rc -ne 0 ] && [ "$expected" = "blocked" ]; }; then
     echo "PASS $description"
     PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
      echo "FAIL ${description}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

}

run_test "ops -> gw (ping 10.0.30.1)" ok ping -c 2 -w 2 10.0.30.1
run_test "ping 8.8.8.8" ok ping -c 2 -w 2 8.8.8.8
run_test "ping google.com" ok ping -c 2 -w 2 google.com
run_test "TCP db:5432" ok nc -z -w 2 10.0.20.10 5432
run_test "TCP db:22" ok nc -z -w 2 10.0.20.10 22
run_test "TCP app:22" ok nc -z -w 2 10.0.10.10 22
run_test "TCP gw:22 (10.0.30.1)" ok nc -z -w 2 10.0.30.1 22
run_test "TCP app:80" blocked nc -z -w 2 10.0.10.10 80 
run_test "db -/-> app:22 (deny)" blocked ssh admin@10.0.20.10 "nc -z -w 2 10.0.10.10 22"
run_test "app -/-> ops:22 (deny)" blocked ssh admin@10.0.10.10 "nc -z -w 2 10.0.30.10 22"


echo "$PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -eq 0 ]; then
    exit 0
else
    exit 1
fi
