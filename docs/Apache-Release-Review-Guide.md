# Apache Incubator Source Release Review Guide

This guide and accompanying tools help you perform thorough license compliance reviews of Apache Incubator source releases.

> **Note:** This guide is applicable to any Apache project. Examples shown reference Apache Toree, but the methodology and tools work for any Apache Software Foundation release.

## Quick Start

1. **Download the source release and verify signatures**
2. **Extract the source tarball**
3. **Run the automated license review script:**
   ```bash
   ./apache-review-license-compliance.sh
   ```
4. **Copy and fill out the review template:**
   ```bash
   cp APACHE_RELEASE_REVIEW_TEMPLATE.md my-review.md
   # Edit my-review.md with your findings
   ```
5. **Complete the manual checklist**
6. **Cast your vote on the mailing list**

## Tools Provided

### 1. apache-review-license-compliance.sh

Automated script that scans for common license compliance issues.

**What it checks:**
- Derived/copied code from third parties
- Non-ASF copyright statements
- Multiple license headers in single files
- LICENSE file completeness
- Build dependencies
- Assembly/uber JAR contents
- Common bundled libraries

**Usage:**
```bash
./apache-review-license-compliance.sh [source-directory]
```

**Output:**
Creates a timestamped directory with:
- `derived-code.txt` - Files mentioning derivation
- `non-asf-copyrights.txt` - Copyright statements to verify
- `multiple-headers.txt` - Files with potential issues
- `assembly-jars.txt` - List of assembly JARs found
- `*-packages.txt` - Bundled packages for each JAR
- `manual-review-checklist.md` - Items to check manually

### 2. APACHE_RELEASE_REVIEW_TEMPLATE.md

Comprehensive template for documenting your review.

**Sections:**
- Release artifact verification
- License compliance checks
- Build verification
- Source release quality
- Issues identified
- Vote recommendation

**Usage:**
```bash
cp APACHE_RELEASE_REVIEW_TEMPLATE.md toree-0.6.0-rc1-review.md
# Fill in all sections as you complete your review
```

## Review Process

### Phase 1: Verification (15-30 minutes)

1. **Download artifacts:**
   ```bash
   wget https://dist.apache.org/repos/dist/dev/incubator/PROJECT/VERSION/...
   ```

2. **Verify signatures and checksums:**
   ```bash
   # Import KEYS
   wget https://downloads.apache.org/incubator/PROJECT/KEYS
   gpg --import KEYS

   # Verify signature
   gpg --verify apache-PROJECT-VERSION-src.tar.gz.asc

   # Verify checksum
   sha512sum -c apache-PROJECT-VERSION-src.tar.gz.sha512
   ```

3. **Extract source:**
   ```bash
   tar xzf apache-PROJECT-VERSION-src.tar.gz
   cd apache-PROJECT-VERSION-src
   ```

### Phase 2: Automated Scanning (5-10 minutes)

1. **Run license compliance script:**
   ```bash
   ./apache-review-license-compliance.sh
   ```

2. **Review the output directory:**
   ```bash
   ls -la license-review-*/
   cat license-review-*/non-asf-copyrights.txt
   cat license-review-*/derived-code.txt
   ```

3. **Check for assembly JARs (must build first):**
   ```bash
   make build  # or mvn package, sbt assembly, etc.
   ./apache-review-license-compliance.sh
   ```

### Phase 3: Manual Review (30-60 minutes)

Focus areas based on automated scan results:

#### A. License File Review

```bash
# Check LICENSE file mentions all third-party code
cat LICENSE

# For each non-ASF copyright found, verify it's in LICENSE
cat license-review-*/non-asf-copyrights.txt
```

**Common issues:**
- Embedded/derived code (like Guava ClassPath.java)
- Modified third-party files
- Code snippets from other projects

#### B. Assembly JAR Deep Dive

If assembly JARs exist, this is CRITICAL:

```bash
# Find the assembly JAR
find . -name "*-assembly-*.jar"

# Extract and review
JAR="dist/toree/lib/toree-assembly-0.6.0-incubating.jar"
unzip -l "$JAR" > jar-contents.txt

# Check META-INF
unzip "$JAR" 'META-INF/*' -d jar-extracted/
ls -la jar-extracted/META-INF/
```

**What to verify:**
1. All bundled libraries are identified
2. Each library's license is in META-INF or root LICENSE
3. NOTICE attributions are complete
4. No Category-X licenses (JSON license, BSD-4-Clause, etc.)

**Common missing licenses:**
- argonaut, shapeless, jansi, hawtjni
- alexarchambault/windowsansi
- neilalexander/jnacl

#### C. Source File Review

```bash
# Review files with potential issues
cat license-review-*/multiple-headers.txt

# Check specific problem files
head -50 path/to/suspicious/file.java
```

**Red flags:**
- Two license headers in one file
- Guava/Apache Commons code embedded
- Code clearly from Stack Overflow or tutorials
- Generated code without proper attribution

#### D. Build System Review

```bash
# Check Makefile for git dependencies
grep "git " Makefile

# Look for COMMIT variables
grep "COMMIT" Makefile

# Check Docker commands running as root
grep "docker.*--user=root" Makefile
```

### Phase 4: Build and Test (30-60 minutes)

1. **Build from source:**
   ```bash
   make build  # or appropriate command
   ```

2. **Run tests:**
   ```bash
   make test
   ```

3. **Verify build doesn't require git:**
   ```bash
   # Ensure you're not in a git repo
   ls -la .git  # should not exist
   make build  # should succeed
   ```

4. **Try problematic targets:**
   ```bash
   make dist     # should fail gracefully or work
   make release  # should fail gracefully if needs git
   ```

### Phase 5: Documentation (15-30 minutes)

1. **Fill out the review template:**
   ```bash
   cp APACHE_RELEASE_REVIEW_TEMPLATE.md my-review-$(date +%Y%m%d).md
   # Edit and complete all sections
   ```

2. **Document all issues found**

3. **Categorize by severity:**
   - **Critical** - Blocks release (license violations, missing attributions)
   - **Major** - Should fix but might not block
   - **Minor** - Nice to fix

4. **Prepare vote email**

## Common Issues to Watch For

### Critical (Release Blocking)

1. **Missing LICENSE attributions**
   - Embedded third-party code not mentioned
   - Assembly JAR missing bundled library licenses

2. **Category-X licenses bundled**
   - JSON license
   - BSD-4-Clause
   - LGPL/GPL (without proper handling)

3. **Duplicate license headers**
   - File has both ASF and original license header
   - Should keep only original if it's also Apache 2.0

4. **Missing DISCLAIMER** (incubator projects)

### Major

1. **Git dependencies in Makefile**
   - Targets using git that shouldn't
   - Missing guards for git-dependent operations

2. **Incomplete NOTICE file**
   - Missing required attributions
   - Bundled Apache components not listed

3. **Docker permission issues**
   - Root-owned artifacts can't be cleaned

### Minor

1. **Build documentation incomplete**
2. **Non-idempotent make targets**
3. **Vote email formatting**

## Voting

After completing your review:

### +1 (Approve)

```
+1 (binding/non-binding)

I have reviewed the release and:
- Verified signatures and checksums
- Reviewed LICENSE and NOTICE files
- Built from source successfully
- All tests passed (235 tests, 0 failures)
- Verified license compliance

No blocking issues found.
```

### -1 (Block)

**Must provide clear justification:**

```
-1 (binding)

I have reviewed the release and found the following blocking issues:

1. Missing Guava attribution in LICENSE file
   - ClassPath.java is derived from Guava v32.1.2
   - Not mentioned in root LICENSE file
   - See: kernel/src/main/scala/org/apache/toree/utils/ClassPath.java:73

2. Assembly JAR missing third-party licenses
   - toree-assembly-0.6.0-incubating.jar bundles multiple libraries
   - Missing licenses for: argonaut, shapeless, jansi, hawtjni, etc.

These must be fixed before the release can be approved.

Otherwise the release looks good:
- Signatures verified
- Build and tests successful
- Source quality is good
```

## Tips and Tricks

### Quickly check if in git repo
```bash
git rev-parse --git-dir 2>/dev/null && echo "In git repo" || echo "Not in git repo"
```

### Find all license files
```bash
find . -iname "*license*" -o -iname "*notice*" -o -iname "*copying*"
```

### List all Java packages
```bash
find . -name "*.java" | sed 's|/[^/]*\.java$||' | sort -u
```

### Check for common bundled libs
```bash
jar -tf assembly.jar | grep -E "(com/google|org/apache/commons|io/netty|akka)"
```

### Extract just META-INF
```bash
unzip assembly.jar 'META-INF/*' -d extracted/
```

### Compare packages to Maven Central
```bash
# For each package found, check on Maven Central if unsure
# https://search.maven.org/
```

## References

- [Apache Release Policy](https://www.apache.org/legal/release-policy.html)
- [Apache License Policy](https://www.apache.org/legal/resolved.html)
- [Apache RAT](https://creadur.apache.org/rat/)
- [Incubator Release Guide](https://incubator.apache.org/guides/releasemanagement.html)
- [ASF Licensing Howto](https://www.apache.org/legal/src-headers.html)

## Questions?

- Ask on dev@ or general@ mailing list
- Check with Apache Legal if unsure about licensing
- Review past release votes for examples
- Consult the Incubator PMC

---

**Remember:** When in doubt, ask! It's better to raise a question than miss a licensing issue.
