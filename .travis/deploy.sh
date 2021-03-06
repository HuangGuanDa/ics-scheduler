#!/bin/bash
set -e # Exit with nonzero exit code if anything fails

YEAR=2017
TERM=1

SOURCE_BRANCH="production"
TARGET_BRANCH="gh-pages"
OUTPUT_FOLDER="public"

function doCompile {
  npm run build
}

# Pull requests and commits to other branches shouldn't try to deploy, just build to verify
if [ "$TRAVIS_PULL_REQUEST" != "false" -o "$TRAVIS_BRANCH" != "$SOURCE_BRANCH" ]; then
    echo "Skipping deploy; just doing a build."
    doCompile
    exit 0
fi

if [[ "$TRAVIS_PULL_REQUEST" != "false" || "$TRAVIS_BRANCH" == "$SOURCE_BRANCH" ]]; then
  echo 'start running crawler'
  REPO_BASE_URL=`git config remote.origin.url | sed 's/\.git//g'`
  while IFS= read -r org_code
  do
    RAW_DATA_URL="$REPO_BASE_URL/raw/data/$YEAR-$TERM-$org_code.gz"

    echo "downloading $org_code data from $RAW_DATA_URL"
    curl -L $RAW_DATA_URL --output "$YEAR-$TERM-$org_code.gz"

    echo "unzipping..."
    gzip -d < "$YEAR-$TERM-$org_code.gz" > "$YEAR-$TERM-$org_code.json"

    echo "extracting..."
    ./.travis/extract_json "$YEAR-$TERM-$org_code.json"
  done < "support_organizations.txt"
fi

# Save some useful information
REPO=`git config remote.origin.url`
SSH_REPO=${REPO/https:\/\/github.com\//git@github.com:}
SHA=`git rev-parse --verify HEAD`

# Clone the existing gh-pages for this repo into out/
# Create a new empty branch if gh-pages doesn't exist yet (should only happen on first deply)
mkdir $OUTPUT_FOLDER
cd $OUTPUT_FOLDER
git clone $REPO .
git checkout $TARGET_BRANCH || git checkout -b $TARGET_BRANCH origin/$TARGET_BRANCH
cd ..

# Clean out existing contents
rm -rf $OUTPUT_FOLDER/*.js || exit 0
rm -rf $OUTPUT_FOLDER/*.css || exit 0

# Run our compile script
doCompile

# Now let's go have some fun with the cloned repo
cd $OUTPUT_FOLDER
git config user.name "Travis CI"
git config user.email "travis-ci@w3.org"

# If there are no changes to the compiled out (e.g. this is a README update) then just bail.
if [ -n "$(git status --porcelain)" ]; then
  echo "Will deploy a new version";
else
  echo "No changes to the output on this push; exiting."
  exit 0
fi

# Commit the "changes", i.e. the new version.
# The delta will show diffs between new and old versions.
git add --all
git commit -m "Deploy to GitHub Pages: ${SHA}"

# Get the deploy key by using Travis's stored variables to decrypt deploy_key.enc
ENCRYPTED_KEY_VAR="encrypted_${ENCRYPTION_LABEL}_key"
ENCRYPTED_IV_VAR="encrypted_${ENCRYPTION_LABEL}_iv"
ENCRYPTED_KEY=${!ENCRYPTED_KEY_VAR}
ENCRYPTED_IV=${!ENCRYPTED_IV_VAR}
openssl aes-256-cbc -K $ENCRYPTED_KEY -iv $ENCRYPTED_IV -in ../.travis/travis_rsa.enc -out deploy_key -d
chmod 600 deploy_key
eval `ssh-agent -s`
ssh-add deploy_key

# Now that we're all set up, we can push.
git push $SSH_REPO $TARGET_BRANCH
