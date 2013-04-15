#!/bin/sh

ENCODING=UTF-8
STD=3.3
LICENSE=modelica2
SVNOPTS="--non-interactive --username anonymous"
while echo $1 | grep -q "^--"; do
OPT="$1"
shift
case $OPT in
--encoding)
  ENCODING=$1
  shift
  ;;
--std)
  STD=$1
  shift
  ;;
--license)
  LICENSE=$1
  shift
  ;;
--breaks)
  BREAKS=$1
  shift
  ;;
*)
  echo "Unknown option $OPT"
  exit 1
  ;;
esac

done

if test $# -lt 5 || !(test "$1" = SVN || test "$1" = GIT); then
  echo "Usage: $0 [flags] [SVN|GIT] URL REVISION DEST [LIBRARIES]"
  echo "   --encoding=[UTF-8]"
  echo "   --std=[3.3]"
  exit 1
fi
TYPE="$1"
URL="$2"
REVISION="$3"
DEST="$4"
shift;shift;shift;shift

if test "$TYPE" = SVN; then

if ! test -d "$DEST"; then
  svn co $SVNOPTS "-r$REVISION" "$URL" "$DEST" || exit 1
  echo "$REVISION" > "$DEST.rev"
elif test -d "$DEST" && ! test "$URL" = "`svn info "$DEST" | grep ^URL: | sed "s/URL: //"`"; then
  echo "Not same URL... $URL and `svn info "$DEST" | grep ^URL: | sed "s/URL: //"`"
  rm -rf "$DEST"
  svn co $SVNOPTS "-r$REVISION" "$URL" "$DEST" || exit 1
  echo "$REVISION" > "$DEST.rev"
elif ! test `cat "$DEST.rev"` = $REVISION; then
  if ! svn up "-r$REVISION" "$DEST"; then
    echo "Failed to update $DEST"
    rm -rf "$DEST"
    exit 1
  fi
  echo "$REVISION" > "$DEST.rev"
else
  echo "$DEST is up to date"
fi

else # GIT
# git --no-pager log --date=short --max-count=1 Makefile | grep Date: | cut -d\  -f4
  exit 1
fi

mkdir -p build/
if test "$*" = "all"; then
 shift
 CURWD=`pwd`
 cd "$DEST"
 for f in *.mo */package.mo; do
   if test "$f" != "package.mo"; then
     LIBS="$LIBS `echo $f | grep -v "[*]" | sed "s/ /%20/g" | sed "s,/package.mo,," | sed "s,.mo$,,"`"
   fi
 done
 cd "$CURWD"
elif test "$*" = "none"; then
 shift
fi
echo $LIBS
for f in $LIBS "$@"; do
  if test "$f" = "self"; then
    LIB=`./get-name.sh "$DEST/package.mo" "$ENCODING" "$STD"`
    VER=""
    if test -z "$LIB"; then
      echo "*** Error: Failed to read package name from $DEST/package.mo"
      exit 1
    fi
  else
    LIB=`echo $f | sed "s/%20/ /g" | cut -d" " -f1`
    VER=`echo $f | sed "s/%20/ /g" | grep " " | cut -d" " -f2`
    echo Copy library $LIB version $VER from `pwd`
  fi
  if test "$f" = "self"; then
    SOURCE="$DEST"
    EXT=""
  elif test -d "$DEST/$LIB $VER"; then
    SOURCE="$DEST/$LIB $VER"
    EXT=""
  elif test -f "$DEST/$LIB $VER.mo"; then
    SOURCE="$DEST/$LIB $VER.mo"
    EXT=".mo"
  elif test -d "$DEST/$LIB"; then
    SOURCE="$DEST/$LIB"
    MOFILE="$DEST/$LIB/package.mo"
    EXT=""
  elif test -f "$DEST/$LIB.mo"; then
    SOURCE="$DEST/$LIB.mo"
    MOFILE="$SOURCE"
    EXT=".mo"
  else
    echo "Did not find library $DEST/$LIB :("
    exit 1
  fi
  if test -z "$VER"; then
    VER=`./get-version.sh "$MOFILE" "$LIB" "$ENCODING" "$STD"`
    echo "Got version $VER for $LIB"
    if test -z "$VER"; then
      NAME="$LIB"
    else
      NAME="$LIB $VER"
    fi
  elif test "$VER" = "none"; then
    NAME="$LIB"
  else
    NAME="$LIB $VER"
  fi
  echo $LICENSE > "build/$NAME.license"
  rm -rf "build/$NAME" "build/$NAME.mo"
  cp -rp "$SOURCE" "build/$NAME$EXT"
  if test -f "$NAME.patch"; then
    if ! patch -d build/ -p1 < "$NAME.patch"; then
      echo "Failed to apply $NAME.patch"
      exit 1
    fi
    echo "Applied $NAME.patch"
    PATCHREV=`git rev-list HEAD --count "$NAME.patch" 2>/dev/null`
    if test -z "$PATCHREV"; then
      echo "Not a git repository. We need it to give patch revisions."
      exit 1
    fi
    PATCHREV=`echo -om$PATCHREV`
  else
    PATCHREV=""
  fi
  if test "$TYPE" = SVN; then
    echo `svn info --xml "$SOURCE" | xpath -q -e '/info/entry/commit/@revision' | grep -o "[0-9]*"`$PATCHREV > "build/$NAME.last_change"
    svn log --xml --verbose "$SOURCE" | sed "s,<date>.*</date>,<date>1970-01-01</date>," | sed "s,<author>\(.*\)</author>,<author>none</author><author-svn>\1</author-svn>," | xsltproc svn2cl.xsl - > "build/$NAME.changes"
  fi
  if ! test -z "$BREAKS"; then
    echo $BREAKS > "build/$NAME.breaks"
  fi
  rm -rf "build/$NAME$EXT/.svn" "build/$NAME$EXT/.git*"

  if ! test "$ENCODING" = "UTF-8"; then
    echo "$ENCODING" > "build/$NAME/package.encoding"
  fi
done
