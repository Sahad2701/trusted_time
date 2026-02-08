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
sed -i "s/^version: .*/version: $NEW_VERSION/" pubspec.yaml

# Update CHANGELOG.md - add a new entry at the top
# Assuming ## [version] format
DATE=$(date +%Y-%m-%d)
TEMP_CHANGELOG=$(mktemp)
echo "## $NEW_VERSION ($DATE)" > "$TEMP_CHANGELOG"
echo "" >> "$TEMP_CHANGELOG"
echo "- Automated release: $NEW_VERSION" >> "$TEMP_CHANGELOG"
echo "" >> "$TEMP_CHANGELOG"
cat CHANGELOG.md >> "$TEMP_CHANGELOG"
mv "$TEMP_CHANGELOG" CHANGELOG.md

echo "Successfully updated version to $NEW_VERSION"
