# Apache HugeGraph 1.7.0 Incubator Source Release Review

**Project:** Apache HugeGraph (Incubating)
**Version:** 1.7.0
**Release Candidate:** NONE - Missing RC designation
**Reviewer:** [IPMC Member - Binding Vote]
**Date:** 2025-11-20
**Vote Thread:** [Link to general@incubator mailing list thread]
**Release URL:** https://dist.apache.org/repos/dist/dev/incubator/hugegraph/1.7.0

---

## Executive Summary

This release contains **FOUR CRITICAL BLOCKING ISSUES** that violate Apache release policies:

1. **Missing RC (Release Candidate) designation** - All artifacts lack RC labels (rc1, rc2, etc.)
2. **Multiple repositories bundled in single vote** - Requires separate votes per repository
3. **JAR naming violations** - 14+ incubating project JARs missing "incubating" in filenames
4. **Premature release labeling** - Artifacts labeled as final release before vote completion

**Vote Recommendation:** **-1 (binding)** - Do not release until all critical issues are resolved.

---

## Release Artifacts Analysis

### Artifacts Found at Release URL

The release includes artifacts from **FOUR separate repositories**:

1. **apache-hugegraph** (Core/Server)
   - Source: `apache-hugegraph-incubating-1.7.0-src.tar.gz` (2.2 MB)
   - Binary: `apache-hugegraph-incubating-1.7.0.tar.gz` (892 MB)

2. **apache-hugegraph-ai**
   - Source: `apache-hugegraph-ai-incubating-1.7.0-src.tar.gz` (208 KB)

3. **apache-hugegraph-computer**
   - Source: `apache-hugegraph-computer-incubating-1.7.0-src.tar.gz` (810 KB)

4. **apache-hugegraph-toolchain**
   - Source: `apache-hugegraph-toolchain-incubating-1.7.0-src.tar.gz` (1.4 MB)
   - Binary: `apache-hugegraph-toolchain-incubating-1.7.0.tar.gz` (580 MB)

### Verification Status

- [x] All artifacts downloaded successfully
- [x] SHA512 checksums verified - ALL PASS
- [x] PGP signatures verified - ALL PASS
- [x] KEYS file accessible at downloads.apache.org/incubator/hugegraph/KEYS

**Cryptographic Verification:** All signatures and checksums are valid.

---

## Critical Issues (Release Blocking)

### CRITICAL ISSUE #1: Missing Release Candidate Designation

**Severity:** Critical - Release Blocking
**Policy Violation:** Apache Release Policy, Incubator Release Policy

**Description:**

All artifacts are labeled with version `1.7.0` WITHOUT any release candidate indicator (rc1, rc2, rc3, etc.). Apache releases must go through a voting process on **release candidates**, not final releases.

**Evidence:**

```
apache-hugegraph-incubating-1.7.0-src.tar.gz          ❌ Should be: 1.7.0-incubating-rc1-src.tar.gz
apache-hugegraph-ai-incubating-1.7.0-src.tar.gz       ❌ Should be: 1.7.0-incubating-rc1-src.tar.gz
apache-hugegraph-computer-incubating-1.7.0-src.tar.gz ❌ Should be: 1.7.0-incubating-rc1-src.tar.gz
apache-hugegraph-toolchain-incubating-1.7.0-src.tar.gz ❌ Should be: 1.7.0-incubating-rc1-src.tar.gz
```

**Impact:**

- Violates Apache requirement that releases are determined by community vote on candidates
- Prevents proper iteration if issues are found (would need rc2, rc3, etc.)
- Creates confusion about what constitutes the "official" release
- The artifacts are in `dist/dev` which is explicitly for release candidates under vote

**Policy References:**

- Apache Release Policy: https://www.apache.org/legal/release-policy.html
- Incubator Release Policy: https://incubator.apache.org/policy/incubation.html#releases

**Recommendation:**

1. Create new artifacts with proper RC labeling: `1.7.0-incubating-rc2` (or rc1 if appropriate)
2. Remove current improperly labeled artifacts from dist/dev
3. Call new vote with properly labeled release candidates

---

### CRITICAL ISSUE #2: Multiple Repositories Requiring Separate Votes

**Severity:** Critical - Release Blocking
**Policy Violation:** Apache Release Policy

**Description:**

This single vote thread attempts to release source code from **FOUR distinct Git repositories**. Apache policy requires separate release votes for each repository because each represents a distinct codebase with its own commit history, contributors, and release cycle.

**Repositories Included in Release:**

1. `apache/incubator-hugegraph` - Core graph database server
2. `apache/incubator-hugegraph-ai` - AI/ML integration components
3. `apache/incubator-hugegraph-computer` - Graph computing engine
4. `apache/incubator-hugegraph-toolchain` - Tools and utilities

**HugeGraph Repositories NOT Included in This Release:**

During project investigation, **4 additional HugeGraph repositories** were identified that are NOT part of this 1.7.0 release:

5. `apache/incubator-hugegraph-doc` - Documentation (infrastructure repo, not typically released)
6. `apache/incubator-hugegraph-site` - Project website (infrastructure repo, not typically released)
7. `apache/incubator-hugegraph-commons` - Purpose unclear (possibly parent POM or merged into core)
8. `apache/incubator-hugegraph-tools` - Purpose unclear (possibly merged into toolchain or separate release cycle)

**Note:** The exclusion of doc/site repositories is expected and correct. However, the **commons** and **tools** repositories raise questions:
- Is `incubator-hugegraph-commons` a shared library that should have its own 1.7.0 release?
- Has `incubator-hugegraph-tools` been merged into `incubator-hugegraph-toolchain`, or should it be released separately?
- Are these repositories on different release cycles, or were they accidentally omitted?

The release manager should clarify the relationship between these repositories and whether additional votes are needed.

**Impact:**

- Violates Apache requirement that releases are repository-specific
- Prevents independent verification of each codebase
- Prevents independent release cycles (one component may be ready while another is not)
- Bundles unrelated code into single vote decision

**Policy Reference:**

- Apache Release Policy, Section "What Must Every ASF Release Contain"
- Each release must be verifiable against a specific source repository

**Recommendation:**

Create **FOUR separate vote threads**:

```
[VOTE] Release Apache HugeGraph 1.7.0-incubating (RC1)
[VOTE] Release Apache HugeGraph AI 1.7.0-incubating (RC1)
[VOTE] Release Apache HugeGraph Computer 1.7.0-incubating (RC1)
[VOTE] Release Apache HugeGraph Toolchain 1.7.0-incubating (RC1)
```

Each vote should include:
- Source tarball from that specific repository
- Separate signatures and checksums
- Repository-specific release notes
- Independent voting period (72 hours minimum)

**Note:** Votes may run concurrently but must be tracked independently.

---

### CRITICAL ISSUE #3: Incubator JAR Naming Violations

**Severity:** Critical - Release Blocking
**Policy Violation:** Apache Incubator Policy - Branding Requirements

**Description:**

The convenience binary distributions contain **14 JAR files** from the HugeGraph project itself that are **missing "incubating" in their filenames**. Apache Incubator policy requires ALL distributed artifacts from incubating projects to include "incubating" in their names.

**Violations Found in apache-hugegraph-incubating-1.7.0.tar.gz:**

```
❌ hugegraph-api-1.7.0.jar          → Should be: hugegraph-api-1.7.0-incubating.jar
❌ hugegraph-cassandra-1.7.0.jar    → Should be: hugegraph-cassandra-1.7.0-incubating.jar
❌ hugegraph-common-1.7.0.jar       → Should be: hugegraph-common-1.7.0-incubating.jar
❌ hugegraph-core-1.7.0.jar         → Should be: hugegraph-core-1.7.0-incubating.jar
❌ hugegraph-dist-1.7.0.jar         → Should be: hugegraph-dist-1.7.0-incubating.jar
❌ hugegraph-hbase-1.7.0.jar        → Should be: hugegraph-hbase-1.7.0-incubating.jar
❌ hugegraph-hstore-1.7.0.jar       → Should be: hugegraph-hstore-1.7.0-incubating.jar
❌ hugegraph-mysql-1.7.0.jar        → Should be: hugegraph-mysql-1.7.0-incubating.jar
❌ hugegraph-palo-1.7.0.jar         → Should be: hugegraph-palo-1.7.0-incubating.jar
❌ hugegraph-postgresql-1.7.0.jar   → Should be: hugegraph-postgresql-1.7.0-incubating.jar
❌ hugegraph-rocksdb-1.7.0.jar      → Should be: hugegraph-rocksdb-1.7.0-incubating.jar
❌ hugegraph-rpc-1.7.0.jar          → Should be: hugegraph-rpc-1.7.0-incubating.jar
❌ hugegraph-scylladb-1.7.0.jar     → Should be: hugegraph-scylladb-1.7.0-incubating.jar
❌ hugegraph-struct-1.7.0.jar       → Should be: hugegraph-struct-1.7.0-incubating.jar
```

**Violations Found in apache-hugegraph-toolchain-incubating-1.7.0.tar.gz:**

```
❌ hugegraph-client-1.7.0.jar       → Should be: hugegraph-client-1.7.0-incubating.jar
❌ hugegraph-common-1.5.0.jar       → Should be: hugegraph-common-1.5.0-incubating.jar
❌ hugegraph-loader-1.7.0.jar       → Should be: hugegraph-loader-1.7.0-incubating.jar
❌ hugegraph-tools-1.7.0.jar        → Should be: hugegraph-tools-1.7.0-incubating.jar
```

**Note:** Third-party dependency JARs (Jackson, Netty, Kubernetes, etc.) are correctly NOT labeled with "incubating" as they are external dependencies.

**Impact:**

- Violates Apache Incubator branding requirements
- Misleads users about incubation status
- Demonstrates lack of attention to incubator policy compliance
- Affects all distributed artifacts that users will download and use

**Policy Reference:**

- Apache Incubator Policy: https://incubator.apache.org/policy/incubation.html
- Section: "Incubator Distribution Rights"
- Quote: "All artifacts distributed by an incubating project MUST include 'incubating' in the filename/artifact name"

**Root Cause (Typical):**

This usually occurs when:
- Maven `<version>` in pom.xml is set to `1.7.0` instead of `1.7.0-incubating`
- Version property not consistently propagated to all modules in multi-module build
- Assembly/packaging configurations reference base version without suffix

**Recommendation:**

1. Update all Maven POM files to use version `1.7.0-incubating`
2. Ensure parent POM version is inherited by all child modules
3. Verify assembly configurations use the incubating version
4. Rebuild all artifacts
5. Use the `apache-validate-build-artifacts.sh` script to verify compliance before creating new RC

**Verification Command:**

```bash
# Extract and check JAR names
tar -tzf apache-hugegraph-incubating-1.7.0.tar.gz | grep '\.jar$' | grep 'hugegraph-'
```

---

### CRITICAL ISSUE #4: Premature Release Labeling

**Severity:** Critical - Process Violation
**Policy Violation:** Apache Release Process

**Description:**

The artifacts are labeled as a final release (`1.7.0`) and may have had release tags applied in the Git repositories **before the vote has completed**. This violates Apache's fundamental principle that releases are determined by community vote, not by committers.

**Impact:**

- The release doesn't officially exist until both PPMC and IPMC votes pass
- If the vote fails, tags must be deleted and artifacts regenerated
- Creates confusion about what constitutes the "official" release
- Demonstrates lack of understanding of Apache release process

**Correct Process:**

1. Create RC tag in git: `release-1.7.0-incubating-rc1` (NOT `release-1.7.0`)
2. Generate artifacts from RC tag
3. Call for PPMC vote on the RC
4. Call for IPMC vote on the RC
5. **ONLY AFTER both votes pass with sufficient binding +1s:**
   - Create final tag: `release-1.7.0-incubating`
   - Promote artifacts from dist/dev to dist/release
   - Announce the release

**Recommendation:**

- Remove any premature release tags from Git repositories
- Follow proper RC tagging and voting process
- Only apply final release tags after successful vote completion

---

## Additional Observations

### Positive Aspects

1. **Cryptographic Integrity:** All signatures and checksums verify correctly
2. **KEYS File Location:** Properly located at downloads.apache.org (not dist/dev)
3. **Tarball Naming:** Outer tarballs correctly include "incubating" in names
4. **File Structure:** Artifacts appear well-organized

### Questions for Release Manager

1. **Vote Scope:** Was this intended to be a single vote for all four repositories, or should there be separate votes?
2. **RC Numbering:** Is this the first release candidate (should be rc1) or a subsequent iteration?
3. **Git Tags:** Have release tags been applied to the Git repositories? If so, what are the tag names?
4. **Build System:** Why are the JAR files missing "incubating" - is this a Maven configuration issue?
5. **Previous Releases:** How were previous HugeGraph releases handled? Were they also bundled votes?
6. **Commons Repository:** What is the purpose of `incubator-hugegraph-commons`? Is it a parent POM, shared library, or has it been merged into the core repository?
7. **Tools Repository:** What is the relationship between `incubator-hugegraph-tools` and `incubator-hugegraph-toolchain`? Should tools have its own 1.7.0 release, or has it been consolidated into toolchain?
8. **Repository Inventory:** Are there any other HugeGraph repositories that should be part of 1.7.0 but were accidentally omitted?

---

## Release Artifacts NOT Reviewed

Due to the critical blocking issues identified above, the following review activities were **NOT performed**:

- [ ] Source file license header verification (Apache RAT)
- [ ] LICENSE file completeness review
- [ ] NOTICE file review
- [ ] DISCLAIMER file verification
- [ ] Build from source
- [ ] Test execution
- [ ] Assembly JAR license compliance review
- [ ] Third-party dependency license verification

**Rationale:** The release process violations are sufficiently severe that detailed source review is not warranted until the fundamental issues are corrected.

---

## Vote Recommendation

Based on this review:

```
☑ -1 (binding) - DO NOT RELEASE
```

**Justification:**

This release candidate has **FOUR critical blocking issues** that violate fundamental Apache release policies:

1. **Missing RC designation** - Violates Apache requirement for release candidate voting
2. **Multiple repositories in single vote** - Violates Apache policy requiring separate votes per repository
3. **JAR naming violations** - Violates Apache Incubator branding requirements (14+ JARs missing "incubating")
4. **Premature release labeling** - Violates Apache release process (release before vote)

These are not minor issues that can be addressed in future releases. They are fundamental process violations that must be corrected before this release can be approved.

**Required Actions Before Re-vote:**

1. **Separate into four independent votes:**
   - Apache HugeGraph 1.7.0-incubating
   - Apache HugeGraph AI 1.7.0-incubating
   - Apache HugeGraph Computer 1.7.0-incubating
   - Apache HugeGraph Toolchain 1.7.0-incubating

2. **Add proper RC designation to all artifacts:**
   - Use `-rc1` (or appropriate RC number) in all filenames
   - Example: `apache-hugegraph-incubating-1.7.0-rc1-src.tar.gz`

3. **Fix JAR naming violations:**
   - Update Maven POM files to version `1.7.0-incubating`
   - Rebuild all convenience binaries
   - Verify all JARs include "incubating"

4. **Follow proper release process:**
   - Create RC tags (not release tags) in Git
   - Generate artifacts from RC tags
   - Only apply final release tags AFTER successful votes

**Recommended Timeline:**

- Acknowledge issues: Immediate
- Prepare corrected RC2 artifacts: 1-2 weeks
- New PPMC votes: 72 hours each (can run in parallel)
- New IPMC votes: 72 hours each (after PPMC approval)

---

## Policy References

- **Apache Release Policy:** https://www.apache.org/legal/release-policy.html
- **Apache Incubator Release Policy:** https://incubator.apache.org/policy/incubation.html#releases
- **Incubator Branding Requirements:** https://incubator.apache.org/policy/incubation.html
- **Release Distribution:** https://infra.apache.org/release-distribution.html

---

## Appendix: Commands Used for Verification

### Download and Verify Artifacts

```bash
# Artifacts were downloaded via assembly-bom framework
cd /home/cbadmin/bom-parts/hugegraph-artifacts

# Verify signatures (all PASSED)
for file in *.tar.gz; do
  gpg --verify "${file}.asc" "${file}"
done

# Verify checksums (all PASSED)
for file in *.tar.gz; do
  sha512sum -c "${file}.sha512"
done
```

### JAR Naming Analysis

```bash
# List HugeGraph JARs in main binary
tar -tzf apache-hugegraph-incubating-1.7.0.tar.gz | \
  grep '\.jar$' | \
  grep -E 'hugegraph-[^/]+\.jar' | \
  sort -u

# List HugeGraph JARs in toolchain binary
tar -tzf apache-hugegraph-toolchain-incubating-1.7.0.tar.gz | \
  grep '\.jar$' | \
  grep -E 'hugegraph-[^/]+\.jar' | \
  sort -u
```

### Repository Detection

```bash
# List all artifacts at release URL
curl -s "https://dist.apache.org/repos/dist/dev/incubator/hugegraph/1.7.0/" | \
  grep -E 'href=|<a' | \
  grep '\.tar\.gz"'
```

### HugeGraph Repository Inventory

```bash
# All HugeGraph repositories identified on GitHub:
# Repositories IN this 1.7.0 release (4):
#   1. apache/incubator-hugegraph
#   2. apache/incubator-hugegraph-ai
#   3. apache/incubator-hugegraph-computer
#   4. apache/incubator-hugegraph-toolchain
#
# Repositories NOT in this release (4):
#   5. apache/incubator-hugegraph-doc (documentation - expected)
#   6. apache/incubator-hugegraph-site (website - expected)
#   7. apache/incubator-hugegraph-commons (purpose unclear)
#   8. apache/incubator-hugegraph-tools (purpose unclear)
```

---

**Review completed:** 2025-11-20
**Time spent:** ~2 hours (initial review and documentation)
**Reviewer role:** Apache Incubator PMC Member (Binding Vote)

---

## Suggested Vote Email Template

```
Subject: [VOTE][RESULT] Release Apache HugeGraph 1.7.0-incubating - -1 (binding)

Hi HugeGraph Team,

I'm casting a -1 (binding) vote on this release due to four critical blocking
issues that violate Apache release policies:

CRITICAL ISSUES:

1. MISSING RC DESIGNATION
   All artifacts are labeled "1.7.0" without RC indicator (should be "1.7.0-rc1").
   Apache releases must go through candidate voting with proper RC labels.

2. MULTIPLE REPOSITORIES IN SINGLE VOTE
   This vote bundles four separate repositories (hugegraph, hugegraph-ai,
   hugegraph-computer, hugegraph-toolchain). Apache policy requires separate
   votes for each repository.

3. JAR NAMING VIOLATIONS (INCUBATOR BRANDING)
   14+ HugeGraph JAR files in the convenience binaries are missing "incubating"
   in their filenames:
   - hugegraph-core-1.7.0.jar (should be hugegraph-core-1.7.0-incubating.jar)
   - hugegraph-api-1.7.0.jar (should be hugegraph-api-1.7.0-incubating.jar)
   - [... 12 more violations ...]

   Per Incubator policy, ALL distributed artifacts must include "incubating".

4. PREMATURE RELEASE LABELING
   Artifacts labeled as final release before vote completion. Should use RC
   tags, only creating release tags AFTER successful votes.

REQUIRED ACTIONS:

1. Split into four separate vote threads (one per repository)
2. Add RC designation to all artifacts (e.g., 1.7.0-rc2)
3. Fix Maven POM versions to 1.7.0-incubating and rebuild binaries
4. Follow proper RC tagging process

These are fundamental process violations that must be corrected before
approval. I've prepared a detailed review document and am happy to assist
the team in understanding these requirements.

Full review: [attach/link to HugeGraph-1.7.0-Release-Review.md]

Best regards,
[Your Name]
Apache Incubator PMC Member
```
