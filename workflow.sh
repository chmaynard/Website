#!/usr/bin/env bash

set -o allexport

#------------------------------------------------------------------------------
#    Workflow
#------------------------------------------------------------------------------

cmm_setenv() {
  for d in $CMM_HOME/*; do
    if [ -d "$d" ]; then
      key=$(echo CMM_${d##*/} | tr 'a-z' 'A-Z')
      eval echo \${$key=$d} > /dev/null
    fi
  done
}
  
cmm_echo() {
  red=1
  green=2
  yellow=3

  tput setaf $yellow
  echo "==> $1"
  tput sgr0
}

cmm_status() {
  git status --short; exitcode=$?
  if [ $exitcode -ne 0 ]
  then
    # fatal error (probably not a git repo)
    cmm_exit
  fi

  defaultBranch=$(git config --get init.defaultBranch)
  currentBranch=$(git branch --show-current)

  if [[ $currentBranch == $defaultBranch ]]
  then
    cmm_echo "please switch to a feature branch"
    cmm_exit
  fi
}

cmm_edit() {
  bbedit .
}

cmm_refresh() {
  _scripts/repertoire.sh
}

cmm_stop() {
  if [ -n exec 2>$CMM_LOGS/cmm_test.log 3>/dev/tcp/localhost/4000 ]
  then
    # cmm_echo "stopping server"
    kill -s KILL $(lsof -ti tcp:4000)
  fi
}

cmm_build() {
  cmm_echo "building website"
  JEKYLL_ENV=production
  bundle exec jekyll clean --quiet
  bundle exec jekyll build --quiet --future --trace --destination $CMM_WEBSITE; exitcode=$?
    if [ $exitcode -ne 0 ]
    then
      cmm_echo "jekyll build error"
    fi
}

cmm_message() {
    read -ep "Commit message [$default_msg]: " input
    msg="${input:-$default_msg}"
}

cmm_commit() {
  if [ -z "$(git status --short)" ]
  then
    cmm_echo "no changes"
  else
    git add -A
    git commit --quiet -m "$msg"
  fi
}

cmm_publish() {
  # make sure we're on feature branch
  cmm_status
  # reset HEAD while preserving changes to working tree
  # (commits on feature branch will become orphans)
  git reset --soft $defaultBranch
  # commit all changes on feature branch
  cmm_message; cmm_commit

  cmm_echo "publishing source code"
  pushb $defaultBranch
    git merge --quiet $currentBranch
    # TODO: error-handling
    git push --quiet origin $defaultBranch
  popb

  cmm_echo "publishing website"
  pushd $CMM_WEBSITE
    cmm_commit
    git push --quiet origin $defaultBranch
  popd
}

cmm_branch() {

  options=()
  mapfile -t options < <(git for-each-ref --format='%(refname:short)' refs/heads/) &>/dev/null

  select opt in "${options[@]}"
  do
      if [[ "$opt" ]]; then
          git checkout "$opt"
          return
      else
          echo "Wrong Input. Please enter the correct input"
      fi
  done
}

cmm_shell() (
  bash
)

cmm_exit() {
  popd
  exit
}

cmm_main() (
  pushd $CMM_SOURCE
    PS3="> "
    select option in exit edit build publish repertoire shell
    do
      $(printf "cmm_%s\n" $option); exitcode=$?
      if [ $exitcode -ne 0 ]; then return; fi
      continue
    done
  popd
)

alias cmm=cmm_main
default_msg="wip"

#------------------------------------------------------------------------------
#    Data Utilities
#------------------------------------------------------------------------------

cmm_repertoire() {
  pushd $CMM_SOURCE/_data

  sqlite3 <<EOS

.headers on
.mode tabs

.import composition.tsv composition
.import composer.tsv composer
.once repertoire.tsv

SELECT a.key, a.date, a.class, b.last, a.title
FROM composition a, composer b
WHERE length(a.date) > 0
AND a.composer = b.name
ORDER BY 3, 1;

EOS

  popd
}

#------------------------------------------------------------------------------
#   Docker
#------------------------------------------------------------------------------

cmm_docker() {
  # Check if docker is running
  if ! docker info >/dev/null 2>&1; then
    # synchronous launch
    open -a Docker
    while ! docker system info > /dev/null 2>&1; do sleep 1; done
    # run the command
    docker run --rm --mount type=bind,source="$PWD",target=/cmm $CMD
  fi
}

#------------------------------------------------------------------------------
#   imagemagick via Docker
#------------------------------------------------------------------------------

cmm_resize() {
  # USAGE: cmm_resize 1300 original.jpg [output.jpg]
  SIZE=$(echo "$1" | bc -l)
  SRC=/cmm/$2
  DST=/cmm/$3
  if [ -z $3 ]; then DST=$SRC; fi
  
  CMD="dpokidov/imagemagick $SRC -resize $SIZE $DST"
  cmm_docker
}

cmm_sharpen() {
  # USAGE: cmm_sharpen cmm/original.jpg [output.jpg]
  SRC=/cmm/$1
  DST=/cmm/$2
  if [ -z $2 ]; then DST=$SRC; fi
  
  CMD="dpokidov/imagemagick $SRC -unsharp 0x0.75+0.75+0.008 $DST"
  cmm_docker
}

cmm_pixelate() {
  # USAGE: cmm_pixelate 0.5 original.jpg [output.jpg]
  AMT=$(echo "1.001 - $1" | bc -l)
  SRC=/cmm/$2
  DST=/cmm/$3
  if [ -z $3 ]; then DST=$SRC; fi

  COEFF1=$(echo "100 * $AMT" | bc -l)
  COEFF2=$(echo "100 / $AMT" | bc -l)

  CMD="dpokidov/imagemagick -scale $COEFF1% -scale $COEFF2% $SRC $DST"
  cmm_docker
}

#------------------------------------------------------------------------------
#    ffmpeg via Docker
#------------------------------------------------------------------------------

cmm_fade() {
  pushd ~/Movies
  START=2035
  DURATION=5
  CMD='linuxserver/ffmpeg -i /cmm/in.mp4 -hide_banner -filter_complex \"fade=t=out:st=$START:d=$DURATION, afade=t=out:st=2035:d=5\" -c:v libx264 -c:a aac /cmm/out.mp4'
  cmm_docker
  popd
}
