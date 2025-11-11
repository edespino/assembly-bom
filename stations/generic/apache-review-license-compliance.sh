#!/bin/bash
#
# Apache Incubator Source Release - License Compliance Review Script
#
# This script helps identify potential licensing issues in Apache source releases
# Usage: ./review-license-compliance.sh [source-dir]
#

set -e

SOURCE_DIR="${1:-.}"
REVIEW_OUTPUT_DIR="license-review-$(date +%Y%m%d-%H%M%S)"

echo "=========================================="
echo "Apache Source Release License Review"
echo "=========================================="
echo "Source Directory: $SOURCE_DIR"
echo "Output Directory: $REVIEW_OUTPUT_DIR"
echo ""

mkdir -p "$REVIEW_OUTPUT_DIR"

cd "$SOURCE_DIR"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

section() {
    echo ""
    echo -e "${GREEN}=== $1 ===${NC}"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

error() {
    echo -e "${RED}ERROR: $1${NC}"
}

section "1. Searching for Derived/Copied Code"

echo "Looking for attribution keywords in source files..."
grep -r "derived from\|adapted from\|based on\|copied from\|ported from" \
    --include="*.java" --include="*.scala" --include="*.py" --include="*.go" \
    --exclude-dir=target --exclude-dir=dist --exclude-dir=.git \
    . > "$REVIEW_OUTPUT_DIR/derived-code.txt" 2>/dev/null || echo "No explicit derivation comments found"

if [ -s "$REVIEW_OUTPUT_DIR/derived-code.txt" ]; then
    warning "Found potential derived code - review $REVIEW_OUTPUT_DIR/derived-code.txt"
    cat "$REVIEW_OUTPUT_DIR/derived-code.txt"
else
    echo "✓ No obvious derivation comments found"
fi

section "2. Finding Non-ASF Copyright Statements"

echo "Searching for copyright statements not from ASF..."
grep -rh "Copyright (C)\|Copyright ©\|Copyright (c)" \
    --include="*.java" --include="*.scala" --include="*.py" --include="*.go" \
    --exclude-dir=target --exclude-dir=dist --exclude-dir=.git \
    . 2>/dev/null | \
    grep -v "Apache Software Foundation" | \
    sort -u > "$REVIEW_OUTPUT_DIR/non-asf-copyrights.txt" || true

if [ -s "$REVIEW_OUTPUT_DIR/non-asf-copyrights.txt" ]; then
    warning "Found non-ASF copyright statements:"
    cat "$REVIEW_OUTPUT_DIR/non-asf-copyrights.txt"
    echo ""
    echo "These should be mentioned in the LICENSE file!"
else
    echo "✓ No non-ASF copyright statements found"
fi

section "3. Finding Files with Multiple License Headers"

echo "Checking for files with multiple license headers..."
find . -type f \( -name "*.java" -o -name "*.scala" -o -name "*.py" \) \
    -not -path "*/target/*" -not -path "*/dist/*" -not -path "*/.git/*" \
    -exec grep -l "Licensed to the Apache Software Foundation" {} \; 2>/dev/null | \
    while read file; do
        # Check if file also has other copyright/license statements
        if grep -q "Copyright (C)" "$file" 2>/dev/null && ! grep -q "Apache Software Foundation" <<< "$(grep "Copyright" "$file")"; then
            echo "$file"
        fi
    done > "$REVIEW_OUTPUT_DIR/multiple-headers.txt"

if [ -s "$REVIEW_OUTPUT_DIR/multiple-headers.txt" ]; then
    warning "Files with potential multiple license headers:"
    cat "$REVIEW_OUTPUT_DIR/multiple-headers.txt"
else
    echo "✓ No obvious multiple license headers found"
fi

section "4. Checking Root LICENSE File"

if [ -f LICENSE ]; then
    echo "Root LICENSE file exists"

    # Check if non-ASF copyrights are mentioned in LICENSE
    if [ -s "$REVIEW_OUTPUT_DIR/non-asf-copyrights.txt" ]; then
        echo ""
        echo "Verifying non-ASF copyrights are in LICENSE file..."
        while IFS= read -r copyright; do
            # Extract the copyright holder name (rough heuristic)
            holder=$(echo "$copyright" | sed -e 's/.*Copyright[^0-9]*[0-9,-]* *//' -e 's/[. ]*$//' | head -c 50)
            if ! grep -qi "$holder" LICENSE 2>/dev/null; then
                error "Copyright holder not found in LICENSE: $holder"
                echo "  From: $copyright"
            fi
        done < "$REVIEW_OUTPUT_DIR/non-asf-copyrights.txt"
    fi
else
    error "No LICENSE file found in root directory!"
fi

section "5. Checking NOTICE File"

if [ -f NOTICE ]; then
    echo "✓ Root NOTICE file exists"
    echo "Review manually for proper attributions"
else
    warning "No NOTICE file found in root directory"
fi

section "6. Analyzing Build Dependencies"

echo "Extracting dependencies from build files..."

# SBT projects
if [ -f build.sbt ] || find . -name "*.sbt" -type f | grep -q .; then
    echo "Found SBT build files"
    find . -name "*.sbt" -not -path "*/target/*" -not -path "*/project/target/*" \
        -exec grep -h "libraryDependencies\|\".*\" %" {} \; 2>/dev/null | \
        sort -u > "$REVIEW_OUTPUT_DIR/sbt-dependencies.txt" || true

    if [ -s "$REVIEW_OUTPUT_DIR/sbt-dependencies.txt" ]; then
        echo "Extracted SBT dependencies to $REVIEW_OUTPUT_DIR/sbt-dependencies.txt"
    fi
fi

# Maven projects
if [ -f pom.xml ]; then
    echo "Found Maven POM"
    grep -A 3 "<dependency>" pom.xml > "$REVIEW_OUTPUT_DIR/maven-dependencies.txt" || true
fi

# Gradle projects
if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    echo "Found Gradle build files"
    grep "implementation\|compile\|api" build.gradle* 2>/dev/null > "$REVIEW_OUTPUT_DIR/gradle-dependencies.txt" || true
fi

section "7. Scanning for Assembly/Uber JARs"

echo "Looking for assembly/uber/fat JARs..."
find . -name "*-assembly-*.jar" -o -name "*-uber-*.jar" -o -name "*-all-*.jar" -o -name "*-fat-*.jar" 2>/dev/null | \
    grep -v "\.git" > "$REVIEW_OUTPUT_DIR/assembly-jars.txt" || true

if [ -s "$REVIEW_OUTPUT_DIR/assembly-jars.txt" ]; then
    warning "Found assembly JARs - these need careful license review!"
    cat "$REVIEW_OUTPUT_DIR/assembly-jars.txt"

    while IFS= read -r jarfile; do
        if [ -f "$jarfile" ]; then
            jarname=$(basename "$jarfile")
            echo ""
            echo "Analyzing $jarname..."

            # List contents
            unzip -l "$jarfile" > "$REVIEW_OUTPUT_DIR/${jarname}-contents.txt" 2>/dev/null || true

            # Extract META-INF licenses
            unzip -l "$jarfile" 2>/dev/null | grep -i "META-INF.*LICENSE\|META-INF.*NOTICE" > "$REVIEW_OUTPUT_DIR/${jarname}-meta-inf-licenses.txt" || true

            # Extract unique package prefixes to identify bundled libraries
            unzip -l "$jarfile" 2>/dev/null | \
                awk '{print $4}' | \
                grep "\.class$" | \
                sed 's|/[^/]*\.class$||' | \
                cut -d/ -f1-3 | \
                sort -u | \
                head -100 > "$REVIEW_OUTPUT_DIR/${jarname}-packages.txt" || true

            echo "  Contents listed in: $REVIEW_OUTPUT_DIR/${jarname}-contents.txt"
            echo "  Packages listed in: $REVIEW_OUTPUT_DIR/${jarname}-packages.txt"

            # Check for common third-party libraries
            echo "  Checking for common bundled libraries..."
            for lib in "com/google" "org/apache/commons" "com/fasterxml" "io/netty" "org/slf4j" \
                       "scala/collection" "argonaut" "shapeless" "jansi" "akka"; do
                if unzip -l "$jarfile" 2>/dev/null | grep -q "$lib"; then
                    echo "    Found: $lib"
                fi
            done
        fi
    done < "$REVIEW_OUTPUT_DIR/assembly-jars.txt"
else
    echo "✓ No assembly JARs found in build output"
fi

section "8. Running Apache RAT (if available)"

if command -v mvn &> /dev/null; then
    echo "Maven available - you can run: mvn apache-rat:check"
elif [ -f Makefile ] && grep -q "rat\|audit" Makefile; then
    echo "Makefile has audit targets - try: make audit-licenses"
    if [ -f target/rat-results.txt ]; then
        echo "✓ Found existing RAT results at target/rat-results.txt"
    fi
else
    echo "No RAT configuration found"
fi

section "9. Common License Issues to Check Manually"

cat > "$REVIEW_OUTPUT_DIR/manual-review-checklist.md" << 'EOF'
# Manual License Review Checklist

## Assembly JAR Review (if present)

For each assembly JAR found, verify:

- [ ] Extract the JAR and review META-INF folder
- [ ] All bundled third-party libraries are identified
- [ ] Each library's license is included in META-INF or root LICENSE
- [ ] No Category-X licenses (JSON, BSD-4-Clause, etc.) are bundled
- [ ] NOTICE file includes all required attributions

## Common Libraries to Check

If you found these in assembly JARs, verify their licenses are properly documented:

- [ ] argonaut (Apache 2.0)
- [ ] shapeless (Apache 2.0)
- [ ] jansi (Apache 2.0)
- [ ] hawtjni (EPL 1.0 + Apache 2.0)
- [ ] netty (Apache 2.0)
- [ ] akka (Apache 2.0)
- [ ] scala-library (Apache 2.0)
- [ ] guava (Apache 2.0 - check for embedded/modified code)

## Source Code Review

- [ ] All files with non-ASF copyrights are documented in LICENSE
- [ ] No files have duplicate license headers (unless intentional)
- [ ] Derived code properly attributes original authors
- [ ] No proprietary or restrictive licenses in source

## Documentation

- [ ] LICENSE file is complete and accurate
- [ ] NOTICE file has all required attributions
- [ ] README mentions any special license considerations
- [ ] DISCLAIMER file is present (for incubator projects)

## Binary Distributions (if releasing binaries)

- [ ] All binary artifacts include LICENSE and NOTICE
- [ ] Convenience binaries properly document bundled dependencies
- [ ] No GPL/LGPL code linked without proper notice

## Known Problem Areas

- [ ] Check for embedded copies of Apache Commons (should use dependencies)
- [ ] Check for embedded JSON libraries (some have restrictions)
- [ ] Check for native libraries (may have different licenses)
- [ ] Check for test dependencies bundled in main artifacts
- [ ] Check for code copied from Stack Overflow (licensing unclear)

EOF

echo "Created manual review checklist: $REVIEW_OUTPUT_DIR/manual-review-checklist.md"

section "10. Summary"

echo ""
echo "Review complete! Results saved to: $REVIEW_OUTPUT_DIR/"
echo ""
echo "Key files to review:"
echo "  - $REVIEW_OUTPUT_DIR/derived-code.txt"
echo "  - $REVIEW_OUTPUT_DIR/non-asf-copyrights.txt"
echo "  - $REVIEW_OUTPUT_DIR/multiple-headers.txt"
echo "  - $REVIEW_OUTPUT_DIR/manual-review-checklist.md"

if [ -s "$REVIEW_OUTPUT_DIR/assembly-jars.txt" ]; then
    echo ""
    warning "Assembly JARs found - these require extra scrutiny!"
    echo "Review all *-packages.txt files to identify bundled libraries"
fi

echo ""
echo "Next steps:"
echo "1. Review all generated files in $REVIEW_OUTPUT_DIR/"
echo "2. Complete the manual checklist"
echo "3. Verify LICENSE file includes all third-party components"
echo "4. Check assembly JARs contain proper META-INF licenses"
echo ""
