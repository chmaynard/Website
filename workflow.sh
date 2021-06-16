#------------------------------------------------------------------------------
#    Workflow Menu
#------------------------------------------------------------------------------

cmm() (
  pushd $CMM_SOURCES
    cmm_precheck
    PS3="> "
    select option in exit status edit build index test publish
    do
      [[ -n $option ]] || { bash -c "$REPLY"; continue; }
      $(printf "cmm_%s\n" $option); exitcode=$?
      if [ $exitcode -ne 0 ]; then return; fi
      continue
    done
  popd
)

#------------------------------------------------------------------------------
#    Workflow Utilities
#------------------------------------------------------------------------------

cmm_print() {
  red=1
  green=2
  yellow=3

  tput setaf $yellow
  printf '==> %s\n' "$1"
  tput sgr0
}

cmm_precheck() {
  git rev-parse --git-dir > /dev/null 2>&1; exitcode=$?
  if [ $exitcode -ne 0 ]
  then
    cmm_print "fatal error (probably not a git repo)"
    exit
  fi

  defaultBranch=$(git config --get init.defaultBranch)
  currentBranch=$(git branch --show-current)

  # make sure we're not on main branch
  if [[ $currentBranch == $defaultBranch ]]
  then
    cmm_print "please switch to a feature branch"
    exit
  fi
}

cmm_repertoire() {
  pushd $CMM_WORKTREES/next/_data
  sqlite3 <<EOS

.headers on
.mode tabs
.import category.tsv category
.import composition.tsv composition
.import concert.tsv concert
.import program.tsv program
.once repertoire.tsv

SELECT 
  category.name AS category, 
  composition.key, 
  composition.composer, 
  composition.name AS composition, 
  concert.date
FROM 
  category, 
  concert, 
  composition, 
  program
WHERE 
  julianday(concert.date) < julianday('now')
  AND composition.category = category.name
  AND program.key = composition.key
  AND concert.name = program.name
ORDER BY 
  category.sequence, 
  composition.key
;

EOS
  popd
}

cmm_shell() {
  # use control-D to return
  bash; return
}

cmm_edit() {
  bbedit .
}

cmm_status() {
  git status --short
}

cmm_exit() {
  exit
}

cmm_build() {
  cmm_print "building website"
  cmm_repertoire
  
  JEKYLL_ENV=production
  
  bundle exec jekyll clean --quiet
  bundle exec jekyll build --quiet --future --trace --destination $CMM_WEBSITE; exitcode=$?
  # cmm_print "exitcode $exitcode"
}

cmm_index() {
  cmm_print "generating and uploading algolia index"
  ALGOLIA_API_KEY="441de4ae91f91058b7c2e11e79f5a1f8"
  bundle exec jekyll algolia > /dev/null 2>&1; exitcode=$?
  cmm_print "exitcode $exitcode"
}

cmm_message() {
    read -ep "Commit message [$msg]: " input
    msg="${input:-$msg}"
}

cmm_commit() {
  if [[ -n $(git status -s) ]]; then
    git add -A
    cmm_message && git commit --quiet -m "$msg"
  fi
}

cmm_test() {
  open -a Safari http://localhost:4000/
}

cmm_publish() {
  msg="wip"
  cmm_precheck
  # reset HEAD while preserving changes to working tree
  # (commits on feature branch will become orphans)
  git reset --soft $defaultBranch
  # commit all changes on feature branch
  git status --short
  cmm_commit

  cmm_print "publishing source code"
  pushd $CMM_SOURCES/$defaultBranch
    git merge --quiet $currentBranch
    # TODO: error-handling
    git push --quiet origin $defaultBranch
  popd

  cmm_print "publishing website"
  pushd $CMM_WEBSITE
    cmm_commit
    git push --quiet origin main
  popd
}
