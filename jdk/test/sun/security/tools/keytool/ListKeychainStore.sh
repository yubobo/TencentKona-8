#
# Copyright (c) 2012, 2014, Oracle and/or its affiliates. All rights reserved.
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
#
# This code is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 only, as
# published by the Free Software Foundation.
#
# This code is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# version 2 for more details (a copy is included in the LICENSE file that
# accompanied this code).
#
# You should have received a copy of the GNU General Public License version
# 2 along with this work; if not, write to the Free Software Foundation,
# Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
# or visit www.oracle.com if you need additional information or have any
# questions.
#

# @test
# @bug 7133495 8041740 8062264
# @summary [macosx] KeyChain KeyStore implementation retrieves only one private key entry

if [ "${TESTJAVA}" = "" ] ; then
    JAVAC_CMD=`which javac`
    TESTJAVA=`dirname $JAVAC_CMD`/..
fi

if [ "${TESTSRC}" = "" ] ; then
    TESTSRC="."
fi
if [ "${TESTCLASSES}" = "" ] ; then
    TESTCLASSES=`pwd`
fi

# Only run on MacOS
OS=`uname -s`
case "$OS" in
    Darwin )
        ;;
    * )
        echo "Will not run test on: ${OS}"
        exit 0;
        ;;
esac

PWD="xxxxxx"
KEYTOOL="${TESTJAVA}/bin/keytool -storetype KeychainStore -keystore NONE -storepass $PWD"
TEMPORARY_P12="$TESTCLASSES/7133495.p12"
TEMPORARY_KC="$TESTCLASSES/7133495.keychain"
TEMPORARY_LIST="$TESTCLASSES/7133495.tmp"
CLEANUP_P12="rm -f $TEMPORARY_P12"
CLEANUP_KC="security delete-keychain $TEMPORARY_KC"
CLEANUP_LIST="rm -f $TEMPORARY_LIST"

# Count the number of private key entries in the Keychain keystores

COUNT=`$KEYTOOL -list | grep PrivateKeyEntry | wc -l`
echo "Found $COUNT private key entries in the Keychain keystores"

# Create a temporary PKCS12 keystore containing 3 public/private keypairs

RESULT=`$CLEANUP_P12`

for i in X Y Z
do
    ${TESTJAVA}/bin/keytool -genkeypair \
        -storetype PKCS12 \
        -keystore $TEMPORARY_P12 \
        -storepass $PWD \
        -keyalg rsa \
        -dname "CN=$i,OU=$i,O=$i,ST=$i,C=US" \
        -alias 7133495-$i

    if [ $? -ne 0 ]; then
        echo "Error: cannot create keypair $i in the temporary PKCS12 keystore"
        RESULT=`$CLEANUP_P12`
        exit 1
    fi
done
echo "Created a temporary PKCS12 keystore: $TEMPORARY_P12"

# Create a temporary keychain

security create-keychain -p $PWD $TEMPORARY_KC
if [ $? -ne 0 ]; then
    echo "Error: cannot create the temporary keychain"
    RESULT=`$CLEANUP_P12`
    exit 2
fi
echo "Created a temporary keychain: $TEMPORARY_KC"

# Unlock the temporary keychain

security unlock-keychain -p $PWD $TEMPORARY_KC
if [ $? -ne 0 ]; then
    echo "Error: cannot unlock the temporary keychain"
    RESULT=`$CLEANUP_P12`
    RESULT=`$CLEANUP_KC`
    exit 3
fi
echo "Unlocked the temporary keychain"

# Import the keypairs from the PKCS12 keystore into the keychain
# (The '-A' option is used to lower the temporary keychain's access controls)

security import $TEMPORARY_P12 -k $TEMPORARY_KC -f pkcs12 -P $PWD -A
if [ $? -ne 0 ]; then
    echo "Error: cannot import keypairs from PKCS12 keystore into the keychain"
    RESULT=`$CLEANUP_P12`
    RESULT=`$CLEANUP_KC`
    exit 4
fi
echo "Imported keypairs from PKCS12 keystore into the keychain"

# Adjust the keychain search order

echo "\"$TEMPORARY_KC\"" > $TEMPORARY_LIST
security list-keychains >> $TEMPORARY_LIST
security list-keychains -s `xargs < ${TEMPORARY_LIST}`
`$CLEANUP_LIST`
echo "Temporary keychain search order:"
security list-keychains

# Recount the number of private key entries in the Keychain keystores

RECOUNT=`$KEYTOOL -list | grep PrivateKeyEntry | wc -l`
echo "Found $RECOUNT private key entries in the Keychain keystore"
if [ $RECOUNT -lt `expr $COUNT + 3` ]; then
    echo "Error: expected >$COUNT private key entries in the Keychain keystores"
    RESULT=`$CLEANUP_P12`
    RESULT=`$CLEANUP_KC`
    exit 5
fi

# Export a private key from the keychain (without supplying a password)
# Access controls have already been lowered (see 'security import ... -A' above)

${TESTJAVA}/bin/javac ${TESTJAVACOPTS} ${TESTTOOLVMOPTS} -d . ${TESTSRC}/ExportPrivateKeyNoPwd.java || exit 6
echo | ${TESTJAVA}/bin/java ${TESTVMOPTS} ExportPrivateKeyNoPwd x
if [ $? -ne 0 ]; then
    echo "Error exporting private key from the temporary keychain"
    RESULT=`$CLEANUP_P12`
    RESULT=`$CLEANUP_KC`
    exit 6
fi
echo "Exported a private key from the temporary keychain"

RESULT=`$CLEANUP_P12`
if [ $? -ne 0 ]; then
    echo "Error: cannot remove the temporary PKCS12 keystore"
    exit 7
fi
echo "Removed the temporary PKCS12 keystore"

RESULT=`$CLEANUP_KC`
if [ $? -ne 0 ]; then
    echo "Error: cannot remove the temporary keychain"
    exit 8
fi
echo "Removed the temporary keychain"

exit 0
