#!/bin/bash

set +e
TFPLAN_DRIFT_CHECK="tfplan-drift-check"

terraform plan \
    -var-file="$VAR_FILE" \
    -out="$TFPLAN_DRIFT_CHECK" \
    -detailed-exitcode \
    -no-color \
    -input=false

TF_EXITCODE=$?
set -e

if [[ $TF_EXITCODE -eq 0 ]]; then
    echo "No drift detected - infrastructure matches expected state"
elif [[ $TF_EXITCODE -eq 2 ]]; then
    echo "Warning: State has drifted - comparing plans..."

    terraform show -no-color "$TFPLAN_DRIFT_CHECK" > drift-check.txt
    terraform show -no-color "$TFPLAN_BINARY" > original-plan.txt

    sed -n '/Terraform will perform the following actions:/,$p' original-plan.txt > original-changes.txt
    sed -n '/Terraform will perform the following actions:/,$p' drift-check.txt > drift-changes.txt

    if diff -u original-changes.txt drift-changes.txt > plan-diff.txt; then
        echo "Plans are identical"
    else
        echo "Warning: Plans differ - showing differences..."
        echo ""
        echo "=== Plan Differences ==="
        cat plan-diff.txt

        exit 1
    fi
else
    echo "Error: Drift check failed"
    exit 1
fi