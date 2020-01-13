#!/bin/sh
rel=`echo "$QUERY_STRING" | sed -n 's/^r=r\([0-9]\+\)-[0-9]\+$/\1/p'`
cnt=`echo "$QUERY_STRING" | sed -n 's/^r=r[0-9]\+-\([0-9]\+\)$/\1/p'`
repo=/sourceware/git/gcc.git

ret=
if [ -n "$rel" ]; then
  if [ -f /opt/rh/git19/enable ]; then
    . /opt/rh/git19/enable
  fi

  sha=`git --git-dir=$repo rev-parse --verify --quiet releases/gcc-$rel`
  if [ -z "$sha" ]; then
    sha=`git --git-dir=$repo rev-parse --verify --quiet master`
  fi
  if [ -n "$sha" ]; then
    num=`git --git-dir=$repo describe --all --match basepoints/gcc-$rel $sha 2>/dev/null \
	 | sed -n 's,^basepoints/gcc-[0-9]\+-\([0-9]\+\)-g[0-9a-f]*$,\1,p;s,^basepoints/gcc-[0-9]\+$,0,p'`
    if [ -n "$num" ]; then
      num=`expr $num - $cnt`
      ret=`git --git-dir=$repo rev-parse --verify $sha~$num`
    fi
  fi
fi
if expr match "$ret" "[0-9a-f]\{7,40\}" > /dev/null; then
  echo 'Content-type: text/html'
  echo
  echo '<html>'
  echo '<meta http-equiv="Refresh" content="0; url=https://gcc.gnu.org/git/gitweb.cgi?p=gcc.git;h='$ret'">'
  echo '</html>'
else
  echo 'Status: 400 Bad Request'
  echo 'Content-type: text/html'
  echo
  echo '<html>'
  echo '<head><title>400 Bad Request</title></head>'
  echo '<body>'
  echo '<h1>Error</h1>'
  echo '<p>Invalid argument or could not determine git revision.</p>'
  echo '</body>'
  echo '</html>'
fi
