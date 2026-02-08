#!/bin/bash

# Usage: ./scripts/bump_version.sh [patch|minor|major|manual] [version]
# Example: ./scripts/bump_version.sh minor
# Example: ./scripts/bump_version.sh manual 1.2.3

STRATEGY=$1
MANUAL_VERSION=$2

# Get current version from pubspec.yaml
CURRENT_VERSION=$(grep '^version: ' pubspec.yaml | sed 's/version: //')

if [[ "$STRATEGY" == "manual" ]]; then
    NEW_VERSION=$MANUAL_VERSION
else
    # Split version by dots
    IFS='.' read -ra ADDR <<< "$CURRENT_VERSION"
    MAJOR=${ADDR[0]}
    MINOR=${ADDR[1]}
    PATCH=${ADDR[2]}

    if [[ "$STRATEGY" == "major" ]]; then
        MAJOR=$((MAJOR+1))
        MINOR=0
        PATCH=0
    elif [[ "$STRATEGY" == "minor" ]]; then
        MINOR=$((MINOR+1))
        PATCH=0
    else # default to patch
        PATCH=$((PATCH+1))
    fi
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
fi

echo "Updating version from $CURRENT_VERSION to $NEW_VERSION"

# Update pubspec.yaml
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
else
  sed -i "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml
fi

# Update CHANGELOG.md - add a new entry at the top
DATE=$(date +%Y-%m-%d)

# Fetch commits since last tag for CHANGELOG
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
if [ -z "$LAST_TAG" ]; then
    echo "No previous tag found. Fetching all commits."
    CHANGES=$(git log --pretty=format:"* %s (%h)")
else
    echo "Fetching commits since $LAST_TAG"
    CHANGES=$(git log "$LAST_TAG..HEAD" --pretty=format:"* %s (%h)")
fi

if [ -z "$CHANGES" ]; then
    CHANGES="* Maintenance and internal optimizations."
fi

TEMP_CHANGELOG=$(mktemp)
echo "## $NEW_VERSION ($DATE)" > "$TEMP_CHANGELOG"
echo "" >> "$TEMP_CHANGELOG"
echo "$CHANGES" >> "$TEMP_CHANGELOG"
echo "" >> "$TEMP_CHANGELOG"
cat CHANGELOG.md >> "$TEMP_CHANGELOG"
mv "$TEMP_CHANGELOG" CHANGELOG.md

# Export changes for GitHub Release
echo "$CHANGES" > RELEASE_NOTES_TMP.md

echo "Successfully updated version to $NEW_VERSION"
