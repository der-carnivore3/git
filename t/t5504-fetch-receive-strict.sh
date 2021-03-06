#!/bin/sh

test_description='fetch/receive strict mode'
. ./test-lib.sh

test_expect_success 'setup and inject "corrupt or missing" object' '
	echo hello >greetings &&
	git add greetings &&
	git commit -m greetings &&

	S=$(git rev-parse :greetings | sed -e "s|^..|&/|") &&
	X=$(echo bye | git hash-object -w --stdin | sed -e "s|^..|&/|") &&
	echo $S >S &&
	echo $X >X &&
	cp .git/objects/$S .git/objects/$S.back &&
	mv -f .git/objects/$X .git/objects/$S &&

	test_must_fail git fsck
'

test_expect_success 'fetch without strict' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config fetch.fsckobjects false &&
		git config transfer.fsckobjects false &&
		test_must_fail git fetch ../.git master
	)
'

test_expect_success 'fetch with !fetch.fsckobjects' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config fetch.fsckobjects false &&
		git config transfer.fsckobjects true &&
		test_must_fail git fetch ../.git master
	)
'

test_expect_success 'fetch with fetch.fsckobjects' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config fetch.fsckobjects true &&
		git config transfer.fsckobjects false &&
		test_must_fail git fetch ../.git master
	)
'

test_expect_success 'fetch with transfer.fsckobjects' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config transfer.fsckobjects true &&
		test_must_fail git fetch ../.git master
	)
'

cat >exp <<EOF
To dst
!	refs/heads/master:refs/heads/test	[remote rejected] (missing necessary objects)
EOF

test_expect_success 'push without strict' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config fetch.fsckobjects false &&
		git config transfer.fsckobjects false
	) &&
	test_must_fail git push --porcelain dst master:refs/heads/test >act &&
	test_cmp exp act
'

test_expect_success 'push with !receive.fsckobjects' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config receive.fsckobjects false &&
		git config transfer.fsckobjects true
	) &&
	test_must_fail git push --porcelain dst master:refs/heads/test >act &&
	test_cmp exp act
'

cat >exp <<EOF
To dst
!	refs/heads/master:refs/heads/test	[remote rejected] (unpacker error)
EOF

test_expect_success 'push with receive.fsckobjects' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config receive.fsckobjects true &&
		git config transfer.fsckobjects false
	) &&
	test_must_fail git push --porcelain dst master:refs/heads/test >act &&
	test_cmp exp act
'

test_expect_success 'push with transfer.fsckobjects' '
	rm -rf dst &&
	git init dst &&
	(
		cd dst &&
		git config transfer.fsckobjects true
	) &&
	test_must_fail git push --porcelain dst master:refs/heads/test >act &&
	test_cmp exp act
'

test_expect_success 'repair the "corrupt or missing" object' '
	mv -f .git/objects/$(cat S) .git/objects/$(cat X) &&
	mv .git/objects/$(cat S).back .git/objects/$(cat S) &&
	rm -rf .git/objects/$(cat X) &&
	git fsck
'

cat >bogus-commit <<EOF
tree $EMPTY_TREE
author Bugs Bunny 1234567890 +0000
committer Bugs Bunny <bugs@bun.ni> 1234567890 +0000

This commit object intentionally broken
EOF

test_expect_success 'fsck with invalid or bogus skipList input' '
	git -c fsck.skipList=/dev/null -c fsck.missingEmail=ignore fsck &&
	test_must_fail git -c fsck.skipList=does-not-exist -c fsck.missingEmail=ignore fsck 2>err &&
	test_i18ngrep "Could not open skip list: does-not-exist" err &&
	test_must_fail git -c fsck.skipList=.git/config -c fsck.missingEmail=ignore fsck 2>err &&
	test_i18ngrep "Invalid SHA-1: \[core\]" err
'

test_expect_success 'push with receive.fsck.skipList' '
	commit="$(git hash-object -t commit -w --stdin <bogus-commit)" &&
	git push . $commit:refs/heads/bogus &&
	rm -rf dst &&
	git init dst &&
	git --git-dir=dst/.git config receive.fsckObjects true &&
	test_must_fail git push --porcelain dst bogus &&
	echo $commit >dst/.git/SKIP &&

	# receive.fsck.* does not fall back on fsck.*
	git --git-dir=dst/.git config fsck.skipList SKIP &&
	test_must_fail git push --porcelain dst bogus &&

	# Invalid and/or bogus skipList input
	git --git-dir=dst/.git config receive.fsck.skipList /dev/null &&
	test_must_fail git push --porcelain dst bogus &&
	git --git-dir=dst/.git config receive.fsck.skipList does-not-exist &&
	test_must_fail git push --porcelain dst bogus 2>err &&
	test_i18ngrep "Could not open skip list: does-not-exist" err &&
	git --git-dir=dst/.git config receive.fsck.skipList config &&
	test_must_fail git push --porcelain dst bogus 2>err &&
	test_i18ngrep "Invalid SHA-1: \[core\]" err &&

	git --git-dir=dst/.git config receive.fsck.skipList SKIP &&
	git push --porcelain dst bogus
'

test_expect_success 'fetch with fetch.fsck.skipList' '
	commit="$(git hash-object -t commit -w --stdin <bogus-commit)" &&
	refspec=refs/heads/bogus:refs/heads/bogus &&
	git push . $commit:refs/heads/bogus &&
	rm -rf dst &&
	git init dst &&
	git --git-dir=dst/.git config fetch.fsckObjects true &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec &&
	git --git-dir=dst/.git config fetch.fsck.skipList /dev/null &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec &&
	echo $commit >dst/.git/SKIP &&

	# fetch.fsck.* does not fall back on fsck.*
	git --git-dir=dst/.git config fsck.skipList dst/.git/SKIP &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec &&

	# Invalid and/or bogus skipList input
	git --git-dir=dst/.git config fetch.fsck.skipList /dev/null &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec &&
	git --git-dir=dst/.git config fetch.fsck.skipList does-not-exist &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec 2>err &&
	test_i18ngrep "Could not open skip list: does-not-exist" err &&
	git --git-dir=dst/.git config fetch.fsck.skipList dst/.git/config &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec 2>err &&
	test_i18ngrep "Invalid SHA-1: \[core\]" err &&

	git --git-dir=dst/.git config fetch.fsck.skipList dst/.git/SKIP &&
	git --git-dir=dst/.git fetch "file://$(pwd)" $refspec
'

test_expect_success 'fsck.<unknownmsg-id> dies' '
	test_must_fail git -c fsck.whatEver=ignore fsck 2>err &&
	test_i18ngrep "Unhandled message id: whatever" err
'

test_expect_success 'push with receive.fsck.missingEmail=warn' '
	commit="$(git hash-object -t commit -w --stdin <bogus-commit)" &&
	git push . $commit:refs/heads/bogus &&
	rm -rf dst &&
	git init dst &&
	git --git-dir=dst/.git config receive.fsckobjects true &&
	test_must_fail git push --porcelain dst bogus &&

	# receive.fsck.<msg-id> does not fall back on fsck.<msg-id>
	git --git-dir=dst/.git config fsck.missingEmail warn &&
	test_must_fail git push --porcelain dst bogus &&

	# receive.fsck.<unknownmsg-id> warns
	git --git-dir=dst/.git config \
		receive.fsck.whatEver error &&

	git --git-dir=dst/.git config \
		receive.fsck.missingEmail warn &&
	git push --porcelain dst bogus >act 2>&1 &&
	grep "missingEmail" act &&
	test_i18ngrep "Skipping unknown msg id.*whatever" act &&
	git --git-dir=dst/.git branch -D bogus &&
	git --git-dir=dst/.git config --add \
		receive.fsck.missingEmail ignore &&
	git push --porcelain dst bogus >act 2>&1 &&
	! grep "missingEmail" act
'

test_expect_success 'fetch with fetch.fsck.missingEmail=warn' '
	commit="$(git hash-object -t commit -w --stdin <bogus-commit)" &&
	refspec=refs/heads/bogus:refs/heads/bogus &&
	git push . $commit:refs/heads/bogus &&
	rm -rf dst &&
	git init dst &&
	git --git-dir=dst/.git config fetch.fsckobjects true &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec &&

	# fetch.fsck.<msg-id> does not fall back on fsck.<msg-id>
	git --git-dir=dst/.git config fsck.missingEmail warn &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" $refspec &&

	# receive.fsck.<unknownmsg-id> warns
	git --git-dir=dst/.git config \
		fetch.fsck.whatEver error &&

	git --git-dir=dst/.git config \
		fetch.fsck.missingEmail warn &&
	git --git-dir=dst/.git fetch "file://$(pwd)" $refspec >act 2>&1 &&
	grep "missingEmail" act &&
	test_i18ngrep "Skipping unknown msg id.*whatever" act &&
	rm -rf dst &&
	git init dst &&
	git --git-dir=dst/.git config fetch.fsckobjects true &&
	git --git-dir=dst/.git config \
		fetch.fsck.missingEmail ignore &&
	git --git-dir=dst/.git fetch "file://$(pwd)" $refspec >act 2>&1 &&
	! grep "missingEmail" act
'

test_expect_success \
	'receive.fsck.unterminatedHeader=warn triggers error' '
	rm -rf dst &&
	git init dst &&
	git --git-dir=dst/.git config receive.fsckobjects true &&
	git --git-dir=dst/.git config \
		receive.fsck.unterminatedheader warn &&
	test_must_fail git push --porcelain dst HEAD >act 2>&1 &&
	grep "Cannot demote unterminatedheader" act
'

test_expect_success \
	'fetch.fsck.unterminatedHeader=warn triggers error' '
	rm -rf dst &&
	git init dst &&
	git --git-dir=dst/.git config fetch.fsckobjects true &&
	git --git-dir=dst/.git config \
		fetch.fsck.unterminatedheader warn &&
	test_must_fail git --git-dir=dst/.git fetch "file://$(pwd)" HEAD &&
	grep "Cannot demote unterminatedheader" act
'

test_done
