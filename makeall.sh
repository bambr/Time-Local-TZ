#!/usr/bin/env bash

RELEASE_TESTING=1
MODULE=`perl -ne 'print($1),exit if m{version_from.+?([\w/.]+)}i' Makefile.PL`;
perl -v

rm -rf MANIFEST.bak Makefile.old MYMETA.* META.* && \
podselect $MODULE > README.pod && \
pod2text  $MODULE > README && \
perl -i -lpne 's{^\s+$}{};s{^    ((?: {8})+)}{" "x(4+length($1)/2)}se;' README && \

perl Makefile.PL && \
make manifest && \
RELEASE_TESTING=1 make disttest && \
make dist && \
cp -f *.tar.gz dist/ && \
make clean && \
rm -rf MANIFEST.bak MANIFEST Makefile.old *.tar.gz && \
echo
echo "=== FINISHED ==="
echo

