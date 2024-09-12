#!/bin/bash
# Constants
REMOTE="origin"
RESTRICTED_BRANCHES=("develop")
REVIEWERS=(StephenMilone currentraghavkishan lewis-current kevin-current AVSEQ00 ramit-current)

# Variables
CreatingPR=true
BaseBranch="develop"
RunLintCheck=true
SquashCommits=true
KeepCurrentBranchAfterPR=false

# Help
Help()
{
    echo "
This script will automate most of the PR create/update process for an Android project
Including

- running lint check
- squashing commits against BaseBranch var when creating a PR or against the remote branch when updating it
- commit changes. Will ask for commit message
- push changes to remote
- create PR on GitHub. GitHub CLI should be installed and authenticated
- checkout BaseBranch and delete branch from which PR was created

Override for the defaults can be provided via a pr.properties txt file in the same directory

Example pr.properties file

base_branch=feature-test
squash_commits=false
lint_check=false
keep_current_branch_after_pr=true

Or via input flags to the script

l    Skip lint checks
s    Skip squashing commits
k    Keep the current branch and don't checkout BaseBranch after PR
b    Set the BaseBranch var to squash commits and create PR against
u    Update the existing PR. Commits are squashed against current branch's remote branch

Branch for an existing PR can be checked out by using the input flag p

To use
- install GitHub cli
- run 'gh auth login'
- select github.com, select ssh, skip selecting ssh key, login with browser
- [Do If Getting Authentication Error] create personal access token to login
- [Do If Still Getting Authentication Error] create ssh key for GitHub cli, run gh auth login and select the created key this time

Examples
./pr.sh
Create PR

./pr.sh -u
Update PR by pushing changes to the PR branch

./pr.sh -s
Create PR but skip squashing commits

./pr.sh -us
Update PR but skip squashing commits

./pr.sh -b feature-test
Create PR against feature-test branch

./pr.sh -k
Create PR and keep the PR branch

./pr.sh -p 999
Checkout the remote branch associated with the PR number 999"
}

# LintCheck
LintCheck()
{
    echo "LintCheck Start"
    if ! ./gradlew detektAutoCorrect;
    then
        exit $?
    fi
    echo "LintCheck End"
}

# SquashCommits
SquashCommits()
{
    current=$(git branch --show-current)
    if [ "$#" -ne 1 ]
    then
        against="$REMOTE/$current"
    else
        against=$BaseBranch
    fi

    echo "SquashCommits Start against $against    
    Squashing all WIP commits in $current"
    if ! git reset "$(git merge-base "$against" "$current")";
    then
        exit $?
    fi
    echo "SquashCommits End"
}

# Commit
Commit()
{
    echo "Commit Start"
    git add -A
    if ! git commit;
    then
        exit $?
    fi
    echo "Commit End"
}

# Push
Push()
{
    echo "Push Start"
    branch=$(git branch --show-current)
    if ! git push -u $REMOTE "$branch";
    then
        exit $?
    fi
    echo "Push End"
}

# Create PR
CreatePR()
{
    echo "CreatePR Start"
    command="gh pr create --fill --base $BaseBranch"

    for reviewer in "${REVIEWERS[@]}"
    do
        command="$command --reviewer $reviewer"
    done

    $command
    echo "CreatePR End"
}

# Checkout BaseBranch and delete current branch after PR
CheckoutBaseBranchDeleteCurrent()
{
    current=$(git branch --show-current)

    if [ "$current" == "$BaseBranch" ]
    then
        return
    elif ! CheckCurrentBranchRestricted;
    then
        return
    elif [ "$KeepCurrentBranchAfterPR" = true ]
    then
        return
    fi

    echo "CheckoutBaseBranchDeleteCurrent Start"

    if ! git checkout "$BaseBranch";
    then
        exit $?
    fi

    if ! git branch -D "$current";
    then
        exit $?
    fi

    echo "CheckoutBaseBranchDeleteCurrent End"
}

# Checkout branch for PR number
CheckoutBranchForPr()
{
    if [ "$#" -ne 1 ]
    then
        echo "PR number not supplied"
        exit
    fi
    prNumber=$1

    if ! git fetch;
    then
        exit $?
    fi

    branch=$(gh pr view "$prNumber" --json headRefName --template '{{ .headRefName }}')
    if ! git checkout -b "$branch" "${REMOTE}/${branch}";
    then
        exit $?
    fi

    if ! git pull;
    then
        exit $?
    fi
}

# Check if current branch is restricted
CheckCurrentBranchRestricted()
{
    return_value=0
    current=$(git branch --show-current)

    for restricted_branch in "${RESTRICTED_BRANCHES[@]}"
    do
        if [ "$current" == "$restricted_branch" ] ; then
            return_value=1
        fi
    done

    return "$return_value"
}

# SetVars
SetVars()
{
    echo "SetVars Start"

    file="./pr.properties"

    function prop {
        grep "${1}" ${file} | cut -d'=' -f2
    }

    # Set only if no value was provided as script input
    if [ -z "$Input_BaseBranch" ]
    then
        BaseBranch=$(prop 'base_branch')
    else
        BaseBranch=$Input_BaseBranch
    fi

    if [ -z "$Input_RunLintCheck" ]
    then
        RunLintCheck=$(prop 'lint_check')
    else
        RunLintCheck=$Input_RunLintCheck
    fi

    if [ -z "$Input_SquashCommits" ]
    then
        SquashCommits=$(prop 'squash_commits')
    else
        SquashCommits=$Input_SquashCommits
    fi

    if [ -z "$Input_KeepCurrentBranchAfterPR" ]
    then
        KeepCurrentBranchAfterPR=$(prop 'keep_current_branch_after_pr')
    else
        KeepCurrentBranchAfterPR=$Input_KeepCurrentBranchAfterPR
    fi

    echo "SetVars End"
}

Run()
{
    SetVars

    if ! CheckCurrentBranchRestricted;
    then
        echo "Submit changes on a non restricted branch"
        exit 1
    fi

    if [ "$RunLintCheck" = true ]
    then
        LintCheck
    fi

    if [ "$SquashCommits" = true ]
    then
        if [ "$CreatingPR" = true ]
        then
            SquashCommits "$BaseBranch"
        else
            SquashCommits
        fi
    fi

    Commit

    Push

    if [ "$CreatingPR" = true ]
    then
        CreatePR
    fi

    CheckoutBaseBranchDeleteCurrent
}

# Main program
while getopts "hulskb:p:" option; do
    case $option in
        h)
            Help
            exit;;

        u)
            CreatingPR=false;;

        l)
            Input_RunLintCheck=false;;

        s)
            Input_SquashCommits=false;;

        k)
            Input_KeepCurrentBranchAfterPR=true;;

        b)
            Input_BaseBranch=$OPTARG;;

        p)
            CheckoutBranchForPr "$OPTARG"
            exit;;

        \?)
            echo "Error: Invalid option"
            exit;;
    esac
done

Run
