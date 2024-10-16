#!/bin/bash

# Constants
REMOTE="origin"
RESTRICTED_BRANCHES=("develop")
REVIEWERS=(StephenMilone currentraghavkishan lewis-current kevin-current AVSEQ00 ramit-current)

# Variables
CreatingPr=false
BaseBranch="develop"
RunLintCheck=true
SquashCommits=true
KeepCurrentBranchAfterPr=false

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

Override for the defaults can be provided via a pr.properties txt file in the project's root directory or via input flags to the script

l    Skip lint checks
s    Skip squashing commits
k    Keep the current branch and don't checkout BaseBranch after PR
b    Set the BaseBranch var to squash commits and create PR against

Branch for an existing PR can be checked out by using the input flag p

Example pr.properties file

base_branch=feature-test
squash_commits=false
lint_check=false
keep_current_branch_after_pr=true

To use
- install GitHub cli
- run 'gh auth login'
- select github.com, select ssh, skip selecting ssh key, login with browser
- [Do If Getting Authentication Error] create personal access token to login
- [Do If Still Getting Authentication Error] create ssh key for GitHub cli, run gh auth login and select the created key this time

Examples
./scripts/pr.sh
Create or update PR

./scripts/pr.sh -s
Create or update PR but skip squashing commits

./scripts/pr.sh -b feature-test
Create PR against feature-test branch

./scripts/pr.sh -k
Create or update PR and keep the PR branch

./scripts/pr.sh -p 999
Checkout the remote branch associated with the PR number 999"
}

LintCheck()
{
    echo "LintCheck Start"
    if ! ./gradlew detektAutoCorrect;
    then
        exit $?
    fi
    echo "LintCheck End"
}

SquashCommits()
{
    current=$(git branch --show-current)

    # We don't want to rewrite history if the branch exists on remote, so squash against
    # remote branch, otherwise against the base branch
    if git ls-remote --exit-code --heads git@github.com:ramit-current/test.git refs/heads/$current
    then
        against="$REMOTE/$current"
    else
        against=$BaseBranch
    fi

    echo "SquashCommits Start against $against"
    if ! git reset "$(git merge-base "$against" "$current")";
    then
        exit $?
    fi
    echo "SquashCommits End"
}

Commit()
{
    echo "Commit Start"
    git add -A
    if [ -z "$(git status --porcelain)" ] # If file changes empty or null then do nothing
    then
        echo "Nothing to commit"
        return
    fi
    git commit
    echo "Commit End"
}

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

CreatePr()
{
    echo "CreatePr Start"
    command="gh pr create --fill --base $BaseBranch"

    for reviewer in "${REVIEWERS[@]}"
    do
        command="$command --reviewer $reviewer"
    done

    $command
    echo "CreatePr End"
}

CheckoutBaseBranchDeleteCurrent()
{
    current=$(git branch --show-current)

    if [ "$current" == "$BaseBranch" ]
    then
        return
    elif ! CheckCurrentBranchRestricted;
    then
        return
    elif [ "$KeepCurrentBranchAfterPr" = true ]
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

SetVars()
{
    echo "SetVars Start"

    # Check if PR exists for current branch
    if ! pr_view_output=$(gh pr view 2>&1)
    then
        error_code=$?
        # If output contains "no pull requests" it means we're creating a PR
        if [[ $pr_view_output == *"no pull requests"* ]];
        then
            CreatingPr=true
        # Some other error occurred
        else
            echo $pr_view_output
            exit $error_code
        fi
    fi

    file="./pr.properties"

    function prop {
      if [ ! -f $file ]; then
          echo ''
      else
          grep "${1}" ${file} | cut -d'=' -f2
      fi
    }

    # Override script default with script input, if not provided override with value in properties
    if [ -n "$Input_BaseBranch" ]
    then
        BaseBranch=$Input_BaseBranch
    elif [ -n "$(prop 'base_branch')" ]
    then
        BaseBranch=$(prop 'base_branch')
    fi

    if [ -n "$Input_RunLintCheck" ]
    then
        RunLintCheck=$Input_RunLintCheck
    elif [ -n "$(prop 'lint_check')" ]
    then
        RunLintCheck=$(prop 'lint_check')
    fi

    if [ -n "$Input_SquashCommits" ]
    then
        SquashCommits=$Input_SquashCommits
    elif [ -n "$(prop 'squash_commits')" ]
    then
        SquashCommits=$(prop 'squash_commits')
    fi

    if [ -n "$Input_KeepCurrentBranchAfterPr" ]
    then
        KeepCurrentBranchAfterPr=$Input_KeepCurrentBranchAfterPr
    elif [ -n "$(prop 'keep_current_branch_after_pr')" ]
    then
        KeepCurrentBranchAfterPr=$(prop 'keep_current_branch_after_pr')
    fi

    bold=$(tput bold)
    normal=$(tput sgr0)
    creating_pr_text="creating"
    if [ "$CreatingPr" = false ]
    then
        creating_pr_text="updating"
    fi

    echo "
${normal}BaseBranch: ${bold}$BaseBranch
${normal}Creating or Updating PR: ${bold}$creating_pr_text
${normal}LintCheck: ${bold}$RunLintCheck
${normal}Squash: ${bold}$SquashCommits
${normal}KeepCurrentBranchAfterPR: ${bold}$KeepCurrentBranchAfterPr

${normal}SetVars End"
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
        SquashCommits
    fi

    Commit

    Push

    if [ "$CreatingPr" = true ]
    then
        CreatePr
    fi

    CheckoutBaseBranchDeleteCurrent
}

# Main program
while getopts "hlskb:p:" option; do
    case $option in
        h)
            Help
            exit;;

        l)
            Input_RunLintCheck=false;;

        s)
            Input_SquashCommits=false;;

        k)
            Input_KeepCurrentBranchAfterPr=true;;

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
